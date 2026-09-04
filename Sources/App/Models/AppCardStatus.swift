import Foundation
import Vapor

/// Mirrors admin-api's `AppCardStatus` shape per
/// openspec/changes/admin-managed-app-card-status in sweetrpg/platform.
struct AppCardStatus: Content {
  let id: String
  var scopeType: String
  var scopeValue: String
  var enabled: Bool
  var label: String
  let createdAt: Date?
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case scopeType = "scope_type"
    case scopeValue = "scope_value"
    case enabled
    case label
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// Create/update payload. `id` is assigned server-side, so it's omitted here.
struct AppCardStatusInput: Content {
  var scopeType: String
  var scopeValue: String
  var enabled: Bool
  var label: String

  enum CodingKeys: String, CodingKey {
    case scopeType = "scope_type"
    case scopeValue = "scope_value"
    case enabled
    case label
  }
}

/// The fixed set of service scopes the admin list view always shows a row for, even when
/// no record exists yet - mirrors `KnownServiceScope` used by maintenance modes.
enum AppCardScopeType {
  static let all = KnownServiceScope.all

  /// Maps a raw scope value to a display-friendly, localized name via `app_card.scope.<value>`.
  static func displayName(for scope: String, req: Request) -> String {
    let lingo = try? req.application.lingoVapor.lingo()
    let key = "app_card.scope.\(scope)"
    return lingo?.localize(key, locale: lingo?.defaultLocale ?? "en") ?? key
  }
}
