import Vapor

// MARK: - Leaf view models

/// Human-friendly "Aug 4, 2026, 12:00 AM UTC" rendering, fixed to UTC/en_US_POSIX so output is
/// deterministic regardless of the server's locale/timezone - the raw RFC3339 value (from
/// `ISO8601DateFormatter`) still goes in the row's `*Rfc` field for a tooltip, so nothing about
/// the exact instant is lost, just no longer the only thing shown.
private let humanDateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "UTC")
  formatter.dateFormat = "MMM d, yyyy, h:mm a 'UTC'"
  return formatter
}()

struct LeafMaintenanceScopeRow: Content {
  let scopeType: String
  let scopeValue: String
  let displayName: String
  let configured: Bool
  let id: String?
  let enabled: Bool
  let isStale: Bool
  let label: String
  let startsAtLabel: String
  let startsAtRfc: String
  let endsAtLabel: String
  let endsAtRfc: String

  init(
    scopeType: MaintenanceScopeType, scopeValue: String, displayName: String,
    record: MaintenanceMode?
  ) {
    self.scopeType = scopeType.rawValue
    self.scopeValue = scopeValue
    self.displayName = displayName
    self.configured = record != nil
    self.id = record?.id
    self.enabled = record?.enabled ?? false
    self.isStale = record?.isStale ?? false
    self.label = record?.label ?? ""
    self.startsAtLabel = record.map { humanDateFormatter.string(from: $0.startsAt) } ?? ""
    self.startsAtRfc = record.map { ISO8601DateFormatter().string(from: $0.startsAt) } ?? ""
    self.endsAtLabel = record?.endsAt.map { humanDateFormatter.string(from: $0) } ?? "\u{2014}"
    self.endsAtRfc = record?.endsAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
  }
}

/// Flattened, always-present form field values - defaults resolved here in Swift (`??`) rather
/// than in the Leaf template. See `LeafBannerForm`'s doc comment: leaf-kit 1.14.3 lexes `??`
/// but throws `.unknownError("Future feature")` when actually resolving it, so
/// `maintenance-modes/form.leaf`'s prior `mode?.field ?? ""` usage 500'd on every render.
struct LeafMaintenanceModeForm: Content {
  let enabled: Bool
  let startsAt: String
  let endsAt: String
  let label: String
  let description: String

  static let empty = LeafMaintenanceModeForm(
    enabled: false, startsAt: "", endsAt: "", label: "", description: ""
  )

  init(enabled: Bool, startsAt: String, endsAt: String, label: String, description: String) {
    self.enabled = enabled
    self.startsAt = startsAt
    self.endsAt = endsAt
    self.label = label
    self.description = description
  }

  init(_ mode: MaintenanceMode) {
    self.enabled = mode.enabled
    self.startsAt = Self.formatDateTimeLocal(mode.startsAt)
    self.endsAt = mode.endsAt.map(Self.formatDateTimeLocal) ?? ""
    self.label = mode.label
    self.description = mode.description
  }

  private static func formatDateTimeLocal(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
  }
}
