# AGENTS.md

This file provides guidance to Claude Code, Codex, GitHub Copilot, and other coding agents
working in this repository.

## About This Project

`admin-web` is a server-rendered Vapor (Swift) frontend for platform-wide admin concerns:
banner messages (create, edit, immediately expire, delete - shown across `main-web`,
`catalog-web`, ...) and, per platform's `add-user-api-authn-authz` change, the `admin`-gated
user role/service-access management UI (`UsersController.swift`) - not a separate frontend, see
that change's design.md for why both live here. It is modeled structurally on `catalog-web`
(`sweetrpg/catalog-web`) - same path-prefix-behind-Traefik architecture, same read-only
shared-session pattern - but is intentionally smaller: no Prometheus metrics, distributed
tracing, CORS middleware, or rate limiting. Those exist in catalog-web because it's a
public-facing, higher-traffic reader surface; this app is an internal tool with a handful of
authenticated operators, so that instrumentation would be unused complexity rather than a
baseline worth carrying forward unconditionally. Add any of it back if this app's operational
needs actually justify it, not by default. Sentry error reporting is the one exception, added
platform-wide across every application regardless of traffic profile - see
`SentryReporter.swift`/`SentryMiddleware.swift`, ported unchanged from catalog-web's own.

Pages are rendered server-side (Leaf templates in `Resources/Views/`) from data fetched
server-to-server from `admin-api`/`users-api` - not via browser-side `fetch`, same rationale as
catalog-web (no CORS concern for server-to-server calls).

### Backend dependencies

- **admin-api**: banner messages - `POST/GET/PUT/DELETE /banners`. See `AdminAPIClient.swift`.
  Write calls (`POST`/`PUT`/`DELETE`) are authenticated the same way as `users-api` below - a
  shared `X-Internal-Service-Token` (`ADMIN_API_INTERNAL_SERVICE_TOKEN`) plus `X-Acting-User-Sub`
  for audit attribution; `GET /banners` needs neither.
- **users-api**: user roles and per-service deny entries - `RolesController`'s `/api/admin/*`
  routes, called via `UsersAPIClient.swift`. Authenticated with a shared
  `X-Internal-Service-Token` (`USERS_API_INTERNAL_SERVICE_TOKEN`), not an Auth0 bearer token -
  this app never holds one of its own (see "Login and the shared session" below).

### Known gap: no documented admin-listing endpoint

`specs/banner-messages/spec.md` (in `sweetrpg/platform`'s `add-banner-messages` OpenSpec change)
documents `GET /banners` as scoped-and-active-only (tasks.md 3.2: "returns active banners only,
ordered by severity"). The banner-message-admin spec's list view needs to show **every** banner,
including expired and future-dated ones. `AdminAPIClient.listAll()` calls `GET
/banners?scope=platform&include_inactive=true` as a best-guess extension of the documented
contract - admin-api may not implement `include_inactive` yet. Confirm against a real admin-api
deployment (or get admin-api's team to add a real admin-listing shape) before assuming the list
view shows more than currently-active banners. Don't build further UI on top of this assumption
without confirming it first.

### The path-prefix architecture (important - don't break this)

Same as catalog-web: this app runs behind Traefik at `dev.sweetrpg.com/admin` (dev), which
strips `/admin` before the request reaches this app. Every link, form action, and redirect this
app generates has to add the prefix back via `Request.basePath` (`AppPaths.swift`) /
`Request.redirectLocal(to:)`, or the *next* browser request won't round-trip through the ingress
correctly. Every Leaf template's internal `href`/`action`/`src` uses `#(meta.basePath)`.

### Login and the shared session

This app has no login flow of its own. `auth-web` is the platform's sole owner of the Auth0
Authorization Code exchange (see `sweetrpg/platform`'s `add-user-api-authn-authz` OpenSpec
change) - `AuthController.swift`/`Auth0Config.swift`/`ResilientRedisSessionDriver.swift` used to
exist here and were removed as part of that migration, along with this app's own per-application
Auth0 registration. "Log in"/"Log out" links (`meta.loginURL`/`meta.logoutURL`, `PageMeta`) point
at `auth-web` directly instead.

`Request.currentUser` (`SessionUserAccess.swift`) reads the shared `sweetrpg_session` cookie
`auth-web` writes, from the shared `redis.sweetrpg-support` instance auth-web also uses, on its
own DB index - see `sweetrpg/platform`'s `docs/frontend-conventions.md` for the full DB-index
registry. It deliberately does not go through Vapor's `Session`/`SessionsMiddleware` - touching
`req.session` on every request would create and write back a brand-new session for every
anonymous visitor,
which is exactly the write this read-only consumer must never make. Fails open (`nil`) on every
error path.

### Trust boundary

Revised from this app's original design (any authenticated user in the Auth0 tenant could manage
banners): `AuthRequiredMiddleware` now requires the `admin` role, since this app also hosts the
role/service-access management UI, a more sensitive surface than banner management alone. The
`admin` role comes from the shared session's `roles` field, verified once by `users-api` at login
time in `auth-web` - this app trusts that verification rather than re-checking per request (it
never holds a bearer token to present to `users-api`'s `/authz/check` itself). Trade-off: a role
revoked after login stays in effect until the session naturally expires or the user logs out and
back in - see `AuthRequiredMiddleware.swift`'s doc comment for why re-verifying live isn't a
better option here.

## Committing Code

[Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <description>`.

## Branches and Workflow

Git-flow (see `docs/git-flow.md` in `sweetrpg/platform`): `develop` is the integration branch,
`master` reflects the latest release. Feature/fix branches off `develop`, PR back into `develop`.

## Running Checks Locally

```bash
swift build
swift test
swift format lint --recursive --strict Sources Tests
```

`swift run` serves on `:8080`. Without `REDIS_HOST` set, every visitor reads as logged-out.
Without `ADMIN_API_URL`/`USERS_API_URL` set, calls default to in-cluster DNS names that won't
resolve outside the cluster - set them to reachable endpoints for local development.
`USERS_API_INTERNAL_SERVICE_TOKEN` also needs to match `users-api`'s own
`INTERNAL_SERVICE_TOKEN`, or every users-api call fails closed with a 500.
`ADMIN_API_INTERNAL_SERVICE_TOKEN` similarly needs to match `admin-api`'s own
`INTERNAL_SERVICE_TOKEN`, or every banner write fails closed with a 500.
