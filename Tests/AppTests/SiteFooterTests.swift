import Foundation
import Testing
import VaporTesting

@testable import App

private struct FooterContext: Content {
  let meta: PageMeta
}

private func renderFooter() async throws -> String {
  var html = ""
  try await withApp { app in
    try I18n.loadTables()
    app.views.use(.leaf)
    app.get("test-footer") { req async throws -> View in
      try await req.view.render("partials/footer", FooterContext(meta: PageMeta(req)))
    }
    try await app.testing().test(.GET, "test-footer") { res in
      #expect(res.status == .ok)
      html = res.body.string
    }
  }
  return html
}

@Suite("Standard site footer", .serialized)
struct SiteFooterTests {
  @Test("renders the three lines in order, the last also marked as the build line")
  func threeLinesInOrder() async throws {
    let html = try await renderFooter()
    let copyright = try #require(html.range(of: "Pilgrimage Software"))
    let terms = try #require(html.range(of: "Terms of Service"))
    let build = try #require(html.range(of: "footer-line footer-build"))
    #expect(copyright.lowerBound < terms.lowerBound && terms.lowerBound < build.lowerBound)
    #expect(html.components(separatedBy: "class=\"footer-line").count - 1 == 3)
    #expect(html.contains("Privacy Policy") && html.contains("Support"))
    #expect(html.contains("built unknown / unset"))
  }

  @Test("the copyright shows the current year, not a literal")
  func currentYear() async throws {
    let html = try await renderFooter()
    let year = Calendar(identifier: .gregorian).component(.year, from: Date())
    #expect(html.contains("&copy; \(year) Pilgrimage Software"))
  }

  @Test("legal links come from the root URL and never include the app's path prefix")
  func linksIgnorePrefix() async throws {
    var html = ""
    var meta: PageMeta?
    try await withApp { app in
      try I18n.loadTables()
      app.views.use(.leaf)
      app.get("test-footer") { req async throws -> View in
        let page = PageMeta(req)
        meta = page
        return try await req.view.render("partials/footer", FooterContext(meta: page))
      }
      try await app.testing().test(.GET, "test-footer") { html = $0.body.string }
    }
    let page = try #require(meta)
    let root = page.rootURL.hasSuffix("/") ? page.rootURL : page.rootURL + "/"
    #expect(page.footer.termsURL == root + "terms")
    #expect(html.contains("href=\"\(root)terms\""))
    #expect(html.contains("href=\"\(root)privacy\""))
    #expect(html.contains("href=\"\(root)support\""))
    if !page.basePath.isEmpty { #expect(!html.contains("\(page.basePath)/terms")) }
  }

  @Test("links resolve from the root URL setting, with or without a trailing slash")
  func rootURLSetting() {
    let withSlash = FooterMeta(rootURL: "https://dev.sweetrpg.com/", version: "0.1.0")
    let without = FooterMeta(rootURL: "https://dev.sweetrpg.com", version: "0.1.0")
    #expect(withSlash.termsURL == "https://dev.sweetrpg.com/terms")
    #expect(without.supportURL == "https://dev.sweetrpg.com/support")
  }

  @Test("release versions get a v prefix; dev is left alone")
  func versionLabel() {
    #expect(FooterMeta(rootURL: "/", version: "0.28.0").versionLabel == "v0.28.0")
    #expect(FooterMeta(rootURL: "/", version: "dev").versionLabel == "dev")
  }
}
