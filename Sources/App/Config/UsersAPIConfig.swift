import Vapor

/// Base URL and shared secret for `users-api`, the Swift backend this app manages user
/// roles/service-access through. Calls happen server-to-server, so this defaults to an
/// in-cluster DNS name - not a public ingress host - matching `AdminAPIConfig.swift`'s pattern.
///
/// `internalServiceToken` is presented as `X-Internal-Service-Token` on every call instead of an
/// Auth0 bearer token - this app never holds one of its own (see `InternalServiceAuth.swift` in
/// `users-api` for the full rationale). Unset means every `UsersAPIClient` call fails closed
/// (see `UsersAPIClient.swift`), not silently sent unauthenticated.
struct UsersAPIConfig {
  let baseURL: String
  let internalServiceToken: String?

  static func fromEnvironment() -> UsersAPIConfig {
    UsersAPIConfig(
      baseURL: Environment.get("USERS_API_URL")
        ?? "http://api-v1.sweetrpg-user.svc.cluster.local:8000",
      internalServiceToken: Environment.get("USERS_API_INTERNAL_SERVICE_TOKEN")
    )
  }
}

extension Application {
  private struct UsersAPIConfigKey: StorageKey {
    typealias Value = UsersAPIConfig
  }

  var usersAPIConfig: UsersAPIConfig {
    get {
      guard let config = storage[UsersAPIConfigKey.self] else {
        let config = UsersAPIConfig.fromEnvironment()
        storage[UsersAPIConfigKey.self] = config
        return config
      }
      return config
    }
    set { storage[UsersAPIConfigKey.self] = newValue }
  }
}

extension Request {
  var usersAPIConfig: UsersAPIConfig { application.usersAPIConfig }
}
