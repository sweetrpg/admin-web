import Vapor

/// Base URL for `auth-api`, the backend this app manages user roles/service-access through
/// (moved off `users-api` - see `sweetrpg/platform`'s `split-authz-into-auth-api` change). Calls
/// happen server-to-server, so this defaults to an in-cluster DNS name. They carry the signed-in
/// admin's own access token (see `AuthAPIClient.swift`), so this config holds no credential.
struct AuthAPIConfig {
  let baseURL: String

  static func fromEnvironment() -> AuthAPIConfig {
    AuthAPIConfig(
      baseURL: Environment.get("AUTH_API_URL")
        ?? "http://api-v1.sweetrpg-auth.svc.cluster.local:8080"
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
