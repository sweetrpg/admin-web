import Vapor

/// Matches `InternalServiceAuth.headerName` in `users-api` exactly - the two repos are separate
/// Swift packages, so this can't be a shared import, only a matched string constant.
private let internalServiceTokenHeaderName = "X-Internal-Service-Token"

/// A user's roles and per-service deny entries, as returned by `users-api`'s
/// `RolesController` (`GET /api/admin/users`). Mirrors that controller's `UserSummary` exactly.
struct UserSummary: Content {
  let id: String
  let email: String
  let roles: [String]
  let deniedServices: [String]
}

/// Thin client for `users-api`'s `/api/admin/users` role/service-access management surface -
/// the counterpart to `AdminAPIClient.swift`'s `/banners` client. Every call presents
/// `X-Internal-Service-Token` instead of an Auth0 bearer token; see `UsersAPIConfig.swift`.
struct UsersAPIClient {
  let client: Client
  let baseURL: String
  let internalServiceToken: String?

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.usersAPIConfig.baseURL
    self.internalServiceToken = request.usersAPIConfig.internalServiceToken
  }

  func listUsers() async throws -> [UserSummary] {
    let response = try await get(URI(string: baseURL + "/api/admin/users"))
    try Self.throwOnFailure(response)
    return try response.content.decode([UserSummary].self)
  }

  func addRole(userID: String, role: String) async throws {
    let response = try await post(URI(string: baseURL + "/api/admin/users/\(userID)/roles")) {
      req in
      try req.content.encode(["role": role])
    }
    try Self.throwOnFailure(response)
  }

  func removeRole(userID: String, role: String) async throws {
    let response = try await delete(
      URI(string: baseURL + "/api/admin/users/\(userID)/roles/\(role)"))
    try Self.throwOnFailure(response)
  }

  func addDenyEntry(userID: String, service: String) async throws {
    let response = try await post(
      URI(string: baseURL + "/api/admin/users/\(userID)/deny-entries")
    ) { req in
      try req.content.encode(["service": service])
    }
    try Self.throwOnFailure(response)
  }

  func removeDenyEntry(userID: String, service: String) async throws {
    let response = try await delete(
      URI(string: baseURL + "/api/admin/users/\(userID)/deny-entries/\(service)"))
    try Self.throwOnFailure(response)
  }

  // MARK: - Request helpers

  /// Fails closed when `USERS_API_INTERNAL_SERVICE_TOKEN` is unset, rather than sending an
  /// unauthenticated request `users-api` would reject anyway - a clearer error for whoever's
  /// debugging a missing-config deployment than a generic 401 from the other service.
  private func requireToken() throws -> String {
    guard let token = internalServiceToken else {
      throw Abort(
        .internalServerError,
        reason: "USERS_API_INTERNAL_SERVICE_TOKEN is not configured")
    }
    return token
  }

  private func get(_ uri: URI) async throws -> ClientResponse {
    let token = try requireToken()
    return try await client.get(uri) { req in
      req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
    }
  }

  private func post(
    _ uri: URI, beforeSend: @escaping (inout ClientRequest) throws -> Void = { _ in }
  )
    async throws -> ClientResponse
  {
    let token = try requireToken()
    return try await client.post(uri) { req in
      req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
      try beforeSend(&req)
    }
  }

  private func delete(_ uri: URI) async throws -> ClientResponse {
    let token = try requireToken()
    return try await client.delete(uri) { req in
      req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
    }
  }

  private static func throwOnFailure(_ response: ClientResponse) throws {
    guard (200..<300).contains(response.status.code) else {
      throw Abort(
        response.status, reason: "users-api request failed with status \(response.status.code)")
    }
  }
}

extension Request {
  var usersAPI: UsersAPIClient { UsersAPIClient(request: self) }
}
