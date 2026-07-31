import Testing
import VaporTesting

@testable import App

@Suite("App")
struct AppTests {
  @Test("status ping responds ok")
  func statusPing() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "status/ping") { res in
        #expect(res.status == .ok)
      }
    }
  }

  @Test("unauthenticated request to root redirects to auth-web's login")
  func unauthenticatedRedirectsToLogin() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "/") { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location) == "/auth/login?return_to=/")
      }
    }
  }

  @Test(
    "a request with a session cookie but no reachable shared-session Redis still redirects to login"
  )
  func failsOpenWhenSharedSessionRedisUnreachable() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(
        .GET, "/",
        beforeRequest: { req in
          req.headers.add(name: .cookie, value: "\(sharedSessionCookieName)=some-session-id")
        }
      ) { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location) == "/auth/login?return_to=/")
      }
    }
  }
}
