import Tracing
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
    try await withSpan("list-users") { _ in
      do {
        return try await renderList(req: req)
      } catch let error as BackendHTTPError {
        // The backend answered with an error: say so, with its message, instead of claiming it
        // could not be reached (which hid a 400 from auth-api for a day).
        req.logger.error(
          "list: \(error.backend) refused the request: status \(error.status.code), message \(error.message ?? "none") (GET /users)"
        )
        return try await req.view.render(
          "users/list",
          UsersListContext(
            users: [], isEmpty: false, allRoles: Self.allRoles, unavailable: false,
            refused: true, refusedMessage: error.displayMessage,
            user: (await req.currentUser).map(LeafUser.init), meta: PageMeta(req)))
      } catch {
        // Backend composition failure (users-api identity listing or auth-api roles) should not
        // surface as a raw 500 error page - render the page shell with a clear unavailable state.
        req.logger.error("list: backend composition failed: \(error)")
        return try await req.view.render(
          "users/list",
          UsersListContext(
            users: [], isEmpty: false, allRoles: Self.allRoles, unavailable: true,
            user: (await req.currentUser).map(LeafUser.init),
            meta: PageMeta(req)
          ))
      }
    }
  }

  private func renderList(req: Request) async throws -> View {
    let accessToken = try await requireAccessToken(req)
    let identities = try await req.usersAPI.listUsers(accessToken: accessToken)
    // One row per person: users-api lists every linked login in `subjects`. Role and deny-entry
    // management act on the person through any one of those logins, so the first stands for the
    // person in every auth-api call. A person with no login at all has nothing to compose
    // against and is left out rather than shown with broken controls.
    var order: [String] = []
    var people: [String: (identity: UserIdentity, subjects: [String])] = [:]
    for identity in identities where !identity.allSubjects.isEmpty {
      if var existing = people[identity.id] {
        existing.subjects += identity.allSubjects.filter { !existing.subjects.contains($0) }
        people[identity.id] = existing
      } else {
        order.append(identity.id)
        people[identity.id] = (identity, identity.allSubjects)
      }
    }
    let skipped = identities.count - order.count
    if skipped > 0 {
      req.logger.warning(
        "list: \(skipped) of \(identities.count) users-api identities have no Auth0 subject, omitted from the list"
      )
    }
    let primaries = order.compactMap { people[$0]?.subjects.first }
    let rolesBySubject = Dictionary(
      try await req.authAPI.listRoles(subjects: primaries, accessToken: accessToken)
        .map { ($0.subject, $0) }, uniquingKeysWith: { first, _ in first })

    let summaries = order.compactMap { id -> LeafUserSummary? in
      guard let person = people[id], let primary = person.subjects.first else { return nil }
      let roles = rolesBySubject[primary]
      return LeafUserSummary(
        subject: primary, userID: id, email: person.identity.email, identities: person.subjects,
        roles: roles?.roles ?? ["user"], deniedServices: roles?.deniedServices ?? [])
    }

    // A failure here degrades only the deny form: the rest of the page still renders.
    var services: [ServiceOption] = []
    var servicesUnavailable = false
    do {
      services = try await req.authAPI.listServices(accessToken: accessToken)
    } catch {
      req.logger.error("list: auth-api services list failed: \(error)")
      servicesUnavailable = true
    }

    return try await req.view.render(
      "users/list",
      UsersListContext(
        users: summaries,
        isEmpty: summaries.isEmpty,
        allRoles: Self.allRoles,
        unavailable: false,
        services: services,
        servicesUnavailable: servicesUnavailable,
        user: (await req.currentUser).map(LeafUser.init),
        meta: PageMeta(req)
      ))
  }

  @Sendable
  func addRole(req: Request) async throws -> Response {
    try await withSpan("add-role") { _ in
      guard let subject = req.parameters.get("subject") else { throw Abort(.badRequest) }
      struct RoleForm: Content { let role: String }
      let form = try req.content.decode(RoleForm.self)
      let actingUserSub = try await requireActingUserSub(req)
      let accessToken = try await requireAccessToken(req)
      try await req.authAPI.addRole(subject: subject, role: form.role, accessToken: accessToken)
      req.logger.info(
        "addRole: \(actingUserSub) added role \(form.role) to \(subject)")
      return req.redirectLocal(to: "/users")
    }
  }

  @Sendable
  func removeRole(req: Request) async throws -> Response {
    try await withSpan("remove-role") { _ in
      guard let subject = req.parameters.get("subject"), let role = req.parameters.get("role")
      else {
        throw Abort(.badRequest)
      }
      let actingUserSub = try await requireActingUserSub(req)
      let accessToken = try await requireAccessToken(req)
      try await req.authAPI.removeRole(subject: subject, role: role, accessToken: accessToken)
      req.logger.info(
        "removeRole: \(actingUserSub) removed role \(role) from \(subject)")
      return req.redirectLocal(to: "/users")
    }
  }

  @Sendable
  func addDenyEntry(req: Request) async throws -> Response {
    try await withSpan("add-deny-entry") { _ in
      guard let subject = req.parameters.get("subject") else { throw Abort(.badRequest) }
      struct DenyEntryForm: Content { let service: String }
      let form = try req.content.decode(DenyEntryForm.self)
      let actingUserSub = try await requireActingUserSub(req)
      let accessToken = try await requireAccessToken(req)
      try await req.authAPI.addDenyEntry(
        subject: subject, service: form.service, accessToken: accessToken)
      req.logger.info(
        "addDenyEntry: \(actingUserSub) denied \(subject) access to \(form.service)")
      return req.redirectLocal(to: "/users")
    }
  }

  @Sendable
  func removeDenyEntry(req: Request) async throws -> Response {
    try await withSpan("remove-deny-entry") { _ in
      guard let subject = req.parameters.get("subject"), let service = req.parameters.get("service")
      else {
        throw Abort(.badRequest)
      }
      let actingUserSub = try await requireActingUserSub(req)
      let accessToken = try await requireAccessToken(req)
      try await req.authAPI.removeDenyEntry(
        subject: subject, service: service, accessToken: accessToken)
      req.logger.info(
        "removeDenyEntry: \(actingUserSub) restored \(subject) access to \(service)")
      return req.redirectLocal(to: "/users")
    }
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

  /// `users-api`'s identity listing forwards the acting admin's own Auth0 access token as the
  /// bearer credential - `users-api` verifies it and checks the user's role itself. Same
  /// fail-loudly rationale as `requireActingUserSub` above.
  private func requireAccessToken(_ req: Request) async throws -> String {
    guard let token = (await req.currentUser)?.accessToken else {
      throw Abort(.internalServerError, reason: "No acting user session found")
    }
    return token
  }
}
