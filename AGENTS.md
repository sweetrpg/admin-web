# AGENTS.md

This file provides guidance to Claude Code, Codex, GitHub Copilot, and other coding agents
working in this repository.

## About This Project

`admin-web` is a server-rendered Vapor (Swift) frontend for managing SweetRPG platform banner
messages - create, edit, immediately expire, and delete banners that other frontends (main-web,
catalog-web, ...) display. It is modeled structurally on `catalog-web`
(`sweetrpg/catalog-web`) - same Auth0 Authorization Code flow, same path-prefix-behind-Traefik
architecture, same Redis-backed session pattern - but is intentionally smaller: no Prometheus
metrics, distributed tracing, Sentry reporting, CORS middleware, or rate limiting. Those exist in
catalog-web because it's a public-facing, higher-traffic reader surface; this app is an internal
tool with a handful of authenticated operators, so that instrumentation would be unused
complexity rather than a baseline worth carrying forward unconditionally. Add any of it back if
this app's operational needs actually justify it, not by default.

Pages are rendered server-side (Leaf templates in `Resources/Views/`) from data fetched
server-to-server from `admin-api` - not via browser-side `fetch`, same rationale as catalog-web
(no CORS concern for server-to-server calls).

### Backend dependency

- **admin-api**: the only backend this app talks to - `POST/GET/PUT/DELETE /banners`. See
  `AdminAPIClient.swift`.

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

### Trust boundary

Per `design.md`'s explicit decision: any authenticated user in the Auth0 tenant can manage
banners - no role-based restriction. `AuthRequiredMiddleware` gates every route on session
presence only, nothing finer-grained. Narrowing this to a specific role/permission is future
work, not a gap in this scaffold.

### Auth0 application registration (human follow-up required)

This app needs its own Auth0 application (client id/secret, its own callback URL) registered in
the same tenant catalog-web uses - Auth0 requires a callback URL to be registered per
application, so the client id can't be shared. A human with Auth0 dashboard/Management API
access needs to create it and populate the `AUTH0_*` secret values (see
`kubernetes/overlays/dev/secrets.yaml`).

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

`swift run` serves on `:8080`. Without `REDIS_HOST` set, falls back to in-memory sessions. Without
`ADMIN_API_URL` set, calls default to an in-cluster DNS name that won't resolve outside the
cluster - set it to a reachable admin-api endpoint for local development.
