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

struct AppCardStatusListContext: Content {
  let rows: [LeafAppCardStatusRow]
  let user: LeafUser?
  let meta: PageMeta
}

struct AppCardStatusFormContext: Content {
  let formAction: String
  let displayName: String
  let scopeType: String
  let scopeValue: String
  let isEdit: Bool
  let status: LeafAppCardStatusForm
  let user: LeafUser?
  let meta: PageMeta
}

struct UsersListContext: Content {
  let users: [LeafUserSummary]
  let isEmpty: Bool
  let allRoles: [String]
  /// True when the users-api/auth-api composition failed - the page renders a clear
  /// "unavailable" state instead of a raw 500 error page.
  let unavailable: Bool
  /// True when a backend answered with an error status; `refusedMessage` is its message, if any.
  let refused: Bool
  let refusedMessage: String?
  /// The services offered in the deny form; empty with `servicesUnavailable` when the list
  /// could not be loaded, in which case the form is replaced by a message.
  let services: [ServiceOption]
  let servicesUnavailable: Bool
  let user: LeafUser?
  let meta: PageMeta

  init(
    users: [LeafUserSummary], isEmpty: Bool, allRoles: [String], unavailable: Bool,
    refused: Bool = false, refusedMessage: String? = nil, services: [ServiceOption] = [],
    servicesUnavailable: Bool = false, user: LeafUser?, meta: PageMeta
  ) {
    self.services = services
    self.servicesUnavailable = servicesUnavailable
    self.users = users
    self.isEmpty = isEmpty
    self.allRoles = allRoles
    self.unavailable = unavailable
    self.refused = refused
    self.refusedMessage = refusedMessage
    self.user = user
    self.meta = meta
  }
}

struct LeafUserSummary: Content {
  /// The Auth0 subject, percent-encoded - used as `id` in every form action/URL this template
  /// generates raw (unescaped) via `#(u.id)`, since that's the key `auth-api` understands (not
  /// the Mongo `User.id` `users-api` uses internally). A subject like `auth0|abc123` contains a
  /// `|`, not legal unescaped in a URL path segment - encoding it here rather than in the
  /// template keeps `list.leaf` simple and guarantees every generated URL is well-formed.
  let id: String
  /// `users-api`'s canonical user ID, percent-encoded - what `entitlements-api` keys on, unlike
  /// `id` above (the Auth0 subject `auth-api` keys on).
  let userID: String
  let email: String
  /// Every login linked to this person, primary first.
  let identities: [String]
  let roles: [String]
  let deniedServices: [String]
  /// Roles not already assigned - what the "add role" dropdown should offer, so the form can't
  /// submit a role the user already has.
  let availableRoles: [String]

  init(
    subject: String, userID: String = "", email: String, identities: [String] = [],
    roles: [String], deniedServices: [String]
  ) {
    self.identities = identities
    self.id = subject.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subject
    self.userID = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
    self.email = email
    self.roles = roles
    self.deniedServices = deniedServices
    self.availableRoles = UsersController.allRoles.filter { !roles.contains($0) }
  }
}
