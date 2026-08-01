import Vapor

/// Role and per-service deny-entry management - the counterpart to `BannerController` for the
/// admin UI this app now also hosts (see design.md's "Admin UI lives in admin-web" decision in
/// platform's add-user-api-authn-authz change). Every route here is already gated by
/// `AuthRequiredMiddleware`'s blanket `admin`-role check, same as the banner routes.
struct UsersController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("users", use: list)
    routes.post("users", ":userID", "roles", use: addRole)
    routes.post("users", ":userID", "roles", ":role", "remove", use: removeRole)
    routes.post("users", ":userID", "deny-entries", use: addDenyEntry)
    routes.post(
      "users", ":userID", "deny-entries", ":service", "remove", use: removeDenyEntry)
  }

  /// The fixed role set from `users-api`'s `Role` enum - kept in sync by hand, same as
  /// `BannerScopeType`/`BannerSeverity`'s Swift mirrors of admin-api's Go enums.
  static let allRoles = ["user", "submitter", "editor", "moderator", "approver", "admin"]

  @Sendable
  func list(req: Request) async throws -> View {
    let users = try await req.usersAPI.listUsers()
    return try await req.view.render(
      "users/list",
      UsersListContext(
        users: users.map(LeafUserSummary.init),
        isEmpty: users.isEmpty,
        allRoles: Self.allRoles,
        user: (await req.currentUser).map(LeafUser.init),
        meta: PageMeta(req)
      ))
  }

  @Sendable
  func addRole(req: Request) async throws -> Response {
    guard let userID = req.parameters.get("userID") else { throw Abort(.badRequest) }
    struct RoleForm: Content { let role: String }
    let form = try req.content.decode(RoleForm.self)
    let actingUserSub = try await requireActingUserSub(req)
    try await req.usersAPI.addRole(userID: userID, role: form.role, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/users")
  }

  @Sendable
  func removeRole(req: Request) async throws -> Response {
    guard let userID = req.parameters.get("userID"), let role = req.parameters.get("role") else {
      throw Abort(.badRequest)
    }
    let actingUserSub = try await requireActingUserSub(req)
    try await req.usersAPI.removeRole(userID: userID, role: role, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/users")
  }

  @Sendable
  func addDenyEntry(req: Request) async throws -> Response {
    guard let userID = req.parameters.get("userID") else { throw Abort(.badRequest) }
    struct DenyEntryForm: Content { let service: String }
    let form = try req.content.decode(DenyEntryForm.self)
    let actingUserSub = try await requireActingUserSub(req)
    try await req.usersAPI.addDenyEntry(
      userID: userID, service: form.service, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/users")
  }

  @Sendable
  func removeDenyEntry(req: Request) async throws -> Response {
    guard let userID = req.parameters.get("userID"), let service = req.parameters.get("service")
    else {
      throw Abort(.badRequest)
    }
    let actingUserSub = try await requireActingUserSub(req)
    try await req.usersAPI.removeDenyEntry(
      userID: userID, service: service, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/users")
  }

  /// Every mutating route needs the acting admin's `sub` to pass to `users-api` for its audit
  /// log. This should never actually be nil here - `AuthRequiredMiddleware` already required a
  /// valid `admin` session to reach this handler at all - but fail loudly rather than silently
  /// send an empty/garbage value `users-api` would otherwise have to guard against itself.
  private func requireActingUserSub(_ req: Request) async throws -> String {
    guard let sub = (await req.currentUser)?.sub else {
      throw Abort(.internalServerError, reason: "No acting user session found")
    }
    return sub
  }
}

// MARK: - Leaf page contexts

struct UsersListContext: Content {
  let users: [LeafUserSummary]
  let isEmpty: Bool
  let allRoles: [String]
  let user: LeafUser?
  let meta: PageMeta
}

struct LeafUserSummary: Content {
  let id: String
  let email: String
  let roles: [String]
  let deniedServices: [String]
  /// Roles not already assigned - what the "add role" dropdown should offer, so the form can't
  /// submit a role the user already has.
  let availableRoles: [String]

  init(_ summary: UserSummary) {
    self.id = summary.id
    self.email = summary.email
    self.roles = summary.roles
    self.deniedServices = summary.deniedServices
    self.availableRoles = UsersController.allRoles.filter { !summary.roles.contains($0) }
  }
}
