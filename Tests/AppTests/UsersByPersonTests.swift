import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting

@testable import App

/// Answers by URL path so the Users page can be driven end to end against canned backends.
private final class PathClient: Client, @unchecked Sendable {
  let eventLoop: any EventLoop
  let routes: [String: (HTTPStatus, String)]
  private let lock = NSLock()
  private var urls: [String] = []

  init(eventLoop: any EventLoop, routes: [String: (HTTPStatus, String)]) {
    self.eventLoop = eventLoop
    self.routes = routes
  }

  var requested: [String] { lock.withLock { urls } }

  func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
    let url = request.url.string
    lock.withLock { urls.append(url) }
    let match = routes.first { url.contains($0.key) }?.value ?? (.notFound, "{}")
    return eventLoop.makeSucceededFuture(
      ClientResponse(
        status: match.0, headers: ["Content-Type": "application/json"],
        body: ByteBuffer(string: match.1)))
  }

  func delegating(to eventLoop: any EventLoop) -> any Client { self }
  func logging(to logger: Logger) -> any Client { self }
  func allocating(to byteBufferAllocator: ByteBufferAllocator) -> any Client { self }
}

private let people = """
  [{"id":"u1","email":"ada@example.com","subject":"auth0|a","subjects":["auth0|a","github|a"]},
   {"id":"u2","email":"bob@example.com","subject":"auth0|b","subjects":["auth0|b"]}]
  """
private let roles = """
  [{"subject":"auth0|a","roles":["user","editor"],"deniedServices":["catalog"]},
   {"subject":"auth0|b","roles":["user"],"deniedServices":[]}]
  """
private let services = #"[{"id":"catalog","name":"Catalog"},{"id":"game-room","name":"Game Room"}]"#

private func usersPage(
  _ routes: [String: (HTTPStatus, String)]
) async throws -> (body: String, urls: [String]) {
  var body = ""
  var urls: [String] = []
  try await withApp(configure: configure) { app in
    let client = PathClient(eventLoop: app.eventLoopGroup.next(), routes: routes)
    app.clients.use { _ in client }
    let user = SessionUser(
      sub: "auth0|admin", name: "Ada", email: nil, roles: ["admin"], accessToken: "t",
      expiry: Date().addingTimeInterval(3600))
    app.sessionUserProvider = { _ in user }
    try await app.testing().test(.GET, "users") { body = $0.body.string }
    urls = client.requested
  }
  return (body, urls)
}

@Suite("Users page by person", .serialized)
struct UsersByPersonTests {
  @Test("one row per person, linked logins shown, roles asked for with one subject per person")
  func rowsByPerson() async throws {
    let (body, urls) = try await usersPage([
      "/admin/users": (.ok, people), "/api/admin/roles": (.ok, roles),
      "/api/admin/services": (.ok, services),
    ])
    #expect(body.components(separatedBy: "<td>ada@example.com").count - 1 == 1)
    #expect(body.contains("auth0|a") && body.contains("github|a"))
    let rolesCall = try #require(urls.first { $0.contains("/api/admin/roles") })
    #expect(rolesCall.contains("auth0%7Ca") || rolesCall.contains("auth0|a"))
    #expect(!rolesCall.contains("github"))
    #expect(body.contains("/users/auth0%7Ca/roles"))
  }

  @Test("the deny form is a select fed from auth-api's service list")
  func servicesSelect() async throws {
    let (body, _) = try await usersPage([
      "/admin/users": (.ok, people), "/api/admin/roles": (.ok, roles),
      "/api/admin/services": (.ok, services),
    ])
    #expect(body.contains(#"<option value="catalog">Catalog</option>"#))
    #expect(body.contains(#"<option value="game-room">Game Room</option>"#))
    #expect(!body.contains(#"name="service" aria-label="Service to deny" placeholder"#))
  }

  @Test("an unloadable service list shows a message instead of a guessed form")
  func servicesUnavailable() async throws {
    let (body, _) = try await usersPage([
      "/admin/users": (.ok, people), "/api/admin/roles": (.ok, roles),
      "/api/admin/services": (.internalServerError, "{}"),
    ])
    #expect(body.contains("could not be loaded"))
    #expect(!body.contains(#"name="service""#))
    #expect(body.contains("ada@example.com"))
  }

  @Test("an older users-api without subjects falls back to the single subject")
  func olderUsersAPI() async throws {
    let old = #"[{"id":"u1","email":"ada@example.com","subject":"auth0|a"}]"#
    let (body, _) = try await usersPage([
      "/admin/users": (.ok, old), "/api/admin/roles": (.ok, roles),
      "/api/admin/services": (.ok, services),
    ])
    #expect(body.contains("ada@example.com") && body.contains("auth0|a"))
  }

  @Test("an email-less user shows the best readable identity under the subject tags")
  func emailLessLabelOnPage() async throws {
    let json = """
      [{"id":"u9","email":"","name":"Sha Zean","username":"","subject":"github|34924976","subjects":["github|34924976"]}]
      """
    let (body, _) = try await usersPage([
      "/admin/users": (.ok, json),
      "/api/admin/roles": (
        .ok, #"[{"subject":"github|34924976","roles":["user"],"deniedServices":[]}]"#
      ),
      "/api/admin/services": (.ok, services),
    ])
    #expect(body.contains("<td>Sha Zean"))
    #expect(body.contains("github|34924976"))
  }
}

@Suite("UserIdentity.displayLabel")
struct DisplayLabelTests {
  private func identity(_ json: String) throws -> UserIdentity {
    try JSONDecoder().decode(UserIdentity.self, from: Data(json.utf8))
  }

  @Test("email wins")
  func email() throws {
    let user = try identity(
      #"{"id":"u","email":"a@b.c","username":"ab","name":"A B","subjects":["x|1"]}"#)
    #expect(user.displayLabel == "a@b.c")
  }

  @Test("then username")
  func username() throws {
    let user = try identity(
      #"{"id":"u","email":"","username":"shazean","name":"Sha","subjects":["x|1"]}"#)
    #expect(user.displayLabel == "shazean")
  }

  @Test("then name")
  func name() throws {
    let user = try identity(
      #"{"id":"u","email":"","username":"","name":"Sha Zean","subjects":["x|1"]}"#)
    #expect(user.displayLabel == "Sha Zean")
  }

  @Test("the provisioning placeholder User does not count as a name")
  func placeholder() throws {
    let user = try identity(#"{"id":"u","email":"","name":"User","subjects":["github|1"]}"#)
    #expect(user.displayLabel == "github|1")
  }

  @Test("then the first subject, then the id")
  func subjectThenID() throws {
    #expect(
      try identity(#"{"id":"u","email":"","subjects":["github|1","auth0|2"]}"#).displayLabel
        == "github|1")
    #expect(try identity(#"{"id":"u","email":"","subjects":[]}"#).displayLabel == "u")
  }
}
