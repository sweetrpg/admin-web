import Testing
import VaporTesting

@testable import App

@Suite("Metrics endpoint")
struct MetricsEndpointTests {
  @Test("GET /metrics serves Prometheus text exposition without a session")
  func servesPrometheusText() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "metrics") { res in
        #expect(res.status == .ok)
        #expect(res.headers.first(name: .contentType) == "text/plain; version=0.0.4")
      }
    }
  }

  @Test("unauthenticated pages still redirect to login")
  func pagesStillRedirect() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "") { res in
        #expect(res.status == .seeOther)
        #expect(res.headers.first(name: .location)?.hasPrefix("/auth/login") == true)
      }
    }
  }
}
