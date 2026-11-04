import Vapor

struct LeafLine: Content {
  let label: String
  let value: String
}

struct LeafEntitlementRow: Content {
  let key: String
  let type: String
  /// Where the effective value comes from, in one word: override, purchased or default.
  let sourceHint: String
  let hasPaid: Bool
  let charges: [LeafLine]
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

struct EntitlementKeyContext: Content {
  let userID: String
  let row: LeafEntitlementRow
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
  /// One line per purchase (not per grant), with amount and date or "not recorded".
  let charges: [LeafLine]
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

  /// One charge per purchase: grants sharing a product and purchase time are one bundle, and the
  /// service repeats the whole charge on each, so it is shown once and never summed.
  static func charges(_ payments: [GrantLine], l10n: [String: String]) -> [LeafLine] {
    let notRecorded = l10n["entitlements_not_recorded"] ?? "not recorded"
    var seen = Set<String>()
    var lines: [LeafLine] = []
    for payment in payments {
      let product = payment.productId ?? payment.source
      let id = "\(product)|\(payment.purchasedAt ?? "")"
      guard seen.insert(id).inserted else { continue }
      let amount =
        payment.amount.map { formatAmount($0, currency: payment.currency) } ?? notRecorded
      let date = payment.purchasedAt.map { String($0.prefix(10)) } ?? notRecorded
      lines.append(LeafLine(label: product, value: "\(amount), \(date)"))
    }
    return lines
  }

  /// Minor units to a decimal amount; assumes two decimal places, which holds for the currencies
  /// the platform bills in.
  static func formatAmount(_ minor: Int, currency: String?) -> String {
    let text = String(format: "%d.%02d", minor / 100, abs(minor % 100))
    return currency.map { "\(text) \($0.uppercased())" } ?? text
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
    let hint =
      override != nil
      ? "entitlements_source_override"
      : (record.payments.isEmpty ? "entitlements_source_default" : "entitlements_source_purchased")
    return LeafEntitlementRow(
      key: record.key,
      type: record.type,
      sourceHint: l10n[hint] ?? hint,
      hasPaid: !record.payments.isEmpty,
      charges: charges(record.payments, l10n: l10n),
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
