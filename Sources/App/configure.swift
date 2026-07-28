import Leaf
import Redis
import Vapor

// TODO: HEALTH_TOKEN-gated deep health check (see docs/service-conventions.md's Health checks
// section) once this app has something worth deep-checking beyond "is the process up" - it has
// no local state of its own (Redis is a session store, not a source of truth; banner data lives
// in admin-api), so a shallow liveness check is the honest answer for now.

public func configure(_ app: Application) async throws {
  app.http.server.configuration.hostname = "0.0.0.0"
  app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

  app.views.use(.leaf)

  app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

  app.sessions.configuration.cookieName = "admin-web-session"
  // Redis-backed sessions: this app can run multiple replicas behind a Service with no session
  // affinity, so an in-memory session store would only work for whichever replica handled login.
  // Falls back to in-memory if Redis isn't configured (local dev, or a single-replica dev
  // deployment that hasn't wired up Redis yet).
  if let redisHost = Environment.get("REDIS_HOST"), !redisHost.isEmpty {
    let redisPort = Environment.get("REDIS_PORT").flatMap(Int.init) ?? 6379
    let redisDB = Environment.get("REDIS_DB").flatMap(Int.init) ?? 0
    app.redis.configuration = try RedisConfiguration(
      hostname: redisHost,
      port: redisPort,
      password: Environment.get("REDIS_PASS"),
      database: redisDB
    )
    // Not `.redis` (Vapor's stock RedisSessionsDriver): that driver propagates Redis errors
    // straight through SessionsMiddleware, which runs on every request, so a Redis outage would
    // 500 the whole app. ResilientRedisSessionDriver degrades instead - see its doc comment.
    app.sessions.use { _ in ResilientRedisSessionDriver() }
  } else {
    app.logger.warning(
      "REDIS_HOST not set - using in-memory sessions. Fine for local development, not for multi-replica deployments."
    )
    app.sessions.use(.memory)
  }
  app.middleware.use(app.sessions.middleware)

  // Every route below this line requires a valid session - see AuthRequiredMiddleware's doc
  // comment for why this is a blanket gate rather than per-route opt-in.
  app.middleware.use(AuthRequiredMiddleware())

  try routes(app)
}
