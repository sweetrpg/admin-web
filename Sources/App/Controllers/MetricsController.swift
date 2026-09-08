import Tracing
import Vapor

/// The metrics overview - `admin-web`'s landing page (`GET /`). Composes `users-api`,
/// `catalog-api`, and `game-systems-api` into a single platform-size dashboard, the same
/// server-to-server composition pattern `UsersController` uses. Already `admin`-gated by
/// `AuthRequiredMiddleware`'s blanket check, like every route in this app.
///
/// Each source is fetched concurrently and independently: a thrown error or timeout from one
/// yields a `.failed` tile in the view model instead of failing the whole page.
struct MetricsController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get(use: overview)
  }

  @Sendable
  func overview(req: Request) async throws -> View {
    try await withSpan("metrics-overview") { _ in
      let accessToken = (await req.currentUser)?.accessToken

      async let users = Self.fetchUserMetrics(req, accessToken: accessToken)
      async let catalog = Self.fetchCatalogMetrics(req)
      async let gameSystems = Self.fetchGameSystemsMetrics(req)

      return try await req.view.render(
        "metrics/overview",
        MetricsPageContext(
          users: await users,
          catalog: await catalog,
          gameSystems: await gameSystems,
          user: (await req.currentUser).map(LeafUser.init),
          meta: PageMeta(req)
        ))
    }
  }

  private static func fetchUserMetrics(_ req: Request, accessToken: String?) async -> UserMetricsVM
  {
    guard let accessToken else {
      // AuthRequiredMiddleware guarantees a session reached here, so this should not happen -
      // treat it as a source failure rather than a 500 so the rest of the page still renders.
      req.logger.error("metrics: no access token on the acting session")
      return .failed
    }
    do {
      return .from(.success(try await req.usersAPI.fetchAdminStats(accessToken: accessToken)))
    } catch {
      req.logger.error("metrics: users-api stats failed: \(error)")
      return .failed
    }
  }

  private static func fetchCatalogMetrics(_ req: Request) async -> CatalogMetricsVM {
    do {
      return .from(.success(try await req.catalogAPI.fetchStats()), detailURLBase: req.rootURL)
    } catch {
      req.logger.error("metrics: catalog-api stats failed: \(error)")
      return .failed
    }
  }

  private static func fetchGameSystemsMetrics(_ req: Request) async -> GameSystemsMetricsVM {
    do {
      return .from(.success(try await req.gameSystemsAPI.fetchStats()))
    } catch {
      req.logger.error("metrics: game-systems-api stats failed: \(error)")
      return .failed
    }
  }
}
