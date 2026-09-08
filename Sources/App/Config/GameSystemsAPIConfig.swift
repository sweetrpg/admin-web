import Vapor

/// Base URL for `game-systems-api`, read for the metrics overview page's game-system document
/// count (`GET /stats`). Calls happen server-to-server, so this defaults to an in-cluster DNS
/// name - not a public ingress host - matching `AdminAPIConfig.swift`'s pattern. `GET /stats` is
/// unauthenticated, so this config carries no credential.
struct GameSystemsAPIConfig {
  let baseURL: String

  static func fromEnvironment() -> GameSystemsAPIConfig {
    GameSystemsAPIConfig(
      baseURL: Environment.get("GAME_SYSTEMS_API_URL")
        ?? "http://api-v1.sweetrpg-game-systems.svc.cluster.local:8000"
    )
  }
}

extension Application {
  private struct GameSystemsAPIConfigKey: StorageKey {
    typealias Value = GameSystemsAPIConfig
  }

  var gameSystemsAPIConfig: GameSystemsAPIConfig {
    get {
      guard let config = storage[GameSystemsAPIConfigKey.self] else {
        let config = GameSystemsAPIConfig.fromEnvironment()
        storage[GameSystemsAPIConfigKey.self] = config
        return config
      }
      return config
    }
    set { storage[GameSystemsAPIConfigKey.self] = newValue }
  }
}

extension Request {
  var gameSystemsAPIConfig: GameSystemsAPIConfig { application.gameSystemsAPIConfig }
}
