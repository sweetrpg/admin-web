import Vapor

/// The identity `auth-web` writes into the shared session store - mirrors its own `SessionUser`
/// model. `roles` comes from `users-api`'s verified `/authz/check` response (`auth-web` called
/// it once at login), not an unverified local ID-token decode - this app no longer decodes any
/// token itself. `AuthRequiredMiddleware` trusts `roles` as already verified rather than calling
/// `/authz/check` again per request.
struct SessionUser: Codable {
  let sub: String
  let name: String
  let email: String?
  let roles: [String]
  /// The Auth0 access token from `auth-web`'s code exchange, forwarded as this app's own
  /// outgoing bearer token on write calls to `admin-api`/`users-api` - see platform's
  /// `api-client-auth` change. Those services authorize the action against this token's own
  /// verified user/role, not against this app's identity.
  let accessToken: String
  /// When this session becomes invalid, set by `auth-web` at write time. A session at or past
  /// this timestamp must be treated as absent, not stale data - see `sweetrpg/platform`'s
  /// `docs/frontend-conventions.md` ("Shared session schema"). Enforced independently at the
  /// Redis key level by `ResilientRedisSessionDriver`'s TTL; this check is defense in depth for
  /// this app's read-only client, which never goes through that driver.
  let expiry: Date
}
