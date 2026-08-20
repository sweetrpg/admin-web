import Tracing
import Vapor

/// Maintenance-mode list, per-scope create/edit form, and direct enable/disable toggle -
/// tasks.md 2.1-2.4. Unlike banners (append-only, edited by id), a maintenance-mode record is
/// keyed by scope: at most one per scope, and admin-api's `POST /maintenance-modes` upserts
/// by scope rather than always creating. The form is reached per-scope (not per-record-id)
/// for that reason - an admin picks "which app" from the known scope list, and the form
/// creates or updates whatever record already exists for it.
struct MaintenanceModeController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("maintenance-modes", use: list)
    routes.get("maintenance-modes", "edit", use: editForm)
    routes.post("maintenance-modes", use: upsert)
    routes.post("maintenance-modes", ":modeID", "toggle", use: toggle)
    routes.post("maintenance-modes", ":modeID", "delete", use: delete)
  }

  @Sendable
  func list(req: Request) async throws -> View {
    try await withSpan("list-maintenance-modes") { _ in
      let records = try await req.adminAPI.listAllMaintenanceModes()
      let byScope = Dictionary(
        records.map { (scopeKey(type: $0.scopeType, value: $0.scopeValue), $0) },
        uniquingKeysWith: { first, _ in first })

      var rows: [LeafMaintenanceScopeRow] = [
        LeafMaintenanceScopeRow(
          scopeType: .platform, scopeValue: "",
          displayName: KnownServiceScope.displayName(for: "platform", req: req),
          record: byScope[scopeKey(type: .platform, value: "")])
      ]
      rows += KnownServiceScope.all.map { service in
        LeafMaintenanceScopeRow(
          scopeType: .service, scopeValue: service,
          displayName: KnownServiceScope.displayName(for: service, req: req),
          record: byScope[scopeKey(type: .service, value: service)])
      }

      return try await req.view.render(
        "maintenance-modes/list",
        MaintenanceModeListContext(
          rows: rows,
          user: (await req.currentUser).map(LeafUser.init),
          meta: PageMeta(req)
        ))
    }
  }

  @Sendable
  func editForm(req: Request) async throws -> View {
    try await withSpan("edit-form-maintenance-mode") { _ in
      guard let scopeTypeRaw = req.query[String.self, at: "scope_type"],
        let scopeType = MaintenanceScopeType(rawValue: scopeTypeRaw)
      else {
        throw Abort(.badRequest, reason: "scope_type is required")
      }
      let scopeValue = req.query[String.self, at: "scope_value"] ?? ""
      if scopeType == .service {
        guard KnownServiceScope.all.contains(scopeValue) else {
          throw Abort(.badRequest, reason: "unknown service scope")
        }
      }

      let records = try await req.adminAPI.listAllMaintenanceModes()
      let existing = records.first {
        $0.scopeType == scopeType && $0.scopeValue == scopeValue
      }

      return try await req.view.render(
        "maintenance-modes/form",
        MaintenanceModeFormContext(
          formAction: "\(req.basePath)/maintenance-modes",
          displayName: scopeType == .platform
            ? KnownServiceScope.displayName(for: "platform", req: req)
            : KnownServiceScope.displayName(for: scopeValue, req: req),
          scopeType: scopeType.rawValue,
          scopeValue: scopeValue,
          isEdit: existing != nil,
          mode: existing.map(LeafMaintenanceModeForm.init) ?? .empty,
          user: (await req.currentUser).map(LeafUser.init),
          meta: PageMeta(req)
        ))
    }
  }

  @Sendable
  func upsert(req: Request) async throws -> Response {
    try await withSpan("upsert-maintenance-mode") { _ in
      let input = try Self.decodeInput(req)
      let accessToken = try await requireAccessToken(req)
      _ = try await req.adminAPI.upsertMaintenanceMode(input, accessToken: accessToken)
      req.logger.info(
        "upsert: maintenance mode set for \(input.scopeType.rawValue) \(input.scopeValue), enabled=\(input.enabled)"
      )
      return req.redirectLocal(to: "/maintenance-modes")
    }
  }

  @Sendable
  func toggle(req: Request) async throws -> Response {
    try await withSpan("toggle-maintenance-mode") { _ in
      guard let modeID = req.parameters.get("modeID") else { throw Abort(.badRequest) }
      let records = try await req.adminAPI.listAllMaintenanceModes()
      guard let mode = records.first(where: { $0.id == modeID }) else {
        req.logger.warning("toggle: maintenance mode \(modeID) not found")
        throw Abort(.notFound)
      }
      let accessToken = try await requireAccessToken(req)
      let newEnabled = !mode.enabled
      _ = try await req.adminAPI.setMaintenanceModeEnabled(
        mode, enabled: newEnabled, accessToken: accessToken)
      req.logger.info("toggle: maintenance mode \(modeID) set to enabled=\(newEnabled)")
      return req.redirectLocal(to: "/maintenance-modes")
    }
  }

  @Sendable
  func delete(req: Request) async throws -> Response {
    try await withSpan("delete-maintenance-mode") { _ in
      guard let modeID = req.parameters.get("modeID") else { throw Abort(.badRequest) }
      let accessToken = try await requireAccessToken(req)
      try await req.adminAPI.deleteMaintenanceMode(id: modeID, accessToken: accessToken)
      req.logger.info("delete: maintenance mode \(modeID) deleted")
      return req.redirectLocal(to: "/maintenance-modes")
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

  private static func decodeInput(_ req: Request) throws -> MaintenanceModeInput {
    struct RawForm: Content {
      let scopeType: String
      let scopeValue: String
      let enabled: String?
      let startsAt: String?
      let endsAt: String?
      let label: String
      let description: String

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
    let raw = try req.content.decode(RawForm.self)
    guard let scopeType = MaintenanceScopeType(rawValue: raw.scopeType) else {
      throw Abort(.badRequest, reason: "Invalid scope_type")
    }
    guard let startsAtRaw = raw.startsAt, !startsAtRaw.isEmpty,
      let startsAt = Self.parseDateTimeLocal(startsAtRaw)
    else {
      throw Abort(.badRequest, reason: "starts_at is required")
    }
    guard !raw.label.isEmpty else {
      throw Abort(.badRequest, reason: "label is required")
    }
    guard !raw.description.isEmpty else {
      throw Abort(.badRequest, reason: "description is required")
    }
    let endsAt = raw.endsAt.flatMap { $0.isEmpty ? nil : Self.parseDateTimeLocal($0) }
    return MaintenanceModeInput(
      scopeType: scopeType,
      scopeValue: raw.scopeValue,
      enabled: raw.enabled == "true",
      startsAt: startsAt,
      endsAt: endsAt,
      label: raw.label,
      description: raw.description
    )
  }

  /// Same `datetime-local` parsing convention as `BannerController` - UTC, no per-user
  /// timezone preference.
  private static func parseDateTimeLocal(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: value)
  }
}

private func scopeKey(type: MaintenanceScopeType, value: String) -> String {
  "\(type.rawValue):\(value)"
}
