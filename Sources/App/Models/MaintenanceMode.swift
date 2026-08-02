import Foundation
import Vapor

enum MaintenanceScopeType: String, Content, CaseIterable {
  case platform
  case service
}

/// Mirrors admin-api's `MaintenanceMode` shape per
/// openspec/changes/maintenance-mode/specs/maintenance-modes/spec.md in sweetrpg/platform.
struct MaintenanceMode: Content {
  let id: String
  var scopeType: MaintenanceScopeType
  var scopeValue: String
  var enabled: Bool
  var startsAt: Date
  var endsAt: Date?
  var label: String
  var description: String
  let createdAt: Date?
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case scopeType = "scope_type"
    case scopeValue = "scope_value"
    case enabled
    case startsAt = "starts_at"
    case endsAt = "ends_at"
    case label
    case description
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  /// True when `enabled` but `ends_at` has already passed - admin-api's `enabled` flag
  /// doesn't auto-clear on expiry (dates are informational only), so the admin list view
  /// flags this as a likely-stale record per tasks.md 2.2.
  var isStale: Bool {
    guard enabled, let endsAt else { return false }
    return endsAt <= Date()
  }
}

/// Create/update payload. `id` is assigned server-side, so it's omitted here.
struct MaintenanceModeInput: Content {
  var scopeType: MaintenanceScopeType
  var scopeValue: String
  var enabled: Bool
  var startsAt: Date
  var endsAt: Date?
  var label: String
  var description: String

  enum CodingKeys: String, CodingKey {
    case scopeType = "scope_type"
    case scopeValue = "scope_value"
    case enabled
    case startsAt = "starts_at"
    case endsAt = "ends_at"
    case label
    case description
  }
}

/// The fixed set of service scopes the admin list view always shows a row for, even when
/// no record exists yet - the per-app frontends named in platform's maintenance-mode
/// change tasks.md 3-4 (main-web's badge plus every consuming frontend's maintenance
/// page). Kept in sync by hand, same as `BannerScopeType`'s mirror of admin-api's Go enum.
enum KnownServiceScope {
  static let all = [
    "main", "catalog", "assets", "auth", "directory", "initiative", "shelf", "users", "shared",
  ]
}
