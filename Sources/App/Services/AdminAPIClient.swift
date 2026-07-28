import Foundation
import Vapor

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
struct AdminAPIClient {
  let client: Client
  let baseURL: String

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.adminAPIConfig.baseURL
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

  func create(_ input: BannerInput) async throws -> Banner {
    let response = try await client.post(URI(string: baseURL + "/banners")) { req in
      try req.content.encode(input)
    }
    try Self.throwOnFailure(response)
    return try response.content.decode(Banner.self)
  }

  func update(id: String, _ input: BannerInput) async throws -> Banner {
    let response = try await client.put(URI(string: baseURL + "/banners/\(id)")) { req in
      try req.content.encode(input)
    }
    try Self.throwOnFailure(response)
    return try response.content.decode(Banner.self)
  }

  /// Expires a banner immediately by setting `expires_at` to now, per the admin spec's
  /// "Expire or delete a banner immediately" requirement - not a separate admin-api endpoint,
  /// just a PUT with the field set to the current time.
  func expireNow(_ banner: Banner) async throws -> Banner {
    try await update(
      id: banner.id,
      BannerInput(
        scopeType: banner.scopeType,
        scopeValue: banner.scopeValue,
        severity: banner.severity,
        message: banner.message,
        startsAt: banner.startsAt,
        expiresAt: Date()
      ))
  }

  func delete(id: String) async throws {
    let response = try await client.delete(URI(string: baseURL + "/banners/\(id)"))
    try Self.throwOnFailure(response)
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
