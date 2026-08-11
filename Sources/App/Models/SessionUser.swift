import Vapor

/// The identity `auth-web` writes into the shared session store - mirrors its own `SessionUser`
/// model. `roles` comes from `users-api`'s verified `/authz/check` response (`auth-web` called
/// it once at login), not an unverified local ID-token decode - this app no longer decodes any
/// token itself. `AuthRequiredMiddleware` trusts `roles` as already verified rather than calling
/// `/authz/check` again per request: this app never holds a bearer token of its own to present
/// (it never talks to Auth0), only the session `auth-web` already established.
struct SessionUser: Codable {
  let sub: String
  let name: String
  let email: String?
  let roles: [String]
  /// When this session becomes invalid, set by `auth-web` at write time. A session at or past
  /// this timestamp must be treated as absent, not stale data - see `sweetrpg/platform`'s
  /// `docs/frontend-conventions.md` ("Shared session schema"). Enforced independently at the
  /// Redis key level by `ResilientRedisSessionDriver`'s TTL; this check is defense in depth for
  /// this app's read-only client, which never goes through that driver.
  let expiry: Date
}
