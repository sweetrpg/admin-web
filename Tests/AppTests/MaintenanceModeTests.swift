import Foundation
import Testing

@testable import App

@Suite("KnownServiceScope")
struct MaintenanceModeTests {
  @Test("includes systems in both KnownServiceScope and AppCardScopeType")
  func includesSystems() {
    #expect(KnownServiceScope.all.contains("systems"))
    #expect(AppCardScopeType.all.contains("systems"))
  }
}

@Suite("MaintenanceMode status")
struct MaintenanceModeStatusTests {
  static let now = Date(timeIntervalSince1970: 1_000_000)

  @Test(
    "active only when enabled and startsAt <= now < endsAt",
    arguments: [
      (true, -60.0, 60.0 as Double?, MaintenanceMode.Status.active),
      (true, 0, nil, .active),
      (true, 60, nil, .scheduled),
      (true, 60, 120, .scheduled),
      (true, -120, -60, .pastEnd),
      (true, -120, 0, .pastEnd),
      (false, -60, 60, .off),
      (false, -120, -60, .off),
    ])
  func status(enabled: Bool, start: Double, end: Double?, expected: MaintenanceMode.Status) {
    let mode = MaintenanceMode(
      id: "1", scopeType: .platform, scopeValue: "", enabled: enabled,
      startsAt: Self.now + start, endsAt: end.map { Self.now + $0 },
      label: "", description: "", createdAt: nil, updatedAt: nil)
    #expect(mode.status(asOf: Self.now) == expected)
  }
}
