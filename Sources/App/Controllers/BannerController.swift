import Vapor

/// Banner list, create/edit form, immediate expire, and delete - the whole management UI per
/// tasks.md 6.1-6.4.
struct BannerController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get(use: list)
    routes.get("banners", "new", use: newForm)
    routes.post("banners", use: create)
    routes.get("banners", ":bannerID", "edit", use: editForm)
    routes.post("banners", ":bannerID", use: update)
    routes.post("banners", ":bannerID", "expire", use: expire)
    routes.post("banners", ":bannerID", "delete", use: delete)
  }

  @Sendable
  func list(req: Request) async throws -> View {
    let banners = try await req.adminAPI.listAll()
    let sorted = banners.sorted { $0.expiresAt > $1.expiresAt }
    return try await req.view.render(
      "banners/list",
      ListContext(
        banners: sorted.map(LeafBanner.init),
        isEmpty: sorted.isEmpty,
        user: (await req.currentUser).map(LeafUser.init),
        meta: PageMeta(req)
      ))
  }

  @Sendable
  func newForm(req: Request) async throws -> View {
    try await req.view.render(
      "banners/form",
      FormContext(
        formAction: "\(req.basePath)/banners",
        isEdit: false,
        banner: nil,
        scopeTypes: BannerScopeType.allCases.map(\.rawValue),
        severities: BannerSeverity.allCases.map(\.rawValue),
        user: (await req.currentUser).map(LeafUser.init),
        meta: PageMeta(req)
      ))
  }

  @Sendable
  func editForm(req: Request) async throws -> View {
    guard let bannerID = req.parameters.get("bannerID") else { throw Abort(.badRequest) }
    let banners = try await req.adminAPI.listAll()
    guard let banner = banners.first(where: { $0.id == bannerID }) else {
      throw Abort(.notFound)
    }
    return try await req.view.render(
      "banners/form",
      FormContext(
        formAction: "\(req.basePath)/banners/\(bannerID)",
        isEdit: true,
        banner: LeafBannerForm(banner),
        scopeTypes: BannerScopeType.allCases.map(\.rawValue),
        severities: BannerSeverity.allCases.map(\.rawValue),
        user: (await req.currentUser).map(LeafUser.init),
        meta: PageMeta(req)
      ))
  }

  @Sendable
  func create(req: Request) async throws -> Response {
    let input = try Self.decodeInput(req)
    _ = try await req.adminAPI.create(input)
    return req.redirectLocal(to: "/")
  }

  @Sendable
  func update(req: Request) async throws -> Response {
    guard let bannerID = req.parameters.get("bannerID") else { throw Abort(.badRequest) }
    let input = try Self.decodeInput(req)
    _ = try await req.adminAPI.update(id: bannerID, input)
    return req.redirectLocal(to: "/")
  }

  @Sendable
  func expire(req: Request) async throws -> Response {
    guard let bannerID = req.parameters.get("bannerID") else { throw Abort(.badRequest) }
    let banners = try await req.adminAPI.listAll()
    guard let banner = banners.first(where: { $0.id == bannerID }) else {
      throw Abort(.notFound)
    }
    _ = try await req.adminAPI.expireNow(banner)
    return req.redirectLocal(to: "/")
  }

  @Sendable
  func delete(req: Request) async throws -> Response {
    guard let bannerID = req.parameters.get("bannerID") else { throw Abort(.badRequest) }
    try await req.adminAPI.delete(id: bannerID)
    return req.redirectLocal(to: "/")
  }

  /// Server-side mirror of the form's client-side validation - `expires_at` is required per the
  /// admin spec's "Form rejects missing expiration" scenario. The client-side check (banner
  /// form's `required` attribute + JS guard, see banners/form.leaf) is the primary UX, but a
  /// request that reaches this handler without one is rejected here too rather than trusted.
  private static func decodeInput(_ req: Request) throws -> BannerInput {
    struct RawForm: Content {
      let scopeType: String
      let scopeValue: String
      let severity: String
      let message: String
      let startsAt: String?
      let expiresAt: String?

      enum CodingKeys: String, CodingKey {
        case scopeType = "scope_type"
        case scopeValue = "scope_value"
        case severity
        case message
        case startsAt = "starts_at"
        case expiresAt = "expires_at"
      }
    }
    let raw = try req.content.decode(RawForm.self)
    guard let scopeType = BannerScopeType(rawValue: raw.scopeType) else {
      throw Abort(.badRequest, reason: "Invalid scope_type")
    }
    guard let severity = BannerSeverity(rawValue: raw.severity) else {
      throw Abort(.badRequest, reason: "Invalid severity")
    }
    guard let expiresAtRaw = raw.expiresAt, !expiresAtRaw.isEmpty,
      let expiresAt = Self.parseDateTimeLocal(expiresAtRaw)
    else {
      throw Abort(.badRequest, reason: "expires_at is required")
    }
    let startsAt = raw.startsAt.flatMap { $0.isEmpty ? nil : Self.parseDateTimeLocal($0) }
    return BannerInput(
      scopeType: scopeType,
      scopeValue: raw.scopeValue,
      severity: severity,
      message: raw.message,
      startsAt: startsAt,
      expiresAt: expiresAt
    )
  }

  /// Parses an HTML `<input type="datetime-local">` value (`yyyy-MM-ddTHH:mm`, no timezone -
  /// treated as UTC here, since this app has no per-user timezone preference yet).
  private static func parseDateTimeLocal(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: value)
  }
}

// MARK: - Leaf page contexts

struct ListContext: Content {
  let banners: [LeafBanner]
  let isEmpty: Bool
  let user: LeafUser?
  let meta: PageMeta
}

struct FormContext: Content {
  let formAction: String
  let isEdit: Bool
  let banner: LeafBannerForm?
  let scopeTypes: [String]
  let severities: [String]
  let user: LeafUser?
  let meta: PageMeta
}

// MARK: - Leaf view models

struct LeafUser: Content {
  let name: String

  init(_ user: SessionUser) {
    self.name = user.name
  }
}

struct LeafBanner: Content {
  let id: String
  let scopeLabel: String
  let severity: String
  let message: String
  let status: String
  let expiresAtLabel: String

  init(_ banner: Banner) {
    self.id = banner.id
    self.scopeLabel =
      banner.scopeType == .platform
      ? "platform" : "\(banner.scopeType.rawValue):\(banner.scopeValue)"
    self.severity = banner.severity.rawValue
    self.message = banner.message
    self.status = banner.status().rawValue
    self.expiresAtLabel = ISO8601DateFormatter().string(from: banner.expiresAt)
  }
}

struct LeafBannerForm: Content {
  let id: String
  let scopeType: String
  let scopeValue: String
  let severity: String
  let message: String
  let startsAt: String
  let expiresAt: String

  init(_ banner: Banner) {
    self.id = banner.id
    self.scopeType = banner.scopeType.rawValue
    self.scopeValue = banner.scopeValue
    self.severity = banner.severity.rawValue
    self.message = banner.message
    self.startsAt = banner.startsAt.map(Self.formatDateTimeLocal) ?? ""
    self.expiresAt = Self.formatDateTimeLocal(banner.expiresAt)
  }

  private static func formatDateTimeLocal(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
  }
}
