import Vapor

/// One catalog entity type's tile: its record count and, when non-empty, a link to the single
/// most recently added record. `hasMostRecent` is false for a zero-count type, and the template
/// renders no "most recent" link in that case.
struct CatalogTileVM: Content {
  let count: Int
  let hasMostRecent: Bool
  let mostRecentName: String
  let mostRecentURL: String

  static let zero = CatalogTileVM(
    count: 0, hasMostRecent: false, mostRecentName: "", mostRecentURL: "")

  /// - Parameter detailURLBase: `Request.rootURL` (the platform root, trailing slash), so the
  ///   most-recent link points at catalog-web's detail page for that record.
  init(_ stats: CatalogTypeStats, typePath: String, detailURLBase: String) {
    self.count = stats.count
    if let recent = stats.mostRecent, stats.count > 0 {
      self.hasMostRecent = true
      self.mostRecentName = recent.name
      self.mostRecentURL = "\(detailURLBase)catalog/\(typePath)/\(recent.id)"
    } else {
      self.hasMostRecent = false
      self.mostRecentName = ""
      self.mostRecentURL = ""
    }
  }

  private init(count: Int, hasMostRecent: Bool, mostRecentName: String, mostRecentURL: String) {
    self.count = count
    self.hasMostRecent = hasMostRecent
    self.mostRecentName = mostRecentName
    self.mostRecentURL = mostRecentURL
  }
}

/// User-population tile. `ok` is false when `users-api`'s `GET /admin/stats` could not be
/// reached; the template shows an error state and the counts are ignored.
struct UserMetricsVM: Content {
  let ok: Bool
  let totalUsers: Int
  let activeUsers: Int

  static let failed = UserMetricsVM(ok: false, totalUsers: 0, activeUsers: 0)

  static func from(_ result: Result<UserStats, Error>) -> UserMetricsVM {
    switch result {
    case .success(let s):
      return UserMetricsVM(ok: true, totalUsers: s.totalUsers, activeUsers: s.activeUsers)
    case .failure:
      return .failed
    }
  }
}

/// Catalog document counts, one tile per entity type. `ok` is false when `catalog-api`'s
/// `GET /stats` could not be reached or decoded; the template shows a single error state in
/// place of the six tiles.
struct CatalogMetricsVM: Content {
  let ok: Bool
  let volumes: CatalogTileVM
  let publishers: CatalogTileVM
  let studios: CatalogTileVM
  let persons: CatalogTileVM
  let licenses: CatalogTileVM
  let systems: CatalogTileVM

  static let failed = CatalogMetricsVM(
    ok: false, volumes: .zero, publishers: .zero, studios: .zero, persons: .zero,
    licenses: .zero, systems: .zero)

  static func from(_ result: Result<CatalogStats, Error>, detailURLBase: String) -> CatalogMetricsVM
  {
    guard case .success(let s) = result else { return .failed }
    return CatalogMetricsVM(
      ok: true,
      volumes: CatalogTileVM(s.volumes, typePath: "volumes", detailURLBase: detailURLBase),
      publishers: CatalogTileVM(s.publishers, typePath: "publishers", detailURLBase: detailURLBase),
      studios: CatalogTileVM(s.studios, typePath: "studios", detailURLBase: detailURLBase),
      persons: CatalogTileVM(s.persons, typePath: "persons", detailURLBase: detailURLBase),
      licenses: CatalogTileVM(s.licenses, typePath: "licenses", detailURLBase: detailURLBase),
      systems: CatalogTileVM(s.systems, typePath: "systems", detailURLBase: detailURLBase))
  }

  private init(
    ok: Bool, volumes: CatalogTileVM, publishers: CatalogTileVM, studios: CatalogTileVM,
    persons: CatalogTileVM, licenses: CatalogTileVM, systems: CatalogTileVM
  ) {
    self.ok = ok
    self.volumes = volumes
    self.publishers = publishers
    self.studios = studios
    self.persons = persons
    self.licenses = licenses
    self.systems = systems
  }
}

/// Game-system document count. `ok` is false when `game-systems-api`'s `GET /stats` could not be
/// reached.
struct GameSystemsMetricsVM: Content {
  let ok: Bool
  let count: Int

  static let failed = GameSystemsMetricsVM(ok: false, count: 0)

  static func from(_ result: Result<GameSystemsStats, Error>) -> GameSystemsMetricsVM {
    switch result {
    case .success(let s):
      return GameSystemsMetricsVM(ok: true, count: s.gameSystems)
    case .failure:
      return .failed
    }
  }
}

struct MetricsPageContext: Content {
  let users: UserMetricsVM
  let catalog: CatalogMetricsVM
  let gameSystems: GameSystemsMetricsVM
  let user: LeafUser?
  let meta: PageMeta
}
