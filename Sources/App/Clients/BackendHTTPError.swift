import Vapor

/// A backend that answered, but not with success. Distinct from an unreachable backend (a
/// transport error or timeout, which never produces a response), so pages can say "refused"
/// instead of "could not be reached" and keep the real cause visible.
struct BackendHTTPError: AbortError, CustomStringConvertible {
  let backend: String
  let status: HTTPResponseStatus
  /// The backend's `message` field, when its error body has one.
  let message: String?

  var reason: String {
    let base = "\(backend) request failed with status \(status.code)"
    return message.map { "\(base): \($0)" } ?? base
  }

  var description: String { reason }

  /// Throws unless `response` is 2xx. Reads `{"message": ...}` from the body when present.
  static func check(_ response: ClientResponse, backend: String) throws {
    guard !(200..<300).contains(response.status.code) else { return }
    struct Body: Decodable { let message: String? }
    let message = (try? response.content.decode(Body.self))?.message
    throw BackendHTTPError(backend: backend, status: response.status, message: message)
  }

  /// The backend's message trimmed to a length safe to show on a page. Leaf escapes it on output.
  var displayMessage: String? {
    guard let message, !message.isEmpty else { return nil }
    return message.count > 200 ? String(message.prefix(200)) + "..." : message
  }
}
