import Vapor

struct LeafLine: Content {
  let label: String
  let value: String
}

struct LeafEntitlementRow: Content {
  let key: String
  let defaultValue: String
  let effective: String
  let paid: String
  let hasPayments: Bool
  let payments: [LeafLine]
  let tierGrants: [LeafLine]
  let grants: [LeafLine]
  let hasOverride: Bool
  let overrideValue: String
  let overrideReason: String
  let overrideSetBy: String
  let overrideValidUntil: String
  /// The override gives the user less than they paid for.
  let reducesPaid: Bool
  /// The reference an administrator gave when acknowledging that reduction, from the audit trail.
  let paidReductionReference: String
  /// Pre-filled into the override form: the override if there is one, else the effective value.
  let formValue: String
}

struct LeafAuditRow: Content {
  let at: String
  let actor: String
  let key: String
  let change: String
  let reason: String
  let reference: String
}

struct EntitlementsPageContext: Content {
  let userID: String
  let rows: [LeafEntitlementRow]
  let audit: [LeafAuditRow]
  let auditUnavailable: Bool
  /// `entitlements-api` could not be reached; the page shows a message and no edit controls.
  let unavailable: Bool
  let notFound: Bool
  let errorMessage: String?
  let user: LeafUser?
  let meta: PageMeta
}

struct EntitlementConfirmContext: Content {
  let userID: String
  let key: String
  let isPaidReduction: Bool
  let isLowering: Bool
  let isRemove: Bool
  let value: String
  let reason: String
  let validUntil: String
  let current: String
  let proposed: String
  let paid: String
  let payments: [LeafLine]
  let reference: String
  let errorMessage: String?
  let user: LeafUser?
  let meta: PageMeta
}

/// Turns service data into display strings. Pure, so it is tested without a request.
enum EntitlementsPresenter {
  static func display(_ value: EntitlementValue, l10n: [String: String]) -> String {
    switch value {
    case .count(let number): String(number)
    case .flag(let on): l10n[on ? "entitlements_flag_on" : "entitlements_flag_off"] ?? "\(on)"
    }
  }

  static func line(_ grant: GrantLine, l10n: [String: String]) -> LeafLine {
    var label = grant.source
    if let product = grant.productId { label += " \(product)" }
    if let quantity = grant.quantity, quantity > 0 { label += " x\(quantity)" }
    if let until = grant.validUntil { label += " (\(until))" }
    return LeafLine(label: label, value: grant.value.map { display($0, l10n: l10n) } ?? "")
  }

  static func row(
    _ record: EntitlementRecord, audit: [AuditEntry], l10n: [String: String]
  ) -> LeafEntitlementRow {
    let override = record.override
    let reduces = override?.value.map { $0.isLower(than: record.paid) } ?? false
    let reference =
      reduces
      ? audit.first {
        $0.paidReduction == true && $0.subject.hasSuffix("/" + record.key)
      }?.reference ?? "" : ""
    return LeafEntitlementRow(
      key: record.key,
      defaultValue: record.default.map { display($0, l10n: l10n) } ?? "",
      effective: display(record.effective, l10n: l10n),
      paid: display(record.paid, l10n: l10n),
      hasPayments: !record.payments.isEmpty,
      payments: record.payments.map { line($0, l10n: l10n) },
      tierGrants: record.tierGrants.map {
        LeafLine(label: "\($0.tierId) (\($0.source))", value: display($0.value, l10n: l10n))
      },
      grants: record.grants.filter { $0.mode != "override" }.map { line($0, l10n: l10n) },
      hasOverride: override != nil,
      overrideValue: override?.value.map { display($0, l10n: l10n) } ?? "",
      overrideReason: override?.reason ?? "",
      overrideSetBy: override?.setBy ?? "",
      overrideValidUntil: override?.validUntil ?? "",
      reducesPaid: reduces,
      paidReductionReference: reference,
      formValue: (override?.value ?? record.effective).formText)
  }

  static func auditRow(_ entry: AuditEntry, l10n: [String: String]) -> LeafAuditRow {
    let key = entry.subject.split(separator: "/").last.map(String.init) ?? entry.subject
    let before = entry.before.map { display($0, l10n: l10n) } ?? "-"
    let after = entry.after.map { display($0, l10n: l10n) } ?? "-"
    return LeafAuditRow(
      at: entry.at, actor: entry.actor, key: key, change: "\(before) -> \(after)",
      reason: entry.reason ?? "", reference: entry.reference ?? "")
  }
}
