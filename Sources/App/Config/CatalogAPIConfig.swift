import Vapor

/// Base URL for `catalog-api`, read for the metrics overview page's per-entity-type document
/// counts (`GET /stats`). Calls happen server-to-server, so this defaults to an in-cluster DNS
/// name - not a public ingress host - matching `AdminAPIConfig.swift`'s pattern. `GET /stats` is
/// unauthenticated, so this config carries no credential.
struct CatalogAPIConfig {
  let baseURL: String

  static func fromEnvironment() -> CatalogAPIConfig {
    CatalogAPIConfig(
      baseURL: Environment.get("CATALOG_API_URL")
        ?? "http://api-v1.sweetrpg-catalog.svc.cluster.local:8000"
    )
  }
}

extension Application {
  private struct CatalogAPIConfigKey: StorageKey {
    typealias Value = CatalogAPIConfig
  }

  var catalogAPIConfig: CatalogAPIConfig {
    get {
      guard let config = storage[CatalogAPIConfigKey.self] else {
        let config = CatalogAPIConfig.fromEnvironment()
        storage[CatalogAPIConfigKey.self] = config
        return config
      }
      return config
    }
    set { storage[CatalogAPIConfigKey.self] = newValue }
  }
}

extension Request {
  var catalogAPIConfig: CatalogAPIConfig { application.catalogAPIConfig }
}
