import Foundation
import Vapor

/// Matches `WriteAuth`'s expectation in `admin-api` exactly - the two repos are separate Swift/Go
/// packages, so this can't be a shared import, only a matched string constant. See
/// `UsersAPIClient.swift` for the identical pattern against `users-api`.
private let internalServiceTokenHeaderName = "X-Internal-Service-Token"

/// Matches `middleware.WriteAuth`'s expectation exactly - the acting admin's Auth0 `sub`,
/// required on every mutating call so `admin-api` can attribute its audit log entry. `admin-api`
/// fails the request closed if this is missing or empty; see that repo's
/// `server/middleware/writeauth.go` and `models/audit.go`.
private let actingUserSubHeaderName = "X-Acting-User-Sub"

/// Thin client for admin-api's `/banners` CRUD surface.
///
/// OPEN QUESTION (see this repo's README "Known gaps" section and the OpenSpec change's task
/// list): `specs/banner-messages/spec.md` only documents `GET /banners` as a *scoped, active-only*
/// query ("returns active banners only, ordered by severity" - tasks.md 3.2) - there is no
/// documented admin listing endpoint that returns every banner (including expired/future-dated
/// ones) for management purposes, which is what the banner-message-admin spec's "List and filter
/// existing banners" requirement needs. `listAll()` below calls `GET /banners` with an
/// `include_inactive=true` query parameter as a best-guess extension of the documented contract -
/// admin-api does not yet implement this parameter as of this writing. Until admin-api's team
/// confirms (or implements) an actual admin-listing shape, this call will silently behave like
/// the scoped/active-only query and the list view will only show currently-active banners, not
/// the full set the spec calls for. Don't build further UI assuming this parameter works without
/// confirming against a real admin-api deployment first.
///
/// Every *mutating* call presents `X-Internal-Service-Token` and `X-Acting-User-Sub`, matching
/// `admin-api`'s `WriteAuth` middleware contract - `GET /banners` needs neither, same scoping as
/// `admin-api`'s own read/write split. See `AdminAPIConfig.swift`.
struct AdminAPIClient {
  let client: Client
  let baseURL: String
  let internalServiceToken: String?

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.adminAPIConfig.baseURL
    self.internalServiceToken = request.adminAPIConfig.internalServiceToken
  }

  private static let scopesForListing = ["platform"]

  func listAll() async throws -> [Banner] {
    var uri = URI(string: baseURL + "/banners")
    var query = Self.scopesForListing.map { "scope=\($0)" }
    query.append("include_inactive=true")
    uri.query = query.joined(separator: "&")
    let response = try await client.get(uri)
    try Self.throwOnFailure(response)
    return try response.content.decode([Banner].self)
  }

  func create(_ input: BannerInput, actingUserSub: String) async throws -> Banner {
    let response = try await post(
      URI(string: baseURL + "/banners"), actingUserSub: actingUserSub
    ) { req in
      try req.content.encode(input)
    }
    try Self.throwOnFailure(response)
    return try response.content.decode(Banner.self)
  }

  func update(id: String, _ input: BannerInput, actingUserSub: String) async throws -> Banner {
    let response = try await put(
      URI(string: baseURL + "/banners/\(id)"), actingUserSub: actingUserSub
    ) { req in
      try req.content.encode(input)
    }
    try Self.throwOnFailure(response)
    return try response.content.decode(Banner.self)
  }

  /// Expires a banner immediately by setting `expires_at` to now, per the admin spec's
  /// "Expire or delete a banner immediately" requirement - not a separate admin-api endpoint,
  /// just a PUT with the field set to the current time.
  func expireNow(_ banner: Banner, actingUserSub: String) async throws -> Banner {
    try await update(
      id: banner.id,
      BannerInput(
        scopeType: banner.scopeType,
        scopeValue: banner.scopeValue,
        severity: banner.severity,
        message: banner.message,
        startsAt: banner.startsAt,
        expiresAt: Date()
      ),
      actingUserSub: actingUserSub)
  }

  func delete(id: String, actingUserSub: String) async throws {
    let response = try await delete(
      URI(string: baseURL + "/banners/\(id)"), actingUserSub: actingUserSub)
    try Self.throwOnFailure(response)
  }

  // MARK: - Request helpers

  /// Fails closed when `ADMIN_API_INTERNAL_SERVICE_TOKEN` is unset, rather than sending an
  /// unauthenticated request `admin-api` would reject anyway - a clearer error for whoever's
  /// debugging a missing-config deployment than a generic 401 from the other service.
  private func requireToken() throws -> String {
    guard let token = internalServiceToken else {
      throw Abort(
        .internalServerError,
        reason: "ADMIN_API_INTERNAL_SERVICE_TOKEN is not configured")
    }
    return token
  }

  private func post(
    _ uri: URI, actingUserSub: String,
    beforeSend: @escaping (inout ClientRequest) throws -> Void = { _ in }
  )
    async throws -> ClientResponse
  {
    let token = try requireToken()
    return try await client.post(uri) { req in
      req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
      req.headers.replaceOrAdd(name: actingUserSubHeaderName, value: actingUserSub)
      try beforeSend(&req)
    }
  }

  private func put(
    _ uri: URI, actingUserSub: String,
    beforeSend: @escaping (inout ClientRequest) throws -> Void = { _ in }
  )
    async throws -> ClientResponse
  {
    let token = try requireToken()
    return try await client.put(uri) { req in
      req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
      req.headers.replaceOrAdd(name: actingUserSubHeaderName, value: actingUserSub)
      try beforeSend(&req)
    }
  }

  private func delete(_ uri: URI, actingUserSub: String) async throws -> ClientResponse {
    let token = try requireToken()
    return try await client.delete(uri) { req in
      req.headers.replaceOrAdd(name: internalServiceTokenHeaderName, value: token)
      req.headers.replaceOrAdd(name: actingUserSubHeaderName, value: actingUserSub)
    }
  }

  private static func throwOnFailure(_ response: ClientResponse) throws {
    guard (200..<300).contains(response.status.code) else {
      throw Abort(
        response.status, reason: "admin-api request failed with status \(response.status.code)")
    }
  }
}

extension Request {
  var adminAPI: AdminAPIClient { AdminAPIClient(request: self) }
}
