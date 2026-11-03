import Vapor

/// Base URL for `entitlements-api`, called server to server with the acting admin's own access
/// token (see `EntitlementsAPIClient.swift`), so this config carries no credential.
struct EntitlementsAPIConfig {
  let baseURL: String

  struct MissingSettingError: Error, CustomStringConvertible {
    let name: String
    var description: String { "\(name) is required and not set" }
  }

  /// Fails with the variable's name so a misconfigured deployment says what to fix at startup,
  /// not on the first page load.
  static func fromEnvironment() throws -> EntitlementsAPIConfig {
    guard let url = Environment.get("ENTITLEMENTS_API_URL"), !url.isEmpty else {
      throw MissingSettingError(name: "ENTITLEMENTS_API_URL")
    }
    return EntitlementsAPIConfig(baseURL: url)
  }
}

extension Application {
  private struct EntitlementsAPIConfigKey: StorageKey {
    typealias Value = EntitlementsAPIConfig
  }

  var entitlementsAPIConfig: EntitlementsAPIConfig? {
    get { storage[EntitlementsAPIConfigKey.self] }
    set { storage[EntitlementsAPIConfigKey.self] = newValue }
  }
}
