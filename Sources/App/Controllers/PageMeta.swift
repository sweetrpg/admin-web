import Vapor

/// Bundles the per-request values every page's template needs regardless of what the page is
/// actually about - the path prefix for internal links (see AppPaths.swift) and the build
/// version/date shown in the footer.
struct PageMeta: Content {
  let basePath: String
  let rootURL: String
  let sharedAssetsURL: String
  let buildVersion: String
  let buildDate: String
  /// `auth-web`'s login link, with `return_to` set to this request's own full path (including
  /// `basePath`). `auth-web` sits at `/auth` on the same host root, not under this app's own
  /// `basePath` - see design.md's "auth-web is the sole owner of the Authorization Code
  /// exchange" decision.
  let loginURL: String
  let logoutURL: String

  init(_ req: Request) {
    self.basePath = req.basePath
    self.rootURL = req.rootURL
    self.sharedAssetsURL = req.sharedAssetsURL
    self.buildVersion = req.buildInfo.version
    self.buildDate = req.buildInfo.date
    let returnTo = "\(req.basePath)\(req.url.path)"
    let encodedReturnTo =
      returnTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/"
    self.loginURL = "/auth/login?return_to=\(encodedReturnTo)"
    self.logoutURL = "/auth/logout"
  }
}
