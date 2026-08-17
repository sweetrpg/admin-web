import Vapor

/// Base URL and shared secret for admin-api, the Go backend this app manages banner messages
/// through. Calls happen server-to-server (this app's pods to admin-api's ClusterIP Service), so
/// the base URL defaults to an in-cluster DNS name - not a public ingress host - matching
/// BackendConfig.swift's pattern in catalog-web. Override via env var for local development
/// against a port-forwarded or public dev endpoint.
///
/// `internalServiceToken` is presented as `X-Internal-Service-Token` on every *write* call
/// instead of an Auth0 bearer token - this app never holds one of its own, same rationale as
/// `UsersAPIConfig.swift`. Unset means every mutating `AdminAPIClient` call fails closed (see
/// `AdminAPIClient.swift`), not silently sent unauthenticated.
struct AdminAPIConfig {
  let baseURL: String
  let internalServiceToken: String?

  static func fromEnvironment() -> AdminAPIConfig {
    AdminAPIConfig(
      baseURL: Environment.get("ADMIN_API_URL")
        ?? "http://api-v1.sweetrpg-admin.svc.cluster.local:8000",
      internalServiceToken: Environment.get("ADMIN_API_INTERNAL_SERVICE_TOKEN")
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
