import Vapor

/// Gates every route behind a valid Auth0 session, per the banner-message-admin spec's
/// "Authenticated access only" requirement: an unauthenticated visitor is redirected to Auth0
/// login before seeing any banner data or management UI, with no per-page opt-in required. This
/// is a blanket allowlist-of-exceptions middleware rather than per-route auth, since this app has
/// no page that's meant to be reachable without a session - the exceptions below are
/// infrastructure endpoints and the login flow itself, not content pages.
///
/// Trust boundary (per design.md): any authenticated user in the Auth0 tenant can manage
/// banners - there is no role check here. Narrowing that to a specific role/permission is
/// explicitly out of scope for this iteration.
struct AuthRequiredMiddleware: AsyncMiddleware {
  private static let unauthenticatedPaths: Set<String> = [
    "/status/ping",
    "/login",
    "/auth/login",
    "/auth/callback",
  ]

  func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
    let path = request.url.path
    if Self.unauthenticatedPaths.contains(path) || path.hasPrefix("/public/") {
      return try await next.respond(to: request)
    }
    guard request.currentUser != nil else {
      return request.redirectLocal(to: "/login")
    }
    return try await next.respond(to: request)
  }
}
