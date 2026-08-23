# AGENTS.md

This file provides guidance to Claude Code, Codex, GitHub Copilot, and other coding agents
working in this repository.

## About This Project

`admin-web` is a server-rendered Vapor (Swift) frontend for platform-wide admin concerns:
banner messages (create, edit, immediately expire, delete - shown across `main-web`,
`catalog-web`, ...) and the `admin`-gated user role/service-access management UI
(`UsersController.swift`) - not a separate frontend, see `add-user-api-authn-authz`'s design.md
for why both live here. Since `split-authz-into-auth-api`, that management UI composes two
backends (`users-api` for identity, `auth-api` for roles/deny entries) instead of one - see
"Backend dependencies" below. It is modeled structurally on `catalog-web`
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
  Write calls (`POST`/`PUT`/`DELETE`) forward the acting admin's own Auth0 access token (from the
  shared session, see `SessionUser.accessToken`) as an `Authorization` bearer - `admin-api`
  verifies it and checks the user's role itself, per `sweetrpg/platform`'s `api-client-auth`
  change; `GET /banners` needs no credential.
- **users-api**: minimal user identity listing (id/email) - `AdminUsersController`'s
  `GET /api/admin/users`, called via `UsersAPIClient.swift`. Same bearer-forwarding model as
  admin-api above, not the shared `X-Internal-Service-Token` this app used to send.
- **auth-api**: user roles and per-service deny entries, keyed by Auth0 subject -
  `RolesController`'s `/api/admin/roles`/`/api/admin/deny-entries` routes, called via
  `AuthAPIClient.swift`. Still authenticated with the shared `X-Internal-Service-Token` model
  (`AUTH_API_INTERNAL_SERVICE_TOKEN`) - `api-client-auth` covers admin-api and users-api only,
  auth-api's own routes are a follow-up, not yet migrated.
  `UsersController.swift` composes this with `users-api`'s identity listing, joined by subject,
  since neither service alone has both halves of what the management UI needs to display - see
  `sweetrpg/platform`'s `split-authz-into-auth-api` change design.md.

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
`auth-web` writes, from `auth-web`'s own dedicated `redis.sweetrpg-auth` instance - see
`sweetrpg/platform`'s `docs/frontend-conventions.md` for the full registry of per-namespace
Redis instances. It deliberately does not go through Vapor's `Session`/`SessionsMiddleware` -
touching `req.session` on every request would create and write back a brand-new session for
every anonymous visitor, which is exactly the write this read-only consumer must never make.
Fails open (`nil`) on every error path.

### Trust boundary

Revised from this app's original design (any authenticated user in the Auth0 tenant could manage
banners): `AuthRequiredMiddleware` now requires the `admin` role, since this app also hosts the
role/service-access management UI, a more sensitive surface than banner management alone. The
`admin` role comes from the shared session's `roles` field, verified once by `auth-api` at login
time in `auth-web` - this app trusts that verification for its own page-access gate rather than
re-checking per request. The session's `accessToken` (see `SessionUser.swift`) is a separate,
narrower use: forwarded as the bearer credential on outgoing `admin-api`/`users-api` calls, where
those services independently re-verify it and check the role themselves - see "Backend
dependencies" above. Trade-off on the page-access gate: a role revoked after login stays in
effect until the session naturally expires or the user logs out and back in - see
`AuthRequiredMiddleware.swift`'s doc comment for why re-verifying live isn't a better option
here.

## Localization

Implemented per sweetrpg/platform's `full-localization-web-apps` OpenSpec change.

- **LingoVapor** is wired in `configure.swift` (`defaultLocale: "en"`, localizations dir
  `Resources/Localizations/`) for controller-side lookups (`maintenance.scope.*` keys).
- Every user-facing template string lives in `Resources/Localizations/<code>.json` as a flat
  dotted key (e.g. `banners.column.scope`). English (`en.json`) is the default and fallback.
- Locale resolution per request (`I18n.swift`): the `locale` cookie, then the first tag of the
  `Accept-Language` header's base subtag, then `"en"`. Tables are loaded once at startup and
  exposed to templates through `PageMeta.l10n`.
- In Leaf templates, interpolate translations as `#(meta.l10n.<key>)` (dots in JSON keys become
  underscores at lookup time). For interpolated strings like "Remove #(role) role", use
  prefix/suffix key pairs so Leaf interpolates between two translated fragments.
- To add a locale, drop a `<code>.json` next to `en.json` - resolution picks it up with no code
  changes. Missing keys render empty; keep `en.json` complete.
- CI enforces this: `scripts/check-template-strings.sh` (run by the `locale-lint` job in
  `.github/workflows/ci.yaml` and `pr.yaml`) fails on hardcoded user-facing text in any
  `Resources/Views/**/*.leaf` outside an allowlist of brand names and the footer build line.

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
Without `ADMIN_API_URL`/`USERS_API_URL`/`AUTH_API_URL` set, calls default to in-cluster DNS
names that won't resolve outside the cluster - set them to reachable endpoints for local
development. `admin-api`/`users-api` calls now forward the session's `accessToken`, so those two
services need `AUTH_API_URL` configured (to verify it) rather than a matching shared secret on
this app's side. `AUTH_API_INTERNAL_SERVICE_TOKEN` still needs to match `auth-api`'s own
`INTERNAL_SERVICE_TOKEN`, or every role/deny-entry call fails closed with a 500 - that surface
hasn't migrated off the shared-secret model yet.
