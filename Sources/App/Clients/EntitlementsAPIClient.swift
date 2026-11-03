import Foundation
import Tracing
import Vapor

/// Thin client for `entitlements-api`'s admin routes. Forwards the acting admin's own access
/// token; the service verifies the admin role itself. Holds no state.
struct EntitlementsAPIClient: EntitlementsServing {
  let client: Client
  let baseURL: String

  init(request: Request) {
    self.client = request.client
    self.baseURL = request.application.entitlementsAPIConfig?.baseURL ?? ""
  }

  private struct ErrorBody: Decodable {
    let error: String?
    let message: String?
  }

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  private func uri(_ path: String) -> URI {
    URI(string: baseURL + "/admin" + path)
  }

  private func segment(_ raw: String) -> String {
    raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
  }

  func read(userID: String, accessToken: String) async throws -> [EntitlementRecord] {
    try await withSpan("client-entitlements-read") { _ in
      let response = try await send(.GET, "/users/\(segment(userID))/entitlements", accessToken)
      return try Self.decode([EntitlementRecord].self, from: response)
    }
  }

  func recentAudit(userID: String, accessToken: String) async throws -> [AuditEntry] {
    try await withSpan("client-entitlements-audit") { _ in
      let response = try await send(
        .GET, "/users/\(segment(userID))/audit?limit=20", accessToken)
      return try Self.decode([AuditEntry].self, from: response)
    }
  }

  private struct SetBody: Encodable {
    let value: EntitlementValue
    let validUntil: String?
    let reason: String
    let acknowledgePaidReduction: Bool?
    let reference: String?
  }

  func setOverride(
    userID: String, key: String, request: OverrideRequest, accessToken: String
  ) async throws {
    try await withSpan("client-entitlements-set-override") { _ in
      let acknowledged = request.paidReductionReference != nil
      let body = SetBody(
        value: request.value, validUntil: request.validUntil, reason: request.reason,
        acknowledgePaidReduction: acknowledged ? true : nil,
        reference: request.paidReductionReference)
      _ = try await send(
        .PUT, "/users/\(segment(userID))/overrides/\(segment(key))", accessToken, body: body)
    }
  }

  func removeOverride(
    userID: String, key: String, reason: String, accessToken: String
  ) async throws {
    try await withSpan("client-entitlements-remove-override") { _ in
      _ = try await send(
        .DELETE, "/users/\(segment(userID))/overrides/\(segment(key))", accessToken,
        body: ["reason": reason])
    }
  }

  private func send(
    _ method: HTTPMethod, _ path: String, _ accessToken: String, body: (any Encodable)? = nil
  ) async throws -> ClientResponse {
    let response: ClientResponse
    do {
      response = try await client.send(method, headers: [:], to: uri(path)) { req in
        req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
        if let body {
          req.headers.contentType = .json
          req.body = ByteBuffer(data: try Self.encoder.encode(AnyEncodable(body)))
        }
      }
    } catch {
      throw EntitlementsError.unavailable
    }
    if (200..<300).contains(response.status.code) { return response }
    throw Self.error(for: response)
  }

  /// Maps the service's error responses. A 409 that carries a paid-reduction body becomes the
  /// typed acknowledgment error so the page can show the service's own figures.
  static func error(for response: ClientResponse) -> EntitlementsError {
    switch response.status.code {
    case 401: return .unauthorized
    case 403:
      let body = try? response.content.decode(ErrorBody.self)
      return body?.error == "paid_reductions_disabled" ? .paidReductionsDisabled : .forbidden
    case 404: return .notFound
    case 400:
      let body = try? response.content.decode(ErrorBody.self)
      return .validation(body?.message ?? "invalid request")
    case 409:
      if let detail = try? decode(PaidReductionDetail.self, from: response) {
        return .acknowledgmentRequired(detail)
      }
      let body = try? response.content.decode(ErrorBody.self)
      return .validation(body?.message ?? "conflict")
    default: return .unavailable
    }
  }

  private static func decode<T: Decodable>(_ type: T.Type, from response: ClientResponse) throws
    -> T
  {
    guard let buffer = response.body else { throw EntitlementsError.unavailable }
    do {
      return try decoder.decode(T.self, from: Data(buffer.readableBytesView))
    } catch {
      throw EntitlementsError.unavailable
    }
  }
}

private struct AnyEncodable: Encodable {
  let wrapped: any Encodable
  init(_ wrapped: any Encodable) { self.wrapped = wrapped }
  func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}
