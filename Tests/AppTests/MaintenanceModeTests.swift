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
