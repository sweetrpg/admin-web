import Vapor

/// What admin-web needs from `entitlements-api`. A protocol so the page can be tested against a
/// stub; `EntitlementsAPIClient` is the production implementation. admin-web decides nothing
/// about values: it renders what the service returns and sends what the admin enters.
protocol EntitlementsServing: Sendable {
  func read(userID: String, accessToken: String) async throws -> [EntitlementRecord]
  func recentAudit(userID: String, accessToken: String) async throws -> [AuditEntry]
  func setOverride(
    userID: String, key: String, request: OverrideRequest, accessToken: String
  ) async throws
  func removeOverride(
    userID: String, key: String, reason: String, accessToken: String
  ) async throws
}

extension Application {
  private struct EntitlementsServiceKey: StorageKey {
    typealias Value = any EntitlementsServing
  }

  /// Replaces the production client; used by tests.
  var entitlementsServiceOverride: (any EntitlementsServing)? {
    get { storage[EntitlementsServiceKey.self] }
    set { storage[EntitlementsServiceKey.self] = newValue }
  }
}

extension Request {
  var entitlements: any EntitlementsServing {
    application.entitlementsServiceOverride ?? EntitlementsAPIClient(request: self)
  }
}
