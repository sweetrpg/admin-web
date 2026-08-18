import Foundation
import Tracing
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
///
/// Every *mutating* call presents the acting user's own Auth0 access token as an `Authorization`
/// bearer, matching `admin-api`'s `WriteAuth` middleware contract - `admin-api` verifies it and
/// checks the user's role itself, rather than trusting this app's identity. `GET /banners` needs
/// no credential, same scoping as `admin-api`'s own read/write split.
struct AdminAPIClient {
  let client: Client
  let baseURL: String

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.adminAPIConfig.baseURL
  }

  private static let scopesForListing = ["platform"]

  func listAll() async throws -> [Banner] {
    try await withSpan("client-list-all-banners") { _ in
      var uri = URI(string: baseURL + "/banners")
      var query = Self.scopesForListing.map { "scope=\($0)" }
      query.append("include_inactive=true")
      uri.query = query.joined(separator: "&")
      let response = try await client.get(uri)
      try Self.throwOnFailure(response)
      return try response.content.decode([Banner].self)
    }
  }

  /// admin-api's `POST /banners` requires `created_by` in the body (`createBannerRequest`,
  /// `binding:"required"`) - `BannerInput` deliberately has no such field (it's also the
  /// `PUT` payload shape, which admin-api's `updateBannerRequest` does not accept `created_by`
  /// on, since it's immutable once set). Wrapping `input`'s fields plus `createdBy` here, rather
  /// than adding an unused field to `BannerInput` for every other caller, keeps the create-only
  /// requirement local to the one call site that actually needs it.
  private struct CreateBannerRequestBody: Content {
    var scopeType: BannerScopeType
    var scopeValue: String
    var severity: BannerSeverity
    var message: String
    var startsAt: Date?
    var expiresAt: Date
    var createdBy: String

    enum CodingKeys: String, CodingKey {
      case scopeType = "scope_type"
      case scopeValue = "scope_value"
      case severity
      case message
      case startsAt = "starts_at"
      case expiresAt = "expires_at"
      case createdBy = "created_by"
    }
  }

  func create(_ input: BannerInput, actingUserSub: String, accessToken: String) async throws
    -> Banner
  {
    try await withSpan("client-create-banner") { _ in
      let body = CreateBannerRequestBody(
        scopeType: input.scopeType,
        scopeValue: input.scopeValue,
        severity: input.severity,
        message: input.message,
        startsAt: input.startsAt,
        expiresAt: input.expiresAt,
        createdBy: actingUserSub
      )
      let response = try await post(
        URI(string: baseURL + "/banners"), accessToken: accessToken
      ) { req in
        try req.content.encode(body)
      }
      try Self.throwOnFailure(response)
      return try response.content.decode(Banner.self)
    }
  }

  func update(id: String, _ input: BannerInput, accessToken: String) async throws -> Banner {
    try await withSpan("client-update-banner") { _ in
      let response = try await put(
        URI(string: baseURL + "/banners/\(id)"), accessToken: accessToken
      ) { req in
        try req.content.encode(input)
      }
      try Self.throwOnFailure(response)
      return try response.content.decode(Banner.self)
    }
  }

  /// Expires a banner immediately by setting `expires_at` to now, per the admin spec's
  /// "Expire or delete a banner immediately" requirement - not a separate admin-api endpoint,
  /// just a PUT with the field set to the current time.
  func expireNow(_ banner: Banner, accessToken: String) async throws -> Banner {
    try await withSpan("client-expire-now") { _ in
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
        accessToken: accessToken)
    }
  }

  func delete(id: String, accessToken: String) async throws {
    try await withSpan("client-delete-banner") { _ in
      let response = try await delete(
        URI(string: baseURL + "/banners/\(id)"), accessToken: accessToken)
      try Self.throwOnFailure(response)
    }
  }

  // MARK: - Request helpers

  private func post(
    _ uri: URI, accessToken: String,
    beforeSend: @escaping (inout ClientRequest) throws -> Void = { _ in }
  )
    async throws -> ClientResponse
  {
    try await client.post(uri) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      try beforeSend(&req)
    }
  }

  private func put(
    _ uri: URI, accessToken: String,
    beforeSend: @escaping (inout ClientRequest) throws -> Void = { _ in }
  )
    async throws -> ClientResponse
  {
    try await client.put(uri) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
      try beforeSend(&req)
    }
  }

  private func delete(_ uri: URI, accessToken: String) async throws -> ClientResponse {
    try await client.delete(uri) { req in
      req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
    }
  }

  private static func throwOnFailure(_ response: ClientResponse) throws {
    guard (200..<300).contains(response.status.code) else {
      throw Abort(
        response.status, reason: "admin-api request failed with status \(response.status.code)")
    }
  }

  // MARK: - Maintenance modes

  /// `GET /maintenance-modes` returns every record regardless of scope or enabled state -
  /// unlike banners, this has a documented admin-listing shape from the start (see
  /// `server/maintenance_modes.go` in admin-api), no `include_inactive` workaround needed.
  func listAllMaintenanceModes() async throws -> [MaintenanceMode] {
    try await withSpan("client-list-all-maintenance-modes") { _ in
      let response = try await client.get(URI(string: baseURL + "/maintenance-modes"))
      try Self.throwOnFailure(response)
      return try response.content.decode([MaintenanceMode].self)
    }
  }

  /// Creates a record for `input`'s scope, or updates the existing record for that scope in
  /// place if one already exists - admin-api enforces at most one record per scope.
  func upsertMaintenanceMode(_ input: MaintenanceModeInput, accessToken: String) async throws
    -> MaintenanceMode
  {
    try await withSpan("client-upsert-maintenance-mode") { _ in
      let response = try await post(
        URI(string: baseURL + "/maintenance-modes"), accessToken: accessToken
      ) { req in
        try req.content.encode(input)
      }
      try Self.throwOnFailure(response)
      return try response.content.decode(MaintenanceMode.self)
    }
  }

  func updateMaintenanceMode(
    id: String, _ input: MaintenanceModeInput, accessToken: String
  ) async throws -> MaintenanceMode {
    try await withSpan("client-update-maintenance-mode") { _ in
      let response = try await put(
        URI(string: baseURL + "/maintenance-modes/\(id)"), accessToken: accessToken
      ) { req in
        try req.content.encode(input)
      }
      try Self.throwOnFailure(response)
      return try response.content.decode(MaintenanceMode.self)
    }
  }

  /// Flips `enabled` without touching the rest of the record - the "direct enable/disable
  /// toggle" from tasks.md 2.4, so an admin doesn't have to open the full edit form just to
  /// flip the gate.
  func setMaintenanceModeEnabled(
    _ mode: MaintenanceMode, enabled: Bool, accessToken: String
  ) async throws -> MaintenanceMode {
    try await withSpan("client-set-maintenance-mode-enabled") { _ in
      try await updateMaintenanceMode(
        id: mode.id,
        MaintenanceModeInput(
          scopeType: mode.scopeType,
          scopeValue: mode.scopeValue,
          enabled: enabled,
          startsAt: mode.startsAt,
          endsAt: mode.endsAt,
          label: mode.label,
          description: mode.description
        ),
        accessToken: accessToken)
    }
  }

  func deleteMaintenanceMode(id: String, accessToken: String) async throws {
    try await withSpan("client-delete-maintenance-mode") { _ in
      let response = try await delete(
        URI(string: baseURL + "/maintenance-modes/\(id)"), accessToken: accessToken)
      try Self.throwOnFailure(response)
    }
  }
}

extension Request {
  var adminAPI: AdminAPIClient { AdminAPIClient(request: self) }
}
