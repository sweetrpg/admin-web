import Metrics
import Prometheus
import Vapor

/// Bootstraps swift-metrics with a Prometheus backend and exposes it at `/metrics`, matching
/// the Go services' `gin-metrics` convention (docs/service-conventions.md's Telemetry section) -
/// same path, same text exposition format, scraped the same way via a `PodMonitor`.
enum MetricsSetup {
  /// `MetricsSystem.bootstrap` may run once per process, but `configure(_:)` runs once per test
  /// case; a lazily initialized static keeps the bootstrap to a single call.
  private static let factory: PrometheusMetricsFactory = {
    let factory = PrometheusMetricsFactory()
    MetricsSystem.bootstrap(factory)
    return factory
  }()

  static func bootstrap(_ app: Application) {
    let factory = Self.factory
    app.get("metrics") { _ -> Response in
      Response(
        status: .ok,
        headers: ["content-type": "text/plain; version=0.0.4"],
        body: .init(string: factory.registry.emitToString())
      )
    }
  }
}
