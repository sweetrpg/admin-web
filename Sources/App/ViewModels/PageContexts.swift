import Vapor

struct ListContext: Content {
  let banners: [LeafBanner]
  let isEmpty: Bool
  let user: LeafUser?
  let meta: PageMeta
}

struct FormContext: Content {
  let formAction: String
  let isEdit: Bool
  let banner: LeafBannerForm
  let scopeTypes: [String]
  let severities: [String]
  let user: LeafUser?
  let meta: PageMeta
}

struct MaintenanceModeListContext: Content {
  let rows: [LeafMaintenanceScopeRow]
  let user: LeafUser?
  let meta: PageMeta
}

struct MaintenanceModeFormContext: Content {
  let formAction: String
  let displayName: String
  let scopeType: String
  let scopeValue: String
  let isEdit: Bool
  let mode: LeafMaintenanceModeForm
  let user: LeafUser?
  let meta: PageMeta
}

struct UsersListContext: Content {
  let users: [LeafUserSummary]
  let isEmpty: Bool
  let allRoles: [String]
  let user: LeafUser?
  let meta: PageMeta
}

struct LeafUserSummary: Content {
  /// The Auth0 subject, percent-encoded - used as `id` in every form action/URL this template
  /// generates raw (unescaped) via `#(u.id)`, since that's the key `auth-api` understands (not
  /// the Mongo `User.id` `users-api` uses internally). A subject like `auth0|abc123` contains a
  /// `|`, not legal unescaped in a URL path segment - encoding it here rather than in the
  /// template keeps `list.leaf` simple and guarantees every generated URL is well-formed.
  let id: String
  let email: String
  let roles: [String]
  let deniedServices: [String]
  /// Roles not already assigned - what the "add role" dropdown should offer, so the form can't
  /// submit a role the user already has.
  let availableRoles: [String]

  init(subject: String, email: String, roles: [String], deniedServices: [String]) {
    self.id = subject.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subject
    self.email = email
    self.roles = roles
    self.deniedServices = deniedServices
    self.availableRoles = UsersController.allRoles.filter { !roles.contains($0) }
  }
}
