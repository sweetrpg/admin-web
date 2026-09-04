import Vapor

// MARK: - Leaf view models

struct LeafAppCardStatusRow: Content {
  let scopeType: String
  let scopeValue: String
  let displayName: String
  let configured: Bool
  let id: String?
  let enabled: Bool
  let label: String

  init(
    scopeType: String, scopeValue: String, displayName: String,
    record: AppCardStatus?
  ) {
    self.scopeType = scopeType
    self.scopeValue = scopeValue
    self.displayName = displayName
    self.configured = record != nil
    self.id = record?.id
    self.enabled = record?.enabled ?? false
    self.label = record?.label ?? ""
  }
}

/// Flattened, always-present form field values.
struct LeafAppCardStatusForm: Content {
  let enabled: Bool
  let label: String

  static let empty = LeafAppCardStatusForm(enabled: false, label: "")

  init(enabled: Bool, label: String) {
    self.enabled = enabled
    self.label = label
  }

  init(_ status: AppCardStatus) {
    self.enabled = status.enabled
    self.label = status.label
  }
}
