import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting

@testable import App

private final class CapturingClient: Client, @unchecked Sendable {
  let eventLoop: any EventLoop
  private let lock = NSLock()
  private var bodies: [String] = []

  init(eventLoop: any EventLoop) { self.eventLoop = eventLoop }

  var sentBodies: [String] { lock.withLock { bodies } }

  func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
    lock.withLock { bodies.append(request.body.map { String(buffer: $0) } ?? "") }
    let banner =
      #"{"id":"b1","scope_type":"platform","scope_value":"","severity":"info","message":"m","expires_at":"2030-01-01T00:00:00Z"}"#
    return eventLoop.makeSucceededFuture(
      ClientResponse(
        status: .created, headers: ["Content-Type": "application/json"],
        body: ByteBuffer(string: banner)))
  }

  func delegating(to eventLoop: any EventLoop) -> any Client { self }
  func logging(to logger: Logger) -> any Client { self }
  func allocating(to byteBufferAllocator: ByteBufferAllocator) -> any Client { self }
}

@Suite("Banner create", .serialized)
struct BannerCreateTests {
  @Test("the create body carries no created_by: admin-api stamps it from the bearer")
  func noCreatedBy() async throws {
    var sent: [String] = []
    try await withApp(configure: configure) { app in
      let client = CapturingClient(eventLoop: app.eventLoopGroup.next())
      app.clients.use { _ in client }
      let user = SessionUser(
        sub: "auth0|admin", name: "Ada", email: nil, roles: ["admin"], accessToken: "t",
        expiry: Date().addingTimeInterval(3600))
      app.sessionUserProvider = { _ in user }
      try await app.testing().test(
        .POST, "banners", headers: ["Content-Type": "application/x-www-form-urlencoded"],
        body: ByteBuffer(
          string:
            "scope_type=platform&scope_value=&severity=info&message=hello&expires_at=2030-01-01T00:00"
        )
      ) { res in
        #expect(res.status == .seeOther)
      }
      sent = client.sentBodies
    }
    let body = try #require(sent.first)
    #expect(body.contains("\"message\":\"hello\""))
    #expect(!body.contains("created_by"))
    #expect(!body.contains("auth0|admin"))
  }
}
