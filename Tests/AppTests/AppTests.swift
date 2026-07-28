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

  @Test("unauthenticated request to root redirects to login")
  func unauthenticatedRedirectsToLogin() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "/") { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location) == "/login")
      }
    }
  }
}
