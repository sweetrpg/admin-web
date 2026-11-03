import Tracing
import Vapor

/// Per-user entitlements page: why each key has its value, and set/replace/remove an override.
/// Every route is already gated by `AuthRequiredMiddleware`'s blanket `admin`-role check, and
/// every `entitlements-api` call forwards the acting admin's own token so the service verifies
/// the role itself. admin-web decides nothing about values; type and range checks come back from
/// the service and are shown verbatim.
struct UserEntitlementsController: RouteCollection {
  /// The path parameter is named `subject` only because the router refuses two routes that
  /// share a prefix but name the parameter differently (`UsersController` uses `:subject`);
  /// here it carries `users-api`'s canonical user ID.
  func boot(routes: RoutesBuilder) throws {
    routes.get("users", ":subject", "entitlements", use: show)
    routes.post("users", ":subject", "entitlements", ":key", "override", use: setOverride)
    routes.post("users", ":subject", "entitlements", ":key", "remove", use: removeOverride)
  }

  private struct OverrideForm: Content {
    var value: String?
    var reason: String?
    var validUntil: String?
    var confirmed: String?
    var acknowledged: String?
    var reference: String?
  }

  private func context(_ req: Request) async throws -> (userID: String, key: String?, token: String)
  {
    guard let userID = req.parameters.get("subject") else { throw Abort(.badRequest) }
    guard let token = (await req.currentUser)?.accessToken else {
      throw Abort(.internalServerError, reason: "No acting user session found")
    }
    return (userID, req.parameters.get("key"), token)
  }

  private func encoded(_ userID: String) -> String {
    userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
  }

  // MARK: Page

  @Sendable
  func show(req: Request) async throws -> View {
    try await withSpan("show-user-entitlements") { _ in
      let (userID, _, token) = try await context(req)
      return try await renderPage(req, userID: userID, token: token, errorMessage: nil)
    }
  }

  /// Reads the service and renders the page. A failed read shows a message and no edit controls,
  /// never stale or partial values; a failed audit read hides only the history section.
  private func renderPage(
    _ req: Request, userID: String, token: String, errorMessage: String?
  ) async throws -> View {
    let l10n = req.l10n
    let user = (await req.currentUser).map(LeafUser.init)
    var rows: [LeafEntitlementRow] = []
    var audit: [LeafAuditRow] = []
    var auditUnavailable = false
    var unavailable = false
    var notFound = false
    do {
      let records = try await req.entitlements.read(userID: userID, accessToken: token)
      let entries: [AuditEntry]
      do {
        entries = try await req.entitlements.recentAudit(userID: userID, accessToken: token)
      } catch {
        req.logger.warning("entitlements audit read failed: \(error)")
        entries = []
        auditUnavailable = true
      }
      rows = records.map { EntitlementsPresenter.row($0, audit: entries, l10n: l10n) }
      audit = entries.map { EntitlementsPresenter.auditRow($0, l10n: l10n) }
    } catch EntitlementsError.notFound {
      notFound = true
    } catch {
      req.logger.error("entitlements read failed: \(error)")
      unavailable = true
    }
    return try await req.view.render(
      "users/entitlements",
      EntitlementsPageContext(
        userID: encoded(userID), rows: rows, audit: audit, auditUnavailable: auditUnavailable,
        unavailable: unavailable, notFound: notFound, errorMessage: errorMessage, user: user,
        meta: PageMeta(req)))
  }

  private func failed(_ req: Request, _ view: View, _ status: HTTPStatus) async throws -> Response {
    let response = try await view.encodeResponse(for: req)
    response.status = status
    return response
  }

  // MARK: Set or replace

