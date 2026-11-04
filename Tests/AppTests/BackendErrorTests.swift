import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting

@testable import App

/// Answers every outgoing request with a canned status and body, or fails like a dead network.
private struct StubClient: Client {
  enum Outcome {
    case respond(HTTPStatus, String)
    case unreachable
  }

  struct Unreachable: Error {}

  let eventLoop: any EventLoop
  let outcome: Outcome

  func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
    switch outcome {
    case .respond(let status, let json):
      let response = ClientResponse(
        status: status, headers: ["Content-Type": "application/json"],
        body: ByteBuffer(string: json))
      return eventLoop.makeSucceededFuture(response)
    case .unreachable:
      return eventLoop.makeFailedFuture(Unreachable())
    }
  }

  func delegating(to eventLoop: any EventLoop) -> any Client {
    StubClient(eventLoop: eventLoop, outcome: outcome)
  }

  func logging(to logger: Logger) -> any Client { self }
  func allocating(to byteBufferAllocator: ByteBufferAllocator) -> any Client { self }
}

private func usersPage(_ outcome: StubClient.Outcome) async throws -> (HTTPStatus, String) {
  var status = HTTPStatus.ok
  var body = ""
  try await withApp(configure: configure) { app in
    app.clients.use { StubClient(eventLoop: $0.eventLoopGroup.next(), outcome: outcome) }
    let user = SessionUser(
      sub: "auth0|admin", name: "Ada", email: nil, roles: ["admin"], accessToken: "t",
      expiry: Date().addingTimeInterval(3600))
    app.sessionUserProvider = { _ in user }
    try await app.testing().test(.GET, "users") { res in
      status = res.status
      body = res.body.string
    }
  }
  return (status, body)
}

@Suite("Backend errors on the users page", .serialized)
struct BackendErrorTests {
  @Test("a 400 shows 'refused' with the backend's message, not 'could not be reached'")
  func badRequestShowsMessage() async throws {
    let (status, body) = try await usersPage(
      .respond(
        .badRequest,
        #"{"error":"invalid_request","message":"X-Acting-User-Sub header is required"}"#))
    #expect(status == .ok)
    #expect(body.contains("refused the request"))
    #expect(body.contains("X-Acting-User-Sub header is required"))
    #expect(!body.contains("could not be reached"))
  }

  @Test("401, 403 and 500 are refusals too, with no message when the body has none")
  func otherStatuses() async throws {
    for status in [HTTPStatus.unauthorized, .forbidden, .internalServerError] {
      let (_, body) = try await usersPage(.respond(status, "{}"))
      #expect(body.contains("refused the request"), "status \(status.code)")
      #expect(!body.contains("Backend message:"), "status \(status.code)")
    }
  }

  @Test("an unreachable backend keeps the original message")
  func unreachable() async throws {
    let (_, body) = try await usersPage(.unreachable)
    #expect(body.contains("could not be reached"))
    #expect(!body.contains("refused the request"))
  }

  @Test("the backend message is escaped on the page")
  func messageEscaped() async throws {
    let (_, body) = try await usersPage(
      .respond(.badRequest, #"{"message":"<script>alert(1)</script>"}"#))
    #expect(!body.contains("<script>alert(1)</script>"))
  }

  @Test("a long message is truncated")
  func messageTruncated() {
    let long = String(repeating: "x", count: 500)
    let error = BackendHTTPError(backend: "auth-api", status: .badRequest, message: long)
    #expect((error.displayMessage?.count ?? 0) <= 203)
  }

  @Test("the logged description carries backend, status and message")
  func description() {
    let error = BackendHTTPError(backend: "auth-api", status: .badRequest, message: "nope")
    #expect(error.description == "auth-api request failed with status 400: nope")
  }
}
