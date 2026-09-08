import Tracing
import Vapor

/// One catalog entity type's slice of `catalog-api`'s `GET /stats` response
/// (`catalog-landing-summary`): the current record count and, when the type has any records, the
/// single most recently added one. Only the fields the metrics page needs are decoded; a future
/// additive field in the payload is ignored rather than breaking the decode.
struct CatalogTypeStats: Content {
  let count: Int
  let mostRecent: RecentRef?

  struct RecentRef: Content {
    let id: String
    let name: String
  }

  enum CodingKeys: String, CodingKey {
    case count
    case mostRecent = "most_recent"
  }
}

/// `catalog-api`'s `GET /stats` body - one `CatalogTypeStats` per catalog entity type. Shape is
/// owned by `sweetrpg/platform`'s `catalog-landing-summary` spec; consumed here as-is.
struct CatalogStats: Content {
  let volumes: CatalogTypeStats
  let publishers: CatalogTypeStats
  let studios: CatalogTypeStats
  let persons: CatalogTypeStats
  let licenses: CatalogTypeStats
  let systems: CatalogTypeStats
}

/// Thin client for `catalog-api`'s unauthenticated `GET /stats` - the counterpart to
/// `AdminAPIClient.swift`, minus any credential (this endpoint feeds a public landing page and
/// takes none).
struct CatalogAPIClient {
  let client: Client
  let baseURL: String

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.catalogAPIConfig.baseURL
  }

  func fetchStats() async throws -> CatalogStats {
    try await withSpan("client-catalog-stats") { _ in
      let response = try await client.get(URI(string: baseURL + "/stats"))
      guard (200..<300).contains(response.status.code) else {
        throw Abort(
          response.status, reason: "catalog-api request failed with status \(response.status.code)")
      }
      return try response.content.decode(CatalogStats.self)
    }
  }
}

extension Request {
  var catalogAPI: CatalogAPIClient { CatalogAPIClient(request: self) }
}
