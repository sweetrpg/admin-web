import Vapor

/// Base URL for admin-api, the Go backend this app manages banner messages through. Calls
/// happen server-to-server (this app's pods to admin-api's ClusterIP Service), so the base URL
/// defaults to an in-cluster DNS name - not a public ingress host - matching
/// BackendConfig.swift's pattern in catalog-web. Override via env var for local development
/// against a port-forwarded or public dev endpoint.
///
/// Write calls present the acting user's own Auth0 access token (from the shared session) as an
/// `Authorization` bearer - see `AdminAPIClient.swift` - not a shared app secret, so this config
/// carries no credential of its own.
struct AdminAPIConfig {
  let baseURL: String

  static func fromEnvironment() -> AdminAPIConfig {
    AdminAPIConfig(
      baseURL: Environment.get("ADMIN_API_URL")
        ?? "http://api-v1.sweetrpg-admin.svc.cluster.local:8000"
    )
  }
}

extension Application {
  private struct AdminAPIConfigKey: StorageKey {
    typealias Value = AdminAPIConfig
  }

  var adminAPIConfig: AdminAPIConfig {
    get {
      guard let config = storage[AdminAPIConfigKey.self] else {
        let config = AdminAPIConfig.fromEnvironment()
        storage[AdminAPIConfigKey.self] = config
        return config
      }
      return config
    }
    set { storage[AdminAPIConfigKey.self] = newValue }
  }
}

extension Request {
  var adminAPIConfig: AdminAPIConfig { application.adminAPIConfig }
}
