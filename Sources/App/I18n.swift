import Foundation
import Vapor

/// Loads the flat dotted-key locale tables from `Resources/Localizations/<code>.json` at
/// startup and resolves each request's locale: `locale` cookie override, then the first tag of
/// the `Accept-Language` header's base subtag, then English. Templates read translations via
/// `#(meta.l10n.<key>)` (see `PageMeta.l10n`). Part of the platform-wide localization contract -
/// see sweetrpg/platform OpenSpec change `full-localization-web-apps`.
enum I18n {
  nonisolated(unsafe) static var tables: [String: [String: String]] = [:]
  static let defaultLocale = "en"

  static func loadTables() throws {
    let dir = URL(fileURLWithPath: "Resources/Localizations")
    let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
    var loaded: [String: [String: String]] = [:]
    for url in urls {
      let data = try Data(contentsOf: url)
      var table = try JSONDecoder().decode([String: String].self, from: data)
      // Leaf resolves each `.` in `#(meta.l10n.foo_bar)` as a dictionary-subscript hop, so
      // dotted JSON keys get underscore aliases for template lookups.
      for (key, value) in table where key.contains(".") {
        table[key.replacingOccurrences(of: ".", with: "_")] = value
      }
      loaded[url.deletingPathExtension().lastPathComponent] = table
    }
    tables = loaded
  }

  static func resolveLocale(for request: Request) -> String {
    if let cookie = request.cookies["locale"]?.string, tables[cookie] != nil {
      return cookie
    }
    if let header = request.headers.first(name: .acceptLanguage) {
      let tag = header.split(separator: ",").first.map(String.init) ?? ""
      let stripped = tag.split(separator: ";").first.map(String.init) ?? ""
      let base = stripped.split(separator: "-").first.map(String.init) ?? ""
      if !base.isEmpty, tables[base] != nil {
        return base
      }
    }
    return defaultLocale
  }

  static func table(for request: Request) -> [String: String] {
    tables[resolveLocale(for: request)] ?? [:]
  }
}

extension Request {
  /// The resolved locale table for this request - used by `PageMeta` so every Leaf template can
  /// interpolate translated strings as `#(meta.l10n.<key>)`.
  var l10n: [String: String] {
    I18n.table(for: self)
  }
}
