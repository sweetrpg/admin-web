# SweetRPG Admin Web

[![CI](https://github.com/sweetrpg/admin-web/actions/workflows/ci.yaml/badge.svg)](https://github.com/sweetrpg/admin-web/actions/workflows/ci.yaml)
[![License](https://img.shields.io/github/license/sweetrpg/admin-web.svg)](https://img.shields.io/github/license/sweetrpg/admin-web.svg)
[![Issues](https://img.shields.io/github/issues/sweetrpg/admin-web.svg)](https://img.shields.io/github/issues/sweetrpg/admin-web.svg)
[![PRs](https://img.shields.io/github/issues-pr/sweetrpg/admin-web.svg)](https://img.shields.io/github/issues-pr/sweetrpg/admin-web.svg)
[![Dependabot](https://badgen.net/github/dependabot/sweetrpg/admin-web)](https://badgen.net/github/dependabot/sweetrpg/admin-web)

[![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)

Server-rendered Vapor (Swift) frontend for managing SweetRPG platform banner messages: create,
edit, immediately expire, and delete banners shown across the other frontends. Auth0-gated -
every route requires a valid session. Talks to
[admin-api](https://github.com/sweetrpg/admin-api) server-to-server, following the same
architecture as [catalog-web](https://github.com/sweetrpg/catalog-web) (this repo's structural
model) - see that repo's `AGENTS.md` for the path-prefix-behind-Traefik pattern this app also
follows.

## Status

Scaffold for the `add-banner-messages` OpenSpec change (`sweetrpg/platform`, tasks 5-6). Banner
list, create/edit form (with required-expiration validation), immediate-expire, and delete are
implemented against admin-api's documented `/banners` CRUD surface. See "Known gaps" below for
what isn't finished.

## Run locally

```bash
swift run
```

Serves on `:8080`. Without `REDIS_HOST` set, falls back to in-memory sessions - fine for local
development. Without `ADMIN_API_URL` set, calls default to an in-cluster DNS name that won't
resolve outside the cluster - set it to a reachable admin-api endpoint for local development
against real data. Auth0 login needs `AUTH0_DOMAIN`/`AUTH0_CLIENT_ID`/`AUTH0_CLIENT_SECRET` set
to do anything (see "Known gaps").

## Known gaps

- **Auth0 application registration**: this app needs its own Auth0 application (client
  id/secret, its own callback URL) registered in the same tenant catalog-web uses - a human with
  Auth0 dashboard/Management API access needs to create it and populate
  `kubernetes/overlays/dev/secrets.yaml`'s `AUTH0_*` keys (via the `sweetrpg-admin` Akeyless
  path referenced there). Not something this codebase can do for itself.
- **Admin listing endpoint**: `specs/banner-messages/spec.md` (in `sweetrpg/platform`'s
  `add-banner-messages` OpenSpec change) only documents `GET /banners` as a scoped, active-only
  query - there's no documented endpoint that returns every banner (including expired/scheduled
  ones) for management purposes, which the banner list view needs. `AdminAPIClient.listAll()`
  calls `GET /banners?scope=platform&include_inactive=true` as a best-guess extension; confirm
  (or implement) this against a real admin-api deployment before trusting the list view to show
  more than currently-active banners. See `AdminAPIClient.swift`'s doc comment.
- **ArgoCD webhook**: not yet configured on this repo - see `docs/git-repos.md` in
  `sweetrpg/platform`. Needs the shared Akeyless-managed webhook secret, which this scaffolding
  pass didn't have separate access to provision beyond what `repo-setup-standard` already
  wires up.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and `AGENTS.md` for
project conventions.
