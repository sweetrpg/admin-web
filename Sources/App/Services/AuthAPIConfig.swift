import Vapor

/// Base URL and shared secret for `auth-api`, the Swift backend this app manages user
/// roles/service-access through (moved off `users-api` - see `sweetrpg/platform`'s
/// `split-authz-into-auth-api` change). Calls happen server-to-server, so this defaults to an
/// in-cluster DNS name - not a public ingress host - matching `UsersAPIConfig.swift`'s pattern.
///
/// `internalServiceToken` is presented as `X-Internal-Service-Token` on every call instead of an
/// Auth0 bearer token - this app never holds one of its own. This is a distinct secret from
/// `USERS_API_INTERNAL_SERVICE_TOKEN` - the two services' internal-service-auth trust boundaries
/// are independent, not required to share a value.
struct AuthAPIConfig {
  let baseURL: String
  let internalServiceToken: String?

  static func fromEnvironment() -> AuthAPIConfig {
    AuthAPIConfig(
      baseURL: Environment.get("AUTH_API_URL")
        ?? "http://api-v1.sweetrpg-auth.svc.cluster.local:8080",
      internalServiceToken: Environment.get("AUTH_API_INTERNAL_SERVICE_TOKEN")
    )
  }
}

extension Application {
  private struct AuthAPIConfigKey: StorageKey {
    typealias Value = AuthAPIConfig
  }

  var authAPIConfig: AuthAPIConfig {
    get {
      guard let config = storage[AuthAPIConfigKey.self] else {
        let config = AuthAPIConfig.fromEnvironment()
        storage[AuthAPIConfigKey.self] = config
        return config
      }
      return config
    }
    set { storage[AuthAPIConfigKey.self] = newValue }
  }
}

extension Request {
  var authAPIConfig: AuthAPIConfig { application.authAPIConfig }
}
