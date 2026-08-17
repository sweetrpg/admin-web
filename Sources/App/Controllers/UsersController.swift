import Vapor

/// Role and per-service deny-entry management - the counterpart to `BannerController` for the
/// admin UI this app also hosts. Every route here is already gated by
/// `AuthRequiredMiddleware`'s blanket `admin`-role check, same as the banner routes.
///
/// Composes `users-api` (identity: id/email) with `auth-api` (authorization: roles/deny
/// entries), joined by Auth0 subject, since the split-authz-into-auth-api change moved
/// authorization data off `users-api` into a service with no profile data of its own to serve a
/// combined view itself - see `sweetrpg/platform`'s `openspec/changes/split-authz-into-auth-api`
/// design.md.
struct UsersController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get("users", use: list)
    routes.post("users", ":subject", "roles", use: addRole)
    routes.post("users", ":subject", "roles", ":role", "remove", use: removeRole)
    routes.post("users", ":subject", "deny-entries", use: addDenyEntry)
    routes.post(
      "users", ":subject", "deny-entries", ":service", "remove", use: removeDenyEntry)
  }

  /// The fixed role set from `auth-api`'s `Role` enum - kept in sync by hand, same as
  /// `BannerScopeType`/`BannerSeverity`'s Swift mirrors of admin-api's Go enums.
  static let allRoles = ["user", "submitter", "editor", "moderator", "approver", "admin"]

  @Sendable
  func list(req: Request) async throws -> View {
    let identities = try await req.usersAPI.listUsers()
    // Role/deny-entry management needs a subject to act on - a user with no Auth0 LoginProfile
    // yet (shouldn't normally happen; Auth0 is the platform's sole login mechanism) has nothing
    // to compose against and is left out rather than shown with broken controls.
    let withSubject = identities.compactMap { identity -> (UserIdentity, String)? in
      guard let subject = identity.subject else { return nil }
      return (identity, subject)
    }
    let rolesBySubject = Dictionary(
      uniqueKeysWithValues: try await req.authAPI.listRoles(subjects: withSubject.map(\.1))
        .map { ($0.subject, $0) })

    let summaries = withSubject.map { identity, subject -> LeafUserSummary in
      let roles = rolesBySubject[subject]
      return LeafUserSummary(
        subject: subject, email: identity.email, roles: roles?.roles ?? ["user"],
        deniedServices: roles?.deniedServices ?? [])
    }

    return try await req.view.render(
      "users/list",
      UsersListContext(
        users: summaries,
        isEmpty: summaries.isEmpty,
        allRoles: Self.allRoles,
        user: (await req.currentUser).map(LeafUser.init),
        meta: PageMeta(req)
      ))
  }

  @Sendable
  func addRole(req: Request) async throws -> Response {
    guard let subject = req.parameters.get("subject") else { throw Abort(.badRequest) }
    struct RoleForm: Content { let role: String }
    let form = try req.content.decode(RoleForm.self)
    let actingUserSub = try await requireActingUserSub(req)
    try await req.authAPI.addRole(subject: subject, role: form.role, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/users")
  }

  @Sendable
  func removeRole(req: Request) async throws -> Response {
    guard let subject = req.parameters.get("subject"), let role = req.parameters.get("role")
    else {
      throw Abort(.badRequest)
    }
    let actingUserSub = try await requireActingUserSub(req)
    try await req.authAPI.removeRole(subject: subject, role: role, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/users")
  }

  @Sendable
  func addDenyEntry(req: Request) async throws -> Response {
    guard let subject = req.parameters.get("subject") else { throw Abort(.badRequest) }
    struct DenyEntryForm: Content { let service: String }
    let form = try req.content.decode(DenyEntryForm.self)
    let actingUserSub = try await requireActingUserSub(req)
    try await req.authAPI.addDenyEntry(
      subject: subject, service: form.service, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/users")
  }

  @Sendable
  func removeDenyEntry(req: Request) async throws -> Response {
    guard let subject = req.parameters.get("subject"), let service = req.parameters.get("service")
    else {
      throw Abort(.badRequest)
    }
    let actingUserSub = try await requireActingUserSub(req)
    try await req.authAPI.removeDenyEntry(
      subject: subject, service: service, actingUserSub: actingUserSub)
    return req.redirectLocal(to: "/users")
  }

  /// Every mutating route needs the acting admin's `sub` to pass to `auth-api` for its audit
  /// log. This should never actually be nil here - `AuthRequiredMiddleware` already required a
  /// valid `admin` session to reach this handler at all - but fail loudly rather than silently
  /// send an empty/garbage value `auth-api` would otherwise have to guard against itself.
  private func requireActingUserSub(_ req: Request) async throws -> String {
    guard let sub = (await req.currentUser)?.sub else {
      throw Abort(.internalServerError, reason: "No acting user session found")
    }
    return sub
  }
}
