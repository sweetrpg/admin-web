import Vapor

/// Matches `InternalServiceAuth.headerName` in `users-api` exactly - the two repos are separate
/// Swift packages, so this can't be a shared import, only a matched string constant.
private let internalServiceTokenHeaderName = "X-Internal-Service-Token"

/// A user's identity, as returned by `users-api`'s `AdminUsersController`
/// (`GET /api/admin/users`). `subject` is the Auth0 `sub` this user last logged in with (from
/// `LoginProfile`) - the key `auth-api`'s role/deny-entry data is stored under, `nil` if this
/// user has no Auth0 `LoginProfile` yet.
struct UserIdentity: Content {
  let id: String
  let email: String
  let subject: String?
}

/// Thin client for `users-api`'s minimal `/api/admin/users` identity listing - the counterpart
/// to `AdminAPIClient.swift`'s `/banners` client. Every call presents
/// `X-Internal-Service-Token` instead of an Auth0 bearer token; see `UsersAPIConfig.swift`.
///
/// This used to also carry role/deny-entry CRUD, before that moved to `auth-api` (see
/// `AuthAPIClient.swift`) as part of `sweetrpg/platform`'s `split-authz-into-auth-api` change -
/// `users-api` now has no authorization data to serve, only identity.
struct UsersAPIClient {
  let client: Client
  let baseURL: String
  let internalServiceToken: String?

  /// This request's inbound trace context, if it arrived with one - forwarded on the outbound
  /// call, never fabricated. Nothing upstream of this app sets `traceparent` yet, so this is a
  /// no-op today; it activates automatically once frontend-side tracing is separately scoped
  /// (see sweetrpg/platform's migrate-auth-users-api-to-go change design.md).
  let traceparent: String?

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.usersAPIConfig.baseURL
    self.internalServiceToken = request.usersAPIConfig.internalServiceToken
    self.traceparent = request.headers.first(name: "traceparent")
  }

  func listUsers() async throws -> [UserIdentity] {
    guard let token = internalServiceToken else {
      throw Abort(
        .internalServerError,
        reason: "USERS_API_INTERNAL_SERVICE_TOKEN is not configured")
    }
    let response = try await client.get(URI(string: baseURL + "/api/admin/users")) { req in
      req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
      if let traceparent {
        req.headers.replaceOrAdd(name: "traceparent", value: traceparent)
      }
    }
    guard (200..<300).contains(response.status.code) else {
      throw Abort(
        response.status, reason: "users-api request failed with status \(response.status.code)")
    }
    return try response.content.decode([UserIdentity].self)
  }
}

extension Request {
  var usersAPI: UsersAPIClient { UsersAPIClient(request: self) }
}
