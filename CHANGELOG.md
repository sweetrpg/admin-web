
## Unreleased

### Added
- Initial scaffold: Vapor/Leaf server-rendered frontend for banner message management (list,
  create/edit, immediate expire, delete), Auth0 login flow gating every route, Redis-backed
  sessions, Docker image build, and Kubernetes manifests.
- User role and per-service deny-entry management UI (`/users`), talking to `users-api`'s
  `RolesController` via a shared internal service token.

### Changed
- Migrated to the platform's shared suite-wide login: removed this app's own Auth0
  Authorization Code flow in favor of reading the session `auth-web` establishes.
  `AuthRequiredMiddleware` now requires the `admin` role, not merely session presence, since
  this app also hosts the role/service-access admin UI above.
