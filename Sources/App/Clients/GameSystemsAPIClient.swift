import Tracing
import Vapor

/// `game-systems-api`'s `GET /stats` body - a plain object with the current game-system document
/// count. Shape is owned by `sweetrpg/platform`'s `game-systems-api-stats` spec.
struct GameSystemsStats: Content {
  let gameSystems: Int

  enum CodingKeys: String, CodingKey {
    case gameSystems = "game_systems"
  }
}

/// Thin client for `game-systems-api`'s unauthenticated `GET /stats`, mirroring
/// `CatalogAPIClient.swift` - no credential, consistent with `catalog-api`'s own `/stats`.
struct GameSystemsAPIClient {
  let client: Client
  let baseURL: String

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.gameSystemsAPIConfig.baseURL
  }

  func fetchStats() async throws -> GameSystemsStats {
    try await withSpan("client-game-systems-stats") { _ in
      let response = try await client.get(URI(string: baseURL + "/stats"))
      guard (200..<300).contains(response.status.code) else {
        throw Abort(
          response.status,
          reason: "game-systems-api request failed with status \(response.status.code)")
      }
      return try response.content.decode(GameSystemsStats.self)
    }
  }
}

extension Request {
  var gameSystemsAPI: GameSystemsAPIClient { GameSystemsAPIClient(request: self) }
}
