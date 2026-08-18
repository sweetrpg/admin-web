import Vapor

/// Base URL for `users-api`, the Go backend this app reads user identities through. Calls
/// happen server-to-server, so this defaults to an in-cluster DNS name - not a public ingress
/// host - matching `AdminAPIConfig.swift`'s pattern.
///
/// Calls present the acting user's own Auth0 access token (from the shared session) as an
/// `Authorization` bearer - see `UsersAPIClient.swift` - not a shared app secret, so this
/// config carries no credential of its own.
struct UsersAPIConfig {
  let baseURL: String

  static func fromEnvironment() -> UsersAPIConfig {
    UsersAPIConfig(
      baseURL: Environment.get("USERS_API_URL")
        ?? "http://api-v1.sweetrpg-user.svc.cluster.local:8000"
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
