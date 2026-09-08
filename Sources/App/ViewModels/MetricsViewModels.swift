import Foundation
import Vapor

/// One metric card on the overview dashboard: a labelled count with an optional sub-line link
/// (e.g. a catalog type's most recently added record). `ok` is false when the card's source
/// could not be reached; the template renders a dash and an "unavailable" note instead of the
/// count.
struct MetricCardVM: Content {
  let ok: Bool
  /// Locale-grouped count string ("2,265"), or "0". Not shown when `ok` is false.
  let countText: String
  let hasLink: Bool
  let linkURL: String
  let linkText: String

  static let failed = MetricCardVM(
    ok: false, countText: "0", hasLink: false, linkURL: "", linkText: "")

  static func count(_ n: Int) -> MetricCardVM {
    MetricCardVM(ok: true, countText: Self.format(n), hasLink: false, linkURL: "", linkText: "")
  }

  static func count(_ n: Int, linkText: String, linkURL: String) -> MetricCardVM {
    let hasLink = !linkText.isEmpty && n > 0
    return MetricCardVM(
      ok: true, countText: Self.format(n), hasLink: hasLink,
      linkURL: hasLink ? linkURL : "", linkText: hasLink ? linkText : "")
  }

  private static let formatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    return f
  }()

  private static func format(_ n: Int) -> String {
    n >= 1000 ? (formatter.string(from: NSNumber(value: n)) ?? String(n)) : String(n)
  }
}

/// The five catalog-entity cards, from `catalog-api`'s `GET /stats`. All five degrade together
/// (one source); the game-system card is separate.
struct CatalogCardsVM: Content {
  let volumes: MetricCardVM
  let publishers: MetricCardVM
  let studios: MetricCardVM
  let persons: MetricCardVM
  let licenses: MetricCardVM

  static let failed = CatalogCardsVM(
    volumes: .failed, publishers: .failed, studios: .failed, persons: .failed, licenses: .failed)

  static func from(_ result: Result<CatalogStats, Error>, detailURLBase: String) -> CatalogCardsVM {
    guard case .success(let s) = result else { return .failed }
    func card(_ t: CatalogTypeStats, _ path: String) -> MetricCardVM {
      .count(
        t.count, linkText: t.mostRecent?.name ?? "",
        linkURL: t.mostRecent.map { "\(detailURLBase)catalog/\(path)/\($0.id)" } ?? "")
    }
    return CatalogCardsVM(
      volumes: card(s.volumes, "volumes"),
      publishers: card(s.publishers, "publishers"),
      studios: card(s.studios, "studios"),
      persons: card(s.persons, "persons"),
      licenses: card(s.licenses, "licenses"))
  }
}

struct MetricsPageContext: Content {
  // Catalog & game systems row (6 cards)
  let catalog: CatalogCardsVM
  let gameSystems: MetricCardVM
  // Users row (3 cards)
  let totalUsers: MetricCardVM
  let activeUsers: MetricCardVM
  let newUsers: MetricCardVM
  // Operations row (3 cards)
  let activeBanners: MetricCardVM
  let activeMaintenance: MetricCardVM
  let userIssues: MetricCardVM

  let user: LeafUser?
  let meta: PageMeta
}
