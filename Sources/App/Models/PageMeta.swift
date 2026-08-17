import Vapor

/// Bundles the per-request values every page's template needs regardless of what the page is
/// actually about - the path prefix for internal links (see AppPaths.swift) and the build
/// version/date/hash shown in the footer.
struct PageMeta: Content {
  let basePath: String
  let rootURL: String
  let sharedURL: String
  let buildVersion: String
  let buildDate: String
  /// First 8 chars of the build sha - matches catalog-web's `PageMeta.buildHash` and
  /// main-web's own convention, rather than dumping the full 40-char sha in the footer.
  let buildHash: String
  /// `auth-web`'s login/logout links, each with `return_to` set to this request's own full path
  /// (including `basePath`). `auth-web` sits at `/auth` on the same host root, not under this
  /// app's own `basePath` - see design.md's "auth-web is the sole owner of the Authorization
  /// Code exchange" decision.
  let loginURL: String
  let logoutURL: String
  /// Fixed path on the shared `dev.sweetrpg.com` host, matching catalog-web's/main-web's own
  /// avatar menu convention (`suite-avatar-menu` OpenSpec change) - 404s until `users-web`
  /// ships, a separate, already-tracked gap. No `adminURL` here unlike those two: this app *is*
  /// admin-web, so an "Administration" item linking to itself would be redundant - every
  /// visitor who reaches it already cleared `AuthRequiredMiddleware`'s `admin` role check.
  let userSettingsURL: String

  init(_ req: Request) {
    self.basePath = req.basePath
    self.rootURL = req.rootURL
    self.sharedURL = req.sharedURL
    self.buildVersion = req.buildInfo.version
    self.buildDate = req.buildInfo.date
    self.buildHash = String(req.buildInfo.sha.prefix(8))
    let returnTo = "\(req.basePath)\(req.url.path)"
    let encodedReturnTo =
      returnTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/"
    self.loginURL = "/auth/login?return_to=\(encodedReturnTo)"
    self.logoutURL = "/auth/logout?return_to=\(encodedReturnTo)"
    self.userSettingsURL = "/users"
  }
}