  @Sendable
  func setOverride(req: Request) async throws -> Response {
    try await withSpan("set-user-entitlement-override") { _ in
      let (userID, keyParam, token) = try await context(req)
      guard let key = keyParam else { throw Abort(.badRequest) }
      let form = try req.content.decode(OverrideForm.self)
      let l10n = req.l10n
      let reason = (form.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !reason.isEmpty else {
        return try await failed(
          req,
          try await renderPage(
            req, userID: userID, token: token,
            errorMessage: l10n["entitlements_error_reason_required"]), .unprocessableEntity)
      }

      let records: [EntitlementRecord]
      do {
        records = try await req.entitlements.read(userID: userID, accessToken: token)
      } catch {
        return try await failed(
          req, try await renderPage(req, userID: userID, token: token, errorMessage: nil),
          .badGateway)
      }
      guard let record = records.first(where: { $0.key == key }) else { throw Abort(.notFound) }
      guard let value = EntitlementValue.parse(form.value ?? "", like: record.effective) else {
        return try await failed(
          req,
          try await renderPage(
            req, userID: userID, token: token,
            errorMessage: l10n["entitlements_error_value_invalid"]), .unprocessableEntity)
      }

      let paidReduction = value.isLower(than: record.paid)
      let lowering = value.isLower(than: record.effective)
      let validUntil = form.validUntil.flatMap { $0.isEmpty ? nil : $0 }
      let confirmed = form.confirmed == "yes"
      let reference = (form.reference ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

      func confirmPage(_ detail: PaidReductionDetail?, error: String?) async throws -> Response {
        let view = try await confirmView(
          req, userID: userID, record: record, value: value, reason: reason,
          validUntil: validUntil, reference: reference,
          isPaidReduction: paidReduction || detail != nil,
          isLowering: lowering, detail: detail, error: error)
        return try await failed(req, view, error == nil ? .ok : .unprocessableEntity)
      }

      if (paidReduction || lowering) && !confirmed { return try await confirmPage(nil, error: nil) }
      if paidReduction && (form.acknowledged != "yes" || reference.isEmpty) {
        return try await confirmPage(
          nil, error: l10n["entitlements_error_acknowledgment_required"])
      }

      let request = OverrideRequest(
        value: value, reason: reason, validUntil: validUntil,
        paidReductionReference: paidReduction ? reference : nil)
      do {
        try await req.entitlements.setOverride(
          userID: userID, key: key, request: request, accessToken: token)
      } catch EntitlementsError.acknowledgmentRequired(let detail) {
        return try await confirmPage(
          detail, error: l10n["entitlements_error_acknowledgment_required"])
      } catch EntitlementsError.paidReductionsDisabled {
        return try await failed(
          req,
          try await renderPage(
            req, userID: userID, token: token,
            errorMessage: l10n["entitlements_error_paid_reductions_disabled"]), .forbidden)
      } catch EntitlementsError.validation(let message) {
        return try await failed(
          req, try await renderPage(req, userID: userID, token: token, errorMessage: message),
          .unprocessableEntity)
      } catch {
        req.logger.error("set override failed: \(error)")
        return try await failed(
          req,
          try await renderPage(
            req, userID: userID, token: token,
            errorMessage: l10n["entitlements_error_unavailable"]), .badGateway)
      }
      let actor = (await req.currentUser)?.sub ?? "?"
      req.logger.info("override set: \(actor) \(userID)/\(key)")
      return req.redirectLocal(to: "/users/\(encoded(userID))/entitlements")
    }
  }

  private func confirmView(
    _ req: Request, userID: String, record: EntitlementRecord, value: EntitlementValue,
    reason: String, validUntil: String?, reference: String, isPaidReduction: Bool,
    isLowering: Bool, detail: PaidReductionDetail?, error: String?
  ) async throws -> View {
    let l10n = req.l10n
    let paid = detail?.paid ?? record.paid
    let payments = detail?.payments ?? record.payments
    return try await req.view.render(
      "users/entitlements-confirm",
      EntitlementConfirmContext(
        userID: encoded(userID), key: record.key, isPaidReduction: isPaidReduction,
        isLowering: isLowering, isRemove: false, value: value.formText, reason: reason,
        validUntil: validUntil ?? "",
        current: EntitlementsPresenter.display(record.effective, l10n: l10n),
        proposed: EntitlementsPresenter.display(detail?.proposed ?? value, l10n: l10n),
        paid: EntitlementsPresenter.display(paid, l10n: l10n),
        payments: payments.map { EntitlementsPresenter.line($0, l10n: l10n) },
        charges: EntitlementsPresenter.charges(payments, l10n: l10n),
        reference: reference, errorMessage: error,
        user: (await req.currentUser).map(LeafUser.init), meta: PageMeta(req)))
  }

  // MARK: Remove

  @Sendable
  func removeOverride(req: Request) async throws -> Response {
    try await withSpan("remove-user-entitlement-override") { _ in
      let (userID, keyParam, token) = try await context(req)
      guard let key = keyParam else { throw Abort(.badRequest) }
      // The first click on "Remove" posts a form with no fields, which has no body to decode.
      let form = (try? req.content.decode(OverrideForm.self)) ?? OverrideForm()
      let l10n = req.l10n
      let reason = (form.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

      if form.confirmed != "yes" || reason.isEmpty {
        let view = try await req.view.render(
          "users/entitlements-confirm",
          EntitlementConfirmContext(
            userID: encoded(userID), key: key, isPaidReduction: false, isLowering: false,
            isRemove: true, value: "", reason: reason, validUntil: "", current: "", proposed: "",
            paid: "", payments: [], charges: [], reference: "",
            errorMessage: form.confirmed == "yes"
              ? l10n["entitlements_error_reason_required"] : nil,
            user: (await req.currentUser).map(LeafUser.init), meta: PageMeta(req)))
        return try await failed(req, view, form.confirmed == "yes" ? .unprocessableEntity : .ok)
      }
      do {
        try await req.entitlements.removeOverride(
          userID: userID, key: key, reason: reason, accessToken: token)
      } catch {
        req.logger.error("remove override failed: \(error)")
        return try await failed(
          req,
          try await renderPage(
            req, userID: userID, token: token,
            errorMessage: l10n["entitlements_error_unavailable"]), .badGateway)
      }
      let actor = (await req.currentUser)?.sub ?? "?"
      req.logger.info("override removed: \(actor) \(userID)/\(key)")
      return req.redirectLocal(to: "/users/\(encoded(userID))/entitlements")
    }
  }
}
