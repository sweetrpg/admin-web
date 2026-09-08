import Tracing
import Vapor

/// The metrics overview - `admin-web`'s landing page (`GET /`). A card dashboard composed from
/// `catalog-api`, `game-systems-api`, `users-api`, `admin-api`, and `auth-api`, in the same
/// server-to-server style as `UsersController`. Already `admin`-gated by
/// `AuthRequiredMiddleware`'s blanket check.
///
/// Every card's source is fetched concurrently and independently: a thrown error or timeout
/// from one yields a `.failed` card (rendered as a dash) rather than failing the page.
struct MetricsController: RouteCollection {
  func boot(routes: RoutesBuilder) throws {
    routes.get(use: overview)
  }

  @Sendable
  func overview(req: Request) async throws -> View {
    try await withSpan("metrics-overview") { _ in
      let accessToken = (await req.currentUser)?.accessToken

      async let catalog = Self.fetchCatalog(req)
      async let gameSystems = Self.fetchGameSystems(req)
      async let userStats = Self.fetchUsers(req, accessToken: accessToken)
      async let banners = Self.card { try await req.adminAPI.activeBannerCount() }
      async let maintenance = Self.card { try await req.adminAPI.activeMaintenanceCount() }
      async let issues = Self.card {
        try await req.authAPI.fetchRestrictedUserCount().restrictedUsers
      }

      let users = await userStats
      return try await req.view.render(
        "metrics/overview",
        MetricsPageContext(
          catalog: await catalog,
          gameSystems: await gameSystems,
          totalUsers: users.total,
          activeUsers: users.active,
          newUsers: users.new,
          activeBanners: await banners,
          activeMaintenance: await maintenance,
          userIssues: await issues,
          user: (await req.currentUser).map(LeafUser.init),
          meta: PageMeta(req)
        ))
    }
  }

  /// Runs `body` and turns its result into an `ok` card, or a `.failed` card on any error. The
  /// per-card degradation path shared by the single-count cards.
  private static func card(_ body: @escaping () async throws -> Int) async -> MetricCardVM {
    do {
      return .count(try await body())
    } catch {
      return .failed
    }
  }

  private static func fetchCatalog(_ req: Request) async -> CatalogCardsVM {
    do {
      return .from(.success(try await req.catalogAPI.fetchStats()), detailURLBase: req.rootURL)
    } catch {
      req.logger.error("metrics: catalog-api stats failed: \(error)")
      return .failed
    }
  }

  private static func fetchGameSystems(_ req: Request) async -> MetricCardVM {
    do {
      return .count(try await req.gameSystemsAPI.fetchStats().gameSystems)
    } catch {
      req.logger.error("metrics: game-systems-api stats failed: \(error)")
      return .failed
    }
  }

  private struct UserCards {
    let total: MetricCardVM
    let active: MetricCardVM
    let new: MetricCardVM
    static let allFailed = UserCards(total: .failed, active: .failed, new: .failed)
  }

  private static func fetchUsers(_ req: Request, accessToken: String?) async -> UserCards {
    guard let accessToken else {
      req.logger.error("metrics: no access token on the acting session")
      return .allFailed
    }
    do {
      let s = try await req.usersAPI.fetchAdminStats(accessToken: accessToken)
      return UserCards(
        total: .count(s.totalUsers),
        active: .count(s.activeUsers),
        // `new_users` is absent until users-api ships it - render that card as unavailable
        // rather than a misleading zero.
        new: s.newUsers.map(MetricCardVM.count) ?? .failed)
    } catch {
      req.logger.error("metrics: users-api stats failed: \(error)")
      return .allFailed
    }
  }
}
