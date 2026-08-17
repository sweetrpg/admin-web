import Vapor

// MARK: - Leaf view models

/// Powers the shared avatar-menu partial (`suite-avatar-menu` OpenSpec change) - same field
/// shape as catalog-web's own `LeafUser`, minus `isAdmin`: this app has no self-referential
/// "Administration" item (see `PageMeta`'s doc comment).
struct LeafUser: Content {
  let name: String
  /// Shown as a smaller, muted subtitle line under `name` in the avatar menu. `nil` when the
  /// session has no email (same source as `avatarGravatarURL` below).
  let email: String?
  /// First character of `name`, uppercased - the avatar trigger's fallback label.
  let avatarInitial: String
  /// Gravatar image URL derived from the session's email (`d=404` so a visitor with no
  /// Gravatar gets a real 404 rather than Gravatar's generic mystery-person image) - the
  /// shared avatar-menu markup's `onerror` falls back to `avatarInitial` on load failure.
  /// `nil` when the session has no email.
  let avatarGravatarURL: String?

  init(_ user: SessionUser) {
    self.name = user.name
    self.email = user.email
    self.avatarInitial = user.name.first.map { String($0).uppercased() } ?? ""
    self.avatarGravatarURL = user.email.map { email in
      let canonical = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let hash = Insecure.MD5.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
      return "https://www.gravatar.com/avatar/\(hash)?s=64&d=404"
    }
  }
}

struct LeafBanner: Content {
  let id: String
  let scopeLabel: String
  let severity: String
  let message: String
  let status: String
  let expiresAtLabel: String

  init(_ banner: Banner) {
    self.id = banner.id
    self.scopeLabel =
      banner.scopeType == .platform
      ? "platform" : "\(banner.scopeType.rawValue):\(banner.scopeValue)"
    self.severity = banner.severity.rawValue
    self.message = banner.message
    self.status = banner.status().rawValue
    self.expiresAtLabel = ISO8601DateFormatter().string(from: banner.expiresAt)
  }
}

/// Flattened, always-present form field values - defaults resolved here in Swift (`??`) rather
/// than in the Leaf template, since the pinned leaf-kit 1.14.3 lexes `??` but never implemented
/// it (`ParameterResolver.resolve` throws `.unknownError("Future feature")` for
/// `.nilCoalesce`), which made `banners/form.leaf`'s prior `banner?.field ?? ""` usage 500 on
/// every render, edit and new alike.
struct LeafBannerForm: Content {
  let id: String
  let scopeType: String
  let scopeValue: String
  let severity: String
  let message: String
  let startsAt: String
  let expiresAt: String

  static let empty = LeafBannerForm(
    id: "", scopeType: "", scopeValue: "", severity: "", message: "", startsAt: "", expiresAt: ""
  )

  init(
    id: String, scopeType: String, scopeValue: String, severity: String, message: String,
    startsAt: String, expiresAt: String
  ) {
    self.id = id
    self.scopeType = scopeType
    self.scopeValue = scopeValue
    self.severity = severity
    self.message = message
    self.startsAt = startsAt
    self.expiresAt = expiresAt
  }

  init(_ banner: Banner) {
    self.id = banner.id
    self.scopeType = banner.scopeType.rawValue
    self.scopeValue = banner.scopeValue
    self.severity = banner.severity.rawValue
    self.message = banner.message
    self.startsAt = banner.startsAt.map(Self.formatDateTimeLocal) ?? ""
    self.expiresAt = Self.formatDateTimeLocal(banner.expiresAt)
  }

  private static func formatDateTimeLocal(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
  }
}
