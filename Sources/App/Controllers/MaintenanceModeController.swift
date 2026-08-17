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
    let records = try await req.adminAPI.listAllMaintenanceModes()
    let byScope = Dictionary(
      records.map { (scopeKey(type: $0.scopeType, value: $0.scopeValue), $0) },
      uniquingKeysWith: { first, _ in first })

    var rows: [LeafMaintenanceScopeRow] = [
      LeafMaintenanceScopeRow(
        scopeType: .platform, scopeValue: "", displayName: "Platform (all apps)",
        record: byScope[scopeKey(type: .platform, value: "")])
    ]
    rows += KnownServiceScope.all.map { service in
      LeafMaintenanceScopeRow(
        scopeType: .service, scopeValue: service, displayName: service,
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

  @Sendable
  func editForm(req: Request) async throws -> View {
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
        displayName: scopeType == .platform ? "Platform (all apps)" : scopeValue,
        scopeType: scopeType.rawValue,
        scopeValue: scopeValue,
        isEdit: existing != nil,
        mode: existing.map(LeafMaintenanceModeForm.init) ?? .empty,
        user: (await req.currentUser).map(LeafUser.init),
        meta: PageMeta(req)
      ))
  }

  @Sendable
  func upsert(req: Request) async throws -> Response {
    let input = try Self.decodeInput(req)
    let actingUserSub = try await requireActingUserSub(req)
    _ = try await req.adminAPI.upsertMaintenanceMode(input, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/maintenance-modes")
  }

  @Sendable
  func toggle(req: Request) async throws -> Response {
    guard let modeID = req.parameters.get("modeID") else { throw Abort(.badRequest) }
    let records = try await req.adminAPI.listAllMaintenanceModes()
    guard let mode = records.first(where: { $0.id == modeID }) else {
      throw Abort(.notFound)
    }
    let actingUserSub = try await requireActingUserSub(req)
    _ = try await req.adminAPI.setMaintenanceModeEnabled(
      mode, enabled: !mode.enabled, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/maintenance-modes")
  }

  @Sendable
  func delete(req: Request) async throws -> Response {
    guard let modeID = req.parameters.get("modeID") else { throw Abort(.badRequest) }
    let actingUserSub = try await requireActingUserSub(req)
    try await req.adminAPI.deleteMaintenanceMode(id: modeID, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/maintenance-modes")
  }

  /// Same rationale as `BannerController.requireActingUserSub`: `AuthRequiredMiddleware`
  /// already guarantees a session here, so a nil sub means something is badly wrong rather
  /// than a normal auth failure to handle gracefully.
  private func requireActingUserSub(_ req: Request) async throws -> String {
    guard let sub = (await req.currentUser)?.sub else {
      throw Abort(.internalServerError, reason: "No acting user session found")
    }
    return sub
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
