import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("App")
struct AppTests {
  @Test("status ping responds ok and reports the build version")
  func statusPing() async throws {
    try await withApp(configure: configure) { app in
      try await app.testing().test(.GET, "status/ping") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains(#""version":"dev""#))
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
            unavailable: false,
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

  // Regression coverage for a leaf-kit 1.14.3 gap: `??`/`?.` are lexed but
  // `ParameterResolver.resolve` throws `.unknownError("Future feature")` for `.nilCoalesce`, so
  // any template using `optional?.field ?? "default"` 500s on every render. Both the new-record
  // (no banner/mode passed) and edit (populated) cases must render without throwing.

  @Test("banner form renders for a new banner with no prior values")
  func bannerFormRendersForNewBanner() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-banner-form") { req async throws -> View in
        try await req.view.render(
          "banners/form",
          FormContext(
            formAction: "/banners", isEdit: false, banner: .empty,
            scopeTypes: BannerScopeType.allCases.map(\.rawValue),
            severities: BannerSeverity.allCases.map(\.rawValue), user: nil, meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-banner-form") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("Create banner"))
      }
    }
  }

  @Test("banner form renders for an existing banner with its values preselected")
  func bannerFormRendersForExistingBanner() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-banner-form-edit") { req async throws -> View in
        let banner = Banner(
          id: "b1", scopeType: .service, scopeValue: "catalog", severity: .warning,
          message: "Degraded performance", startsAt: nil,
          expiresAt: Date(timeIntervalSince1970: 0), createdBy: nil, createdAt: nil,
          updatedAt: nil)
        return try await req.view.render(
          "banners/form",
          FormContext(
            formAction: "/banners/b1", isEdit: true, banner: LeafBannerForm(banner),
            scopeTypes: BannerScopeType.allCases.map(\.rawValue),
            severities: BannerSeverity.allCases.map(\.rawValue), user: nil, meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-banner-form-edit") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("Degraded performance"))
        #expect(body.contains(#"<option value="warning"  selected >warning</option>"#))
      }
    }
  }

  private struct FooterContext: Content {
    let meta: PageMeta
  }

  @Test("footer shows the build hash truncated to 8 chars")
  func footerShowsTruncatedBuildHash() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-footer") { req async throws -> View in
        try await req.view.render("partials/footer", FooterContext(meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-footer") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        // BuildInfo.load() falls back to sha "unset" outside a container (no BUILD_INFO_PATH) -
        // shorter than 8 chars, so this also covers prefix(_:) being a safe no-op on a short
        // string, same rationale as assets-web's own truncation fix.
        #expect(body.contains("built unknown / unset"))
      }
    }
  }

  @Test("maintenance-mode form renders for an unconfigured scope")
  func maintenanceModeFormRendersForUnconfiguredScope() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-maintenance-form") { req async throws -> View in
        try await req.view.render(
          "maintenance-modes/form",
          MaintenanceModeFormContext(
            formAction: "/maintenance-modes", displayName: "assets", scopeType: "service",
            scopeValue: "assets", isEdit: false, mode: .empty, user: nil, meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-maintenance-form") { res in
        #expect(res.status == .ok)
        #expect(res.body.string.contains("Configure"))
      }
    }
  }

  @Test("maintenance-mode form renders for an already-configured scope")
  func maintenanceModeFormRendersForConfiguredScope() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-maintenance-form-edit") { req async throws -> View in
        let mode = MaintenanceMode(
          id: "mm1", scopeType: .service, scopeValue: "catalog", enabled: true,
          startsAt: Date(timeIntervalSince1970: 0), endsAt: nil, label: "Catalog down",
          description: "Migrating data", createdAt: nil, updatedAt: nil)
        return try await req.view.render(
          "maintenance-modes/form",
          MaintenanceModeFormContext(
            formAction: "/maintenance-modes", displayName: "catalog", scopeType: "service",
            scopeValue: "catalog", isEdit: true, mode: LeafMaintenanceModeForm(mode), user: nil,
            meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-maintenance-form-edit") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("Catalog down"))
        #expect(body.contains("Migrating data"))
        #expect(body.contains("checked"))
      }
    }
  }

  private struct HeaderContext: Content {
    let user: LeafUser?
    let meta: PageMeta
  }

  @Test("header renders the avatar menu with identity, gravatar fallback, and user settings link")
  func headerRendersAvatarMenuForLoggedInUser() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-header") { req async throws -> View in
        let user = LeafUser(
          SessionUser(
            sub: "abc123", name: "Alice Example", email: "alice@example.com", roles: ["admin"],
            accessToken: "test-access-token",
            expiry: Date().addingTimeInterval(3600)))
        return try await req.view.render(
          "partials/header", HeaderContext(user: user, meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-header") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains(#"class="avatar-menu-trigger""#))
        #expect(body.contains(#"class="avatar-menu-name">Alice Example"#))
        #expect(body.contains(#"class="avatar-menu-email">alice@example.com"#))
        #expect(body.contains(#"href="/users/profile">User Settings"#))
        #expect(body.contains(#"action="/auth/logout?return_to=/test-header" method="post""#))
        // f70df121d renamed the nav-brand link text to "Administration"; the avatar menu itself
        // still has no self-referential "Administration" item - its entries are only
        // User Settings / Log out / the theme row.
        #expect(body.contains(#">Administration</a>"#))
      }
    }
  }

  @Test("header renders the app switcher with four destinations and no admin link")
  func headerRendersAppSwitcher() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-header") { req async throws -> View in
        try await req.view.render(
          "partials/header", HeaderContext(user: nil, meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-header") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("app-switcher-trigger"))
        #expect(body.contains(#"href="/">Main"#))
        #expect(body.contains(#"href="/catalog">Catalog"#))
        #expect(body.contains(#"href="/shelf">Shelf"#))
        #expect(body.contains(#"href="/initiative">Initiative"#))
        #expect(!body.contains(#"app-switcher-item" href="/admin""#))
      }
    }
  }

  @Test("header falls back to the mystery-man avatar when logged out")
  func headerRendersLoggedOutFallback() async throws {
    try await withApp { app in
      app.views.use(.leaf)
      app.get("test-header-logged-out") { req async throws -> View in
        try await req.view.render(
          "partials/header", HeaderContext(user: nil, meta: PageMeta(req)))
      }
      try await app.testing().test(.GET, "test-header-logged-out") { res in
        #expect(res.status == .ok)
        let body = res.body.string
        #expect(body.contains("mystery-man.svg"))
        #expect(
          body.contains(
            #"class="avatar-menu-item" href="/auth/login?return_to=/test-header-logged-out">Log in"#
          ))
      }
    }
  }

  @Test("SessionUser decodes auth-web's RFC 3339 expiry, not a raw Double")
  func sessionUserDecodesRFC3339Expiry() throws {
    // Exactly the shape auth-web's SessionUserAccess now writes (see auth-web's
    // fix/session-expiry-iso8601) - docs/frontend-conventions.md's "Shared session schema"
    // documents `expiry` as an RFC 3339 string, not the raw Double a plain JSONDecoder's
    // .deferredToDate default would expect.
    let json = """
      {"sub":"auth0|abc","name":"Ada","email":"ada@example.com","roles":["admin"],\
      "accessToken":"test-access-token","expiry":"2027-01-15T08:00:00Z"}
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let user = try decoder.decode(SessionUser.self, from: Data(json.utf8))
    #expect(user.name == "Ada")
    #expect(user.expiry.timeIntervalSince1970 == 1_800_000_000)
  }
}
