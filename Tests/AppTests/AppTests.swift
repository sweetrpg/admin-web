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

  // Renders the real Leaf template directly (bypassing AuthRequiredMiddleware and users-api
  // entirely, same as catalog-web's equivalent header-render test) to confirm the roles/deny
  // entries markup and per-row remove forms interpolate correctly.

  @Test("users list renders roles, deny entries, and remove forms")
  func usersListRendersRolesAndDenyEntries() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-users") { req async throws -> View in
        let summary = LeafUserSummary(
          subject: "abc123", email: "alice@example.com", roles: ["user", "admin"],
          deniedServices: ["catalog"])
        return try await req.view.render(
          "users/list",
          UsersListContext(
            users: [summary],
            isEmpty: false,
            allRoles: UsersController.allRoles,
            user: nil,
            meta: PageMeta(req)
          ))
      }
      try await app.testing().test(.GET, "test-users") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("alice@example.com"))
        #expect(body.contains(#"action="/users/abc123/roles/admin/remove""#))
        #expect(body.contains(#"action="/users/abc123/deny-entries/catalog/remove""#))
        // "admin" and "user" are both already assigned - only the remaining roles should
        // appear as add-role options.
        #expect(!body.contains(#"<option value="admin">"#))
        #expect(body.contains(#"<option value="editor">"#))
      }
    }
  }

  @Test("maintenance-modes list flags an enabled record and an unconfigured scope")
  func maintenanceModesListRendersConfiguredAndUnconfiguredRows() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-maintenance-modes") { req async throws -> View in
        let configured = LeafMaintenanceScopeRow(
          scopeType: .service, scopeValue: "catalog", displayName: "catalog",
          record: MaintenanceMode(
            id: "mm1", scopeType: .service, scopeValue: "catalog", enabled: true,
            startsAt: Date(timeIntervalSince1970: 0), endsAt: nil,
            label: "Catalog down", description: "Migrating data", createdAt: nil,
            updatedAt: nil))
        let unconfigured = LeafMaintenanceScopeRow(
          scopeType: .service, scopeValue: "assets", displayName: "assets", record: nil)
        return try await req.view.render(
          "maintenance-modes/list",
          MaintenanceModeListContext(
            rows: [configured, unconfigured], user: nil, meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-maintenance-modes") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("Catalog down"))
        #expect(body.contains(#"class="tag tag-critical">Maintenance"#))
        #expect(body.contains(#"class="tag tag-outline">Not configured"#))
        #expect(body.contains(#"action="/maintenance-modes/mm1/toggle""#))
        // Human-friendly label in the visible cell, raw RFC3339 preserved in the tooltip -
        // regression coverage for the squished-columns/inconsistent-sizing fix and for the
        // "unreadable timestamp" complaint this replaced.
        #expect(body.contains("Jan 1, 1970, 12:00 AM UTC"))
        #expect(body.contains(#"title="1970-01-01T00:00:00Z""#))
      }
    }
  }
}
