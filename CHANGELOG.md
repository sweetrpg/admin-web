
## 0.3.1 - 2026-08-04

### Fixed
- Authenticate to the shared session Redis
- Send created_by when creating a banner



## 0.3.0 - 2026-08-02


## 0.3.0 - 2026-08-02

### Added
- Send internal-service write auth headers to admin-api (#10)
- Add maintenance-mode admin page
- Add guarded Sentry error reporting


### Documentation
- Correct users-api's port to 8080 in overlay comments



## 0.2.0 - 2026-08-01

### Added
- Send internal-service write auth headers to admin-api (#10)


### Documentation
- Correct users-api's port to 8080 in overlay comments



## 0.1.0 - 2026-08-01

### Added
- Scaffold admin-web Vapor frontend for banner message management
- Migrate to auth-web's shared session, require admin role
- Add the role/service-access management UI
- Send acting admin's sub to users-api for audit logging


### Fixed
- Point dev overlay at latest image tag (#4)



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
