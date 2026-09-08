import Tracing
import Vapor

/// A user's identity, as returned by `users-api`'s `AdminUsersController`
/// (`GET /admin/users`). `subject` is the Auth0 `sub` this user last logged in with (from
/// `LoginProfile`) - the key `auth-api`'s role/deny-entry data is stored under, `nil` if this
/// user has no Auth0 `LoginProfile` yet.
struct UserIdentity: Content {
  let id: String
  let email: String
  let subject: String?
}

/// `users-api`'s `GET /admin/stats` body - total user count, the count active within a rolling
/// 30-day login window, and (once `users-api` ships it) the count of signups in the last 7
/// days. `newUsers` is optional so this decodes against a `users-api` release that predates the
/// field; the metrics page renders that card as unavailable until it appears.
struct UserStats: Content {
  let totalUsers: Int
  let activeUsers: Int
  let newUsers: Int?

  enum CodingKeys: String, CodingKey {
    case totalUsers = "total_users"
    case activeUsers = "active_users"
    case newUsers = "new_users"
  }
}

/// Thin client for `users-api`'s minimal `/api/admin/users` identity listing - the counterpart
/// to `AdminAPIClient.swift`'s `/banners` client. Presents the acting user's own Auth0 access
/// token as an `Authorization` bearer; `users-api` verifies it and checks the user's role
/// itself, rather than trusting this app's identity.
///
/// This used to also carry role/deny-entry CRUD, before that moved to `auth-api` (see
/// `AuthAPIClient.swift`) as part of `sweetrpg/platform`'s `split-authz-into-auth-api` change -
/// `users-api` now has no authorization data to serve, only identity.
struct UsersAPIClient {
  let client: Client
  let baseURL: String

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.usersAPIConfig.baseURL
  }

  func listUsers(accessToken: String) async throws -> [UserIdentity] {
    try await withSpan("client-list-users") { _ in
      let response = try await client.get(URI(string: baseURL + "/admin/users")) { req in
        req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      }
      guard (200..<300).contains(response.status.code) else {
        throw Abort(
          response.status, reason: "users-api request failed with status \(response.status.code)")
      }
      return try response.content.decode([UserIdentity].self)
    }
  }

  /// `GET /admin/stats` - user population counts for the metrics overview page. Forwards the
  /// acting admin's own Auth0 access token as the bearer, same as `listUsers`; `users-api`
  /// verifies it and checks the `admin` role itself.
  func fetchAdminStats(accessToken: String) async throws -> UserStats {
    try await withSpan("client-admin-stats") { _ in
      let response = try await client.get(URI(string: baseURL + "/admin/stats")) { req in
        req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      }
      guard (200..<300).contains(response.status.code) else {
        throw Abort(
          response.status, reason: "users-api request failed with status \(response.status.code)")
      }
      return try response.content.decode(UserStats.self)
    }
  }
}

extension Request {
  var usersAPI: UsersAPIClient { UsersAPIClient(request: self) }
}
