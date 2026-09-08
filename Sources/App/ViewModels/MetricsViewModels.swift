import Foundation
import Vapor

/// One metric card on the overview dashboard: a labelled count, optionally linking through to a
/// browse/detail page. `ok` is false when the card's source could not be reached; the template
/// renders a dash and an "unavailable" note instead of the count.
struct MetricCardVM: Content {
  let ok: Bool
  /// Locale-grouped count string ("2,265"), or "0". Not shown when `ok` is false.
  let countText: String
  /// Destination for the whole-card link, or "" for a card that isn't linked.
  let href: String

  static let failed = MetricCardVM(ok: false, countText: "0", href: "")

  static func count(_ n: Int, href: String = "") -> MetricCardVM {
    MetricCardVM(ok: true, countText: Self.format(n), href: href)
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
/// (one source); the game-system card is separate. Each links to its browse page on the public
/// catalog site.
struct CatalogCardsVM: Content {
  let volumes: MetricCardVM
  let publishers: MetricCardVM
  let studios: MetricCardVM
  let persons: MetricCardVM
  let licenses: MetricCardVM

  static let failed = CatalogCardsVM(
    volumes: .failed, publishers: .failed, studios: .failed, persons: .failed, licenses: .failed)

  /// - Parameter catalogURLBase: `Request.rootURL` (the platform root, trailing slash).
  static func from(_ result: Result<CatalogStats, Error>, catalogURLBase: String) -> CatalogCardsVM
  {
    guard case .success(let s) = result else { return .failed }
    func card(_ t: CatalogTypeStats, _ path: String) -> MetricCardVM {
      .count(t.count, href: "\(catalogURLBase)catalog/\(path)")
    }
    return CatalogCardsVM(
      // Volumes browse lives at /catalog/browse; the other types at /catalog/<type>.
      volumes: card(s.volumes, "browse"),
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
  // Users row (3 cards) + the 30-day history chart
  let totalUsers: MetricCardVM
  let activeUsers: MetricCardVM
  let newUsers: MetricCardVM
  /// `[UserHistoryPoint]` as a JSON string for the chart's inline data block. "[]" when the
  /// history endpoint was unavailable - the chart script then renders an empty-state note.
  let userHistoryJSON: String
  // Operations row (3 cards)
  let activeBanners: MetricCardVM
  let activeMaintenance: MetricCardVM
  let userIssues: MetricCardVM

  let user: LeafUser?
  let meta: PageMeta
}
