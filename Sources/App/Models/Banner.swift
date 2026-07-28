import Foundation
import Vapor

enum BannerScopeType: String, Content, CaseIterable {
  case platform
  case service
  case page
}

enum BannerSeverity: String, Content, CaseIterable {
  case info
  case warning
  case critical
}

/// Mirrors admin-api's `BannerMessage` shape per
/// openspec/changes/add-banner-messages/specs/banner-messages/spec.md in sweetrpg/platform.
struct Banner: Content {
  let id: String
  var scopeType: BannerScopeType
  var scopeValue: String
  var severity: BannerSeverity
  var message: String
  var startsAt: Date?
  var expiresAt: Date
  let createdBy: String?
  let createdAt: Date?
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case scopeType = "scope_type"
    case scopeValue = "scope_value"
    case severity
    case message
    case startsAt = "starts_at"
    case expiresAt = "expires_at"
    case createdBy = "created_by"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  enum Status: String {
    case active
    case expired
    case scheduled
  }

  func status(asOf now: Date = Date()) -> Status {
    if expiresAt <= now { return .expired }
    if let startsAt, startsAt > now { return .scheduled }
    return .active
  }
}

/// Create/update payload. `id` is assigned server-side, so it's omitted here.
struct BannerInput: Content {
  var scopeType: BannerScopeType
  var scopeValue: String
  var severity: BannerSeverity
  var message: String
  var startsAt: Date?
  var expiresAt: Date

  enum CodingKeys: String, CodingKey {
    case scopeType = "scope_type"
    case scopeValue = "scope_value"
    case severity
    case message
    case startsAt = "starts_at"
    case expiresAt = "expires_at"
  }
}
