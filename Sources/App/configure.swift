import Leaf
import Logging
import OTel
import Redis
import Tracing
import Vapor

// TODO: HEALTH_TOKEN-gated deep health check (see docs/service-conventions.md's Health checks
// section) once this app has something worth deep-checking beyond "is the process up" - it has
// no local state of its own (Redis is a session store, not a source of truth; banner data lives
// in admin-api), so a shallow liveness check is the honest answer for now.

public func configure(_ app: Application) async throws {
  // Structured JSON logging is bootstrapped once in entrypoint.swift, not here - LoggingSystem's
  // bootstrap can only run once per process, and configure(_:) runs once per test case under
  // swift-testing, which would crash on the second call.

  // Bootstrap distributed tracing via OTLP/gRPC to the cluster's Tempo collector. Uses
  // OTEL_EXPORTER_OTLP_ENDPOINT env var (same endpoint the Go services export to via HTTP,
  // but this app uses gRPC per swift-otel's available transports).
  try await TracingSetup.bootstrap(app)
  app.http.server.configuration.hostname = "0.0.0.0"
  app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

  // Creates a server-kind span per request, extracting an inbound traceparent header if present.
  // request.serviceContext is set for the request's duration, so outgoing calls via
  // request.client (AsyncHTTPClient) automatically inject the current span's context into their
  // own headers - see HTTPClientRequest+Prepared.swift upstream.
  app.middleware.use(TracingMiddleware())

  app.views.use(.leaf)

  app.middleware.use(SentryMiddleware())

  app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

  // The shared "redis" instance in sweetrpg-support (auth-web's session store), read-only from
  // here - not dedicated to any one service. See docs/frontend-conventions.md's "Shared
  // sweetrpg-support Redis instance" section (sweetrpg/platform) for the full DB-index
  // registry. This app never runs its own Auth0 code-exchange or SessionsMiddleware - see
  // SessionUserAccess.swift.
  if let redisHost = Environment.get("REDIS_HOST"), !redisHost.isEmpty {
    let redisPort = Environment.get("REDIS_PORT").flatMap(Int.init) ?? 6379
    // Must match auth-web's own DB index - this app reads the exact session keys auth-web
    // writes, not a namespace of its own.
    let redisDB = Environment.get("REDIS_DB").flatMap(Int.init) ?? 0
    app.redis.configuration = try RedisConfiguration(
      hostname: redisHost,
      port: redisPort,
      password: Environment.get("REDIS_PASS"),
      database: redisDB
    )
    app.sharedSessionRedisConfigured = true
  } else {
    app.logger.warning(
      "REDIS_HOST not set - every visitor will read as logged-out."
    )
  }

  // Every route below this line requires a valid session with the admin role - see
  // AuthRequiredMiddleware's doc comment for why this is a blanket gate rather than per-route
  // opt-in.
  app.middleware.use(AuthRequiredMiddleware())

  try routes(app)
}
