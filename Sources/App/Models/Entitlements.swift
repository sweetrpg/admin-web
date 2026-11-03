import Foundation

/// A key's value as `entitlements-api` reports it: a count or an on/off flag.
enum EntitlementValue: Codable, Equatable, Sendable {
  case count(Int)
  case flag(Bool)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Int.self) {
      self = .count(number)
    } else {
      self = .flag(try container.decode(Bool.self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .count(let number): try container.encode(number)
    case .flag(let on): try container.encode(on)
    }
  }

  /// Text for a form field's `value`; the service decides whether it is valid for the key.
  var formText: String {
    switch self {
    case .count(let number): String(number)
    case .flag(let on): on ? "true" : "false"
    }
  }

  /// Parses admin input in the same shape as `sample`; `nil` when it does not parse.
  static func parse(_ raw: String, like sample: EntitlementValue) -> EntitlementValue? {
    let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
    switch sample {
    case .count: return Int(text).map(EntitlementValue.count)
    case .flag:
      switch text {
      case "true", "on", "yes": return .flag(true)
      case "false", "off", "no": return .flag(false)
      default: return nil
      }
    }
  }

  /// `true` when `self` gives the user less than `other`. Values of different kinds never compare.
  func isLower(than other: EntitlementValue) -> Bool {
    switch (self, other) {
    case (.count(let a), .count(let b)): a < b
    case (.flag(let a), .flag(let b)): !a && b
    default: false
    }
  }
}

/// A tier's contribution to a key (`tier_grants` in the service's explanation).
struct TierGrantLine: Codable, Equatable, Sendable {
  let tierId: String
  let value: EntitlementValue
  let source: String
}

/// One grant, payment or override as `entitlements-api` reports it. `value` is absent on a
/// tier grant; `setBy`, `reason` and `validUntil` are set on overrides.
struct GrantLine: Codable, Equatable, Sendable {
  let source: String
  let value: EntitlementValue?
  let mode: String?
  let productId: String?
  let quantity: Int?
  let reason: String?
  let setBy: String?
  let validUntil: String?
  /// Payment-sourced grants only; all null on grants made before the service recorded them.
  /// `amount` is in minor units. They describe the latest charge, and a bundle repeats the whole
  /// charge on every grant of one purchase.
  let purchasedAt: String?
  let firstPurchasedAt: String?
  let amount: Int?
  let currency: String?

  init(
    source: String, value: EntitlementValue?, mode: String?, productId: String?, quantity: Int?,
    reason: String?, setBy: String?, validUntil: String?, purchasedAt: String? = nil,
    firstPurchasedAt: String? = nil, amount: Int? = nil, currency: String? = nil
  ) {
    self.source = source
    self.value = value
    self.mode = mode
    self.productId = productId
    self.quantity = quantity
    self.reason = reason
    self.setBy = setBy
    self.validUntil = validUntil
    self.purchasedAt = purchasedAt
    self.firstPurchasedAt = firstPurchasedAt
    self.amount = amount
    self.currency = currency
  }
}

/// Everything the service reports for one key of one user (`GET /admin/users/:id/entitlements`).
struct EntitlementRecord: Codable, Equatable, Sendable {
  let key: String
  let type: String
  let `default`: EntitlementValue?
  let tierGrants: [TierGrantLine]
  let grants: [GrantLine]
  let override: GrantLine?
  /// The value from payment-sourced grants alone; the figure an override must not undercut.
  let paid: EntitlementValue
  let payments: [GrantLine]
  let effective: EntitlementValue
}

/// One entry of the entitlements audit trail.
struct AuditEntry: Codable, Equatable, Sendable {
  let at: String
  let actor: String
  let action: String
  let kind: String
  /// `<user id>/<key>` for override writes.
  let subject: String
  let reason: String?
  let paidReduction: Bool?
  let paid: EntitlementValue?
  let reference: String?
  let before: EntitlementValue?
  let after: EntitlementValue?

  init(
    at: String, actor: String, action: String, kind: String = "override", subject: String,
    reason: String? = nil, paidReduction: Bool? = nil, paid: EntitlementValue? = nil,
    reference: String? = nil, before: EntitlementValue? = nil, after: EntitlementValue? = nil
  ) {
    self.at = at
    self.actor = actor
    self.action = action
    self.kind = kind
    self.subject = subject
    self.reason = reason
    self.paidReduction = paidReduction
    self.paid = paid
    self.reference = reference
    self.before = before
    self.after = after
  }

  /// Before and after are free-form on the service; anything that is not a count or flag is
  /// treated as absent rather than failing the whole page.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    at = try c.decode(String.self, forKey: .at)
    actor = try c.decode(String.self, forKey: .actor)
    action = try c.decode(String.self, forKey: .action)
    kind = try c.decode(String.self, forKey: .kind)
    subject = try c.decode(String.self, forKey: .subject)
    reason = try c.decodeIfPresent(String.self, forKey: .reason)
    paidReduction = try c.decodeIfPresent(Bool.self, forKey: .paidReduction)
    reference = try c.decodeIfPresent(String.self, forKey: .reference)
    paid = try? c.decodeIfPresent(EntitlementValue.self, forKey: .paid)
    before = try? c.decodeIfPresent(EntitlementValue.self, forKey: .before)
    after = try? c.decodeIfPresent(EntitlementValue.self, forKey: .after)
  }
}

struct OverrideRequest: Equatable, Sendable {
  let value: EntitlementValue
  let reason: String
  let validUntil: String?
  /// Set only when the admin acknowledged reducing a paid value.
  let paidReductionReference: String?
}

/// The 409 `paid_reduction_not_acknowledged` body: the service's own figures for the warning.
struct PaidReductionDetail: Codable, Equatable, Sendable {
  let key: String
  let paid: EntitlementValue
  let proposed: EntitlementValue
  let payments: [GrantLine]
}

enum EntitlementsError: Error, Equatable {
  case unauthorized
  case forbidden
  case notFound
  /// Message from the service, shown verbatim.
  case validation(String)
  case acknowledgmentRequired(PaidReductionDetail)
  /// The service refuses paid reductions altogether (`paid_reductions_disabled`).
  case paidReductionsDisabled
  case unavailable
}
