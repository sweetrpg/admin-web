import Tracing
import Vapor

/// Gates every route behind a session that carries the `admin` role, per this change's revised
/// trust boundary (see design.md's "Admin UI lives in admin-web" decision in platform's
/// add-user-api-authn-authz change): being logged in elsewhere in the suite is not enough on its
/// own, since this app now also hosts the role/service-access management UI, not just banner
/// management. This is a blanket allowlist-of-exceptions middleware rather than per-route auth,
/// since this app has no page meant to be reachable by a non-admin - the exceptions below are
/// infrastructure endpoints only, not content pages.
///
/// The `admin` role comes from the shared session's `roles` field, which `users-api` verified
/// (via `/authz/check`) once at login time in `auth-web` - this app trusts that verification
/// rather than re-checking, since it never holds a bearer token of its own to present to
/// `/authz/check` (it never talks to Auth0 or `users-api` directly). The trade-off: a role
/// revoked after login stays in effect until the session naturally expires or the user logs out
/// and back in - there's no live per-request re-check. Re-verifying live would need `auth-web`
/// to also store a raw access token in the shared session, which is a bigger exposure (a live
/// credential visible to every reading frontend) than this trade-off is worth.
struct AuthRequiredMiddleware: AsyncMiddleware {
  private static let unauthenticatedPaths: Set<String> = [
    "/status/ping"
  ]

  func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
    try await withSpan("auth-required-middleware") { _ in
      let path = request.url.path
      if Self.unauthenticatedPaths.contains(path) || path.hasPrefix("/public/") {
        return try await next.respond(to: request)
      }

      guard let user = await request.currentUser else {
        let returnTo = "\(request.basePath)\(path)"
        let encodedReturnTo =
          returnTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/"
        return request.redirect(to: "/auth/login?return_to=\(encodedReturnTo)")
      }
      guard user.roles.contains("admin") else {
        throw Abort(.forbidden, reason: "Your account does not have access to this page.")
      }
      return try await next.respond(to: request)
    }
  }
}
