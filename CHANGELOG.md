
## 0.17.0 - 2026-08-23

### Added
- Add Game Systems link to app switcher
- Change admin link text to Administration
- Scope value hint and graceful users page error state (refs #22)



## 0.16.1 - 2026-08-21

### Fixed
- Fix cpu resource limit quantity that never matched ArgoCD's applied manifest



## 0.16.0 - 2026-08-20

### Added
- Localize maintenance-mode scope names via Lingo-Vapor



## 0.15.0 - 2026-08-19

### Added
- Add app switcher grid next to avatar menu



## 0.14.0 - 2026-08-19


## 0.14.0 - 2026-08-19

### Added
- Update page title to Administration
- Add controller-level logging for every mutation and not-found path



## 0.13.1 - 2026-08-18

### Fixed
- Render build info as a span, not an h6



## 0.13.0 - 2026-08-18

### Added
- Forward acting user's Auth0 token to admin-api/users-api



## 0.12.0 - 2026-08-18

### Added
- Add admin theme stylesheet to base template
- Add theme-toggle UI to admin-web



## 0.11.0 - 2026-08-18

### Added
- Add structured logging and OTel tracing


### Documentation
- Add ArgoCD deployment badge


### Fixed
- Remove duplicate logging bootstrap, guard tracing bootstrap
- Actually propagate trace context to auth-api/users-api
- Sort imports lexicographically in TracingSetup
- Correct AUTH_API_URL/USERS_API_URL ports to 8000



## 0.10.0 - 2026-08-17

### Added
- Add tracing


### Changed
- Rename environment variables for clarity
- Extract view models and update shared URL references
- Reorganize source files into Clients, Config, and Handlers directories
- Rename files to follow naming convention


### Fixed
- Remove await



## 0.9.0 - 2026-08-14

### Added
- Route generic error status codes to shared-web


### Fixed
- Decode the shared session's expiry as RFC 3339



## 0.8.0 - 2026-08-12

### Added
- Report build version on /status/ping



## 0.7.1 - 2026-08-12

### Fixed
- Pass return_to on logout link



## 0.7.0 - 2026-08-11

### Added
- Honor shared session expiry field



## 0.6.0 - 2026-08-11

### Added
- Restructure form labels for accessibility


### Fixed
- Image path for favicon



## 0.5.0 - 2026-08-09

### Added
- Show build hash in footer, avatar menu in header


### Fixed
- Stop using leaf-kit's unimplemented ?? operator in banner/maintenance forms



## 0.4.1 - 2026-08-09

### Fixed
- Update shared static asset paths for assets-web's css/img/js reorg



## 0.4.0 - 2026-08-07

### Added
- Swap nav logo for theme-aware SVGs
- Compose users-api identity with auth-api role data
- Forward inbound traceparent header to auth-api and users-api


### Fixed
- Dark theme, table/form layout, and Leaf whitespace bugs



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
