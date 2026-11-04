import Tracing
import Vapor

/// A subject's roles and per-service deny entries, as returned by `auth-api`'s `RolesController`
/// (`GET /api/admin/roles`). Mirrors that controller's `SubjectRolesSummary` exactly.
struct SubjectRolesSummary: Content {
  let subject: String
  let roles: [String]
  let deniedServices: [String]
}

/// `auth-api`'s `GET /api/admin/deny-entries/stats` body - the number of distinct subjects with
/// at least one active deny entry, for the metrics page's "user issues" card. A dedicated count
/// endpoint rather than listing every deny entry and counting client-side.
struct RestrictedUsersStats: Content {
  let restrictedUsers: Int

  enum CodingKeys: String, CodingKey {
    case restrictedUsers = "restricted_users"
  }
}

/// Thin client for `auth-api`'s subject-keyed `/api/admin/roles`/`/api/admin/deny-entries`
/// role/service-access management surface - the counterpart to `UsersAPIClient.swift`'s identity
/// listing. `admin-web`'s role-management UI composes both: `users-api` for who a user is
/// (id/email), `auth-api` for what they're allowed to do (roles/deny entries), joined by Auth0
/// subject. See `sweetrpg/platform`'s `split-authz-into-auth-api` change design.md.
///
/// Every call forwards the signed-in admin's own Auth0 access token as an `Authorization`
/// bearer. `auth-api` verifies it, checks the admin role itself, and takes the acting user for its
/// audit log from the verified token - this app holds no service credential and sends no
/// acting-user header.
struct AuthAPIClient {
  let client: Client
  let baseURL: String

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.authAPIConfig.baseURL
  }

  /// Bulk lookup for a set of subjects, in one round trip - what `admin-web`'s user list uses
  /// rather than a per-row call. Subjects with no role/deny data at all still get a default
  /// summary back from `auth-api` (implicit `user` role, no denials), so the result always has
  /// one entry per requested subject.
  func listRoles(subjects: [String], accessToken: String) async throws -> [SubjectRolesSummary] {
    try await withSpan("client-list-roles") { _ in
      guard !subjects.isEmpty else { return [] }
      let encoded = subjects.map { Self.percentEncode($0, in: .urlQueryAllowed) }
      let response = try await get(
        URI(string: baseURL + "/api/admin/roles?subjects=\(encoded.joined(separator: ","))"),
        accessToken: accessToken)
      try Self.throwOnFailure(response)
      return try response.content.decode([SubjectRolesSummary].self)
    }
  }

  /// Count of distinct subjects with at least one active deny entry - the metrics page's "user
  /// issues" card.
  func fetchRestrictedUserCount(accessToken: String) async throws -> RestrictedUsersStats {
    try await withSpan("client-restricted-user-count") { _ in
      let response = try await get(
        URI(string: baseURL + "/api/admin/deny-entries/stats"), accessToken: accessToken)
      try Self.throwOnFailure(response)
      return try response.content.decode(RestrictedUsersStats.self)
    }
  }

  func addRole(subject: String, role: String, accessToken: String) async throws {
    try await withSpan("client-add-role") { _ in
      let response = try await post(
        URI(string: baseURL + "/api/admin/roles/\(Self.percentEncode(subject))"),
        accessToken: accessToken
      ) { req in
        try req.content.encode(["role": role])
      }
      try Self.throwOnFailure(response)
    }
  }

  func removeRole(subject: String, role: String, accessToken: String) async throws {
    try await withSpan("client-remove-role") { _ in
      let response = try await delete(
        URI(string: baseURL + "/api/admin/roles/\(Self.percentEncode(subject))/\(role)"),
        accessToken: accessToken)
      try Self.throwOnFailure(response)
    }
  }

  func addDenyEntry(subject: String, service: String, accessToken: String) async throws {
    try await withSpan("client-add-deny-entry") { _ in
      let response = try await post(
        URI(string: baseURL + "/api/admin/deny-entries/\(Self.percentEncode(subject))"),
        accessToken: accessToken
      ) { req in
        try req.content.encode(["service": service])
      }
      try Self.throwOnFailure(response)
    }
  }

  func removeDenyEntry(subject: String, service: String, accessToken: String) async throws {
    try await withSpan("client-remove-deny-entry") { _ in
      let response = try await delete(
        URI(
          string: baseURL
            + "/api/admin/deny-entries/\(Self.percentEncode(subject))/\(service)"),
        accessToken: accessToken)
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

  private func get(_ uri: URI, accessToken: String) async throws -> ClientResponse {
    try await withSpan("client-get-uri") { _ in
      try await client.get(uri) { req in
        req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      }
    }
  }

  private func post(
    _ uri: URI, accessToken: String,
    beforeSend: @escaping (inout ClientRequest) throws -> Void = { _ in }
  )
    async throws -> ClientResponse
  {
    try await withSpan("client-post-uri") { _ in
      try await client.post(uri) { req in
        req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
        try beforeSend(&req)
      }
    }
  }

  private func delete(_ uri: URI, accessToken: String) async throws -> ClientResponse {
    try await withSpan("client-delete-uri") { _ in
      try await client.delete(uri) { req in
        req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      }
    }
  }

  private static func throwOnFailure(_ response: ClientResponse) throws {
    try BackendHTTPError.check(response, backend: "auth-api")
  }
}

extension Request {
  var authAPI: AuthAPIClient { AuthAPIClient(request: self) }
}
