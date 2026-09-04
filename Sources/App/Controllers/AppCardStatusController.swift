import Tracing
import Vapor

/// App card status list, per-scope create/edit form, and direct enable/disable toggle.
/// Unlike maintenance modes (datetime-based with complex lifecycle), app-card-status is a
/// simple per-scope flag + label pair, so the form is simpler. Like maintenance modes, a
/// record is keyed by scope: at most one per scope, and admin-api's `POST /app-card-statuses`
/// upserts by scope rather than always creating.
struct AppCardStatusController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("app-card-statuses", use: list)
    routes.get("app-card-statuses", "edit", use: editForm)
    routes.post("app-card-statuses", use: upsert)
    routes.post("app-card-statuses", ":statusID", "toggle", use: toggle)
    routes.post("app-card-statuses", ":statusID", "delete", use: delete)
  }

  @Sendable
  func list(req: Request) async throws -> View {
    try await withSpan("list-app-card-statuses") { _ in
      let records = try await req.adminAPI.listAllAppCardStatuses()
      let byScope = Dictionary(
        records.map { (scopeKey(type: $0.scopeType, value: $0.scopeValue), $0) },
        uniquingKeysWith: { first, _ in first })

      var rows: [LeafAppCardStatusRow] = []
      rows += AppCardScopeType.all.map { service in
        LeafAppCardStatusRow(
          scopeType: "service", scopeValue: service,
          displayName: AppCardScopeType.displayName(for: service, req: req),
          record: byScope[scopeKey(type: "service", value: service)])
      }

      rows.sort { $0.displayName < $1.displayName }

      return try await req.view.render(
        "app-card-statuses/list",
        AppCardStatusListContext(
          rows: rows,
          user: (await req.currentUser).map(LeafUser.init),
          meta: PageMeta(req)
        ))
    }
  }

  @Sendable
  func editForm(req: Request) async throws -> View {
    try await withSpan("edit-form-app-card-status") { _ in
      let scopeType = "service"
      guard let scopeValue = req.query[String.self, at: "scope_value"] else {
        throw Abort(.badRequest, reason: "scope_value is required")
      }
      guard AppCardScopeType.all.contains(scopeValue) else {
        throw Abort(.badRequest, reason: "unknown service scope")
      }

      let records = try await req.adminAPI.listAllAppCardStatuses()
      let existing = records.first {
        $0.scopeType == scopeType && $0.scopeValue == scopeValue
      }

      return try await req.view.render(
        "app-card-statuses/form",
        AppCardStatusFormContext(
          formAction: "\(req.basePath)/app-card-statuses",
          displayName: AppCardScopeType.displayName(for: scopeValue, req: req),
          scopeType: scopeType,
          scopeValue: scopeValue,
          isEdit: existing != nil,
          status: existing.map(LeafAppCardStatusForm.init) ?? .empty,
          user: (await req.currentUser).map(LeafUser.init),
          meta: PageMeta(req)
        ))
    }
  }

  @Sendable
  func upsert(req: Request) async throws -> Response {
    try await withSpan("upsert-app-card-status") { _ in
      let input = try Self.decodeInput(req)
      let accessToken = try await requireAccessToken(req)
      _ = try await req.adminAPI.upsertAppCardStatus(input, accessToken: accessToken)
      req.logger.info(
        "upsert: app card status set for \(input.scopeValue), enabled=\(input.enabled)"
      )
      return req.redirectLocal(to: "/app-card-statuses")
    }
  }

  @Sendable
  func toggle(req: Request) async throws -> Response {
    try await withSpan("toggle-app-card-status") { _ in
      guard let statusID = req.parameters.get("statusID") else { throw Abort(.badRequest) }
      let records = try await req.adminAPI.listAllAppCardStatuses()
      guard let status = records.first(where: { $0.id == statusID }) else {
        req.logger.warning("toggle: app card status \(statusID) not found")
        throw Abort(.notFound)
      }
      let accessToken = try await requireAccessToken(req)
      let newEnabled = !status.enabled
      _ = try await req.adminAPI.setAppCardStatusEnabled(
        status, enabled: newEnabled, accessToken: accessToken)
      req.logger.info("toggle: app card status \(statusID) set to enabled=\(newEnabled)")
      return req.redirectLocal(to: "/app-card-statuses")
    }
  }

  @Sendable
  func delete(req: Request) async throws -> Response {
    try await withSpan("delete-app-card-status") { _ in
      guard let statusID = req.parameters.get("statusID") else { throw Abort(.badRequest) }
      let accessToken = try await requireAccessToken(req)
      try await req.adminAPI.deleteAppCardStatus(id: statusID, accessToken: accessToken)
      req.logger.info("delete: app card status \(statusID) deleted")
      return req.redirectLocal(to: "/app-card-statuses")
    }
  }

  /// Same rationale as `BannerController.requireAccessToken`: `AuthRequiredMiddleware`
  /// already guarantees a session here, so a nil token means something is badly wrong rather
  /// than a normal auth failure to handle gracefully.
  private func requireAccessToken(_ req: Request) async throws -> String {
    guard let token = (await req.currentUser)?.accessToken else {
      throw Abort(.internalServerError, reason: "No acting user session found")
    }
    return token
  }

  private static func decodeInput(_ req: Request) throws -> AppCardStatusInput {
    struct RawForm: Content {
      let scopeType: String
      let scopeValue: String
      let enabled: String?
      let label: String

      enum CodingKeys: String, CodingKey {
        case scopeType = "scope_type"
        case scopeValue = "scope_value"
        case enabled
        case label
      }
    }
    let raw = try req.content.decode(RawForm.self)
    guard !raw.label.isEmpty else {
      throw Abort(.badRequest, reason: "label is required")
    }
    return AppCardStatusInput(
      scopeType: raw.scopeType,
      scopeValue: raw.scopeValue,
      enabled: raw.enabled == "true",
      label: raw.label
    )
  }
}

private func scopeKey(type: String, value: String) -> String {
  "\(type):\(value)"
}
