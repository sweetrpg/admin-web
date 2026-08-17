import Tracing
import Vapor

/// Matches `InternalServiceAuth.headerName` in `auth-api` exactly - the two repos are separate
/// Swift packages, so this can't be a shared import, only a matched string constant.
private let internalServiceTokenHeaderName = "X-Internal-Service-Token"

/// Matches `RolesController`'s expectation exactly - the acting admin's Auth0 `sub`, required on
/// every mutating call so `auth-api` can write its before/after audit log entry. `auth-api`
/// fails the request closed if this is missing or empty; see that repo's
/// `AdminActionAuditLog.swift` and `RolesController.performAudited`.
private let actingUserSubHeaderName = "X-Acting-User-Sub"

/// A subject's roles and per-service deny entries, as returned by `auth-api`'s `RolesController`
/// (`GET /api/admin/roles`). Mirrors that controller's `SubjectRolesSummary` exactly.
struct SubjectRolesSummary: Content {
  let subject: String
  let roles: [String]
  let deniedServices: [String]
}

/// Thin client for `auth-api`'s subject-keyed `/api/admin/roles`/`/api/admin/deny-entries`
/// role/service-access management surface - the counterpart to `UsersAPIClient.swift`'s identity
/// listing. `admin-web`'s role-management UI composes both: `users-api` for who a user is
/// (id/email), `auth-api` for what they're allowed to do (roles/deny entries), joined by Auth0
/// subject. See `sweetrpg/platform`'s `split-authz-into-auth-api` change design.md.
///
/// Every call presents `X-Internal-Service-Token` instead of an Auth0 bearer token; see
/// `AuthAPIConfig.swift`. Every *mutating* call also presents `X-Acting-User-Sub` (the current
/// session's `sub`) so `auth-api` can record who initiated the action in its audit log -
/// `auth-api` refuses to perform the action at all if it can't log who asked for it.
struct AuthAPIClient {
  let client: Client
  let baseURL: String
  let internalServiceToken: String?

  /// This request's inbound trace context, if it arrived with one - forwarded on every
  /// outbound call, never fabricated. Nothing upstream of this app sets `traceparent` yet, so
  /// this is a no-op today; it activates automatically once frontend-side tracing is
  /// separately scoped (see sweetrpg/platform's migrate-auth-users-api-to-go change
  /// design.md).
  let traceparent: String?

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.authAPIConfig.baseURL
    self.internalServiceToken = request.authAPIConfig.internalServiceToken
    self.traceparent = request.headers.first(name: "traceparent")
  }

  /// Bulk lookup for a set of subjects, in one round trip - what `admin-web`'s user list uses
  /// rather than a per-row call. Subjects with no role/deny data at all still get a default
  /// summary back from `auth-api` (implicit `user` role, no denials), so the result always has
  /// one entry per requested subject.
  func listRoles(subjects: [String]) async throws -> [SubjectRolesSummary] {
    try await withSpan("client-list-roles") { _ in
      guard !subjects.isEmpty else { return [] }
      let encoded = subjects.map { Self.percentEncode($0, in: .urlQueryAllowed) }
      let response = try await get(
        URI(string: baseURL + "/api/admin/roles?subjects=\(encoded.joined(separator: ","))"))
      try Self.throwOnFailure(response)
      return try response.content.decode([SubjectRolesSummary].self)
    }
  }

  func addRole(subject: String, role: String, actingUserSub: String) async throws {
    try await withSpan("client-add-role") { _ in
      let response = try await post(
        URI(string: baseURL + "/api/admin/roles/\(Self.percentEncode(subject))"),
        actingUserSub: actingUserSub
      ) { req in
        try req.content.encode(["role": role])
      }
      try Self.throwOnFailure(response)
    }
  }

  func removeRole(subject: String, role: String, actingUserSub: String) async throws {
    try await withSpan("client-remove-role") { _ in
      let response = try await delete(
        URI(string: baseURL + "/api/admin/roles/\(Self.percentEncode(subject))/\(role)"),
        actingUserSub: actingUserSub)
      try Self.throwOnFailure(response)
    }
  }

  func addDenyEntry(subject: String, service: String, actingUserSub: String) async throws {
    try await withSpan("client-add-deny-entry") { _ in
      let response = try await post(
        URI(string: baseURL + "/api/admin/deny-entries/\(Self.percentEncode(subject))"),
        actingUserSub: actingUserSub
      ) { req in
        try req.content.encode(["service": service])
      }
      try Self.throwOnFailure(response)
    }
  }

  func removeDenyEntry(subject: String, service: String, actingUserSub: String) async throws {
    try await withSpan("client-remove-deny-entry") { _ in
      let response = try await delete(
        URI(
          string: baseURL
            + "/api/admin/deny-entries/\(Self.percentEncode(subject))/\(service)"),
        actingUserSub: actingUserSub)
      try Self.throwOnFailure(response)
    }
  }

  // MARK: - Request helpers

  /// `subject` values (e.g. `auth0|abc123`) contain characters (`|`) that aren't legal
  /// unescaped in a URL path segment or query value.
  private static func percentEncode(
    _ value: String, in allowed: CharacterSet = .urlPathAllowed
  ) -> String {
    value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  /// Fails closed when `AUTH_API_INTERNAL_SERVICE_TOKEN` is unset, rather than sending an
  /// unauthenticated request `auth-api` would reject anyway - a clearer error for whoever's
  /// debugging a missing-config deployment than a generic 401 from the other service.
  private func requireToken() throws -> String {
    try await withSpan("client-require-token") { _ in
      guard let token = internalServiceToken else {
        throw Abort(
          .internalServerError,
          reason: "AUTH_API_INTERNAL_SERVICE_TOKEN is not configured")
      }
      return token
    }
  }

  private func get(_ uri: URI) async throws -> ClientResponse {
    try await withSpan("client-get-uri") { _ in
      let token = try requireToken()
      return try await client.get(uri) { req in
        req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
        applyTraceparent(&req)
      }
    }
  }

  private func post(
    _ uri: URI, actingUserSub: String,
    beforeSend: @escaping (inout ClientRequest) throws -> Void = { _ in }
  )
    async throws -> ClientResponse
  {
    try await withSpan("client-post-uri") { _ in
      let token = try requireToken()
      return try await client.post(uri) { req in
        req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
        req.headers.replaceOrAdd(name: actingUserSubHeaderName, value: actingUserSub)
        applyTraceparent(&req)
        try beforeSend(&req)
      }
    }
  }

  private func delete(_ uri: URI, actingUserSub: String) async throws -> ClientResponse {
    try await withSpan("client-delete-uri") { _ in
      let token = try requireToken()
      return try await client.delete(uri) { req in
        req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
        req.headers.replaceOrAdd(name: actingUserSubHeaderName, value: actingUserSub)
        applyTraceparent(&req)
      }
    }
  }

  private func applyTraceparent(_ req: inout ClientRequest) {
    if let traceparent {
      req.headers.replaceOrAdd(name: "traceparent", value: traceparent)
    }
  }

  private static func throwOnFailure(_ response: ClientResponse) throws {
    guard (200..<300).contains(response.status.code) else {
      throw Abort(
        response.status, reason: "auth-api request failed with status \(response.status.code)")
    }
  }
}

extension Request {
  var authAPI: AuthAPIClient { AuthAPIClient(request: self) }
}
