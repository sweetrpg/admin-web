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
}
