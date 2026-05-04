# ADR-012: Digital Ocean Hosting with Kamal 2

**Date:** 2026-04-25  
**Status:** Accepted

---

## Context

The estimating app needs a hosting environment for staging validation before it reaches real users. The constraints were:

- No additional monthly spend beyond an existing Digital Ocean Droplet
- Deployment tooling already bundled with Rails 8.1 (Kamal 2)
- Simple enough for a single developer to operate
- CI/CD on merge to `main` without manual intervention

---

## Decision

**Host on Digital Ocean Droplets using Kamal 2.**

- **Staging**: existing 1 vCPU / 1 GB Droplet at `64.23.238.38` (shared with syndicate-development.com)
- **Production** (future): dedicated Droplet provisioned when ready for real users
- **Container registry**: GitHub Container Registry (`ghcr.io`) — free for public images, no separate DO Container Registry cost
- **Database**: Postgres 16 as a Kamal accessory container on the same Droplet, storing data in a named Docker volume
- **CI/CD**: `deploy_staging` job in `.github/workflows/ci.yml` — fires on push to `main` after all five CI checks pass

---

## Alternatives Considered

### Digital Ocean App Platform

Managed PaaS with built-in scaling, SSL, and zero-downtime deploys. Rejected because it adds $12–25/month minimum above the current Droplet cost and the app doesn't yet need auto-scaling.

### Fly.io / Render

Similar managed PaaS tradeoffs. Rejected for the same cost reason.

### Heroku

More expensive at this tier. Rejected.

### Keep using Kamal with DO Container Registry

DO Container Registry costs $5/month. Swapped to `ghcr.io` (free) instead.

---

## Consequences

### Accepted trade-offs

- **Staging shares a Droplet with another site** — Nginx holds ports 80/443, so `kamal-proxy` runs on 3000/3001. This is a staging-only quirk; production will get a dedicated Droplet.
- **1 vCPU is slow to build Docker images** — the CI runner builds the image and pushes to `ghcr.io`; the Droplet only pulls and runs it. Cold-start health check timeout is set to 120s to accommodate the slow boot.
- **Single-node Postgres** — data loss on Droplet failure. Acceptable for staging; production will need a backup strategy (DO Managed Postgres or automated volume snapshots).
- **No SSL on staging** — serving plain HTTP on port 3000. Acceptable for internal testing only.

### Benefits

- Zero extra cost during early development
- Kamal is already in the Gemfile; no new tooling to learn
- GitHub Actions `deploy_staging` job gives automatic deploys on every merge to `main`
- `bin/kamal` CLI gives direct access to logs, console, and shell without SSH

---

## Key Configuration Decisions

| Decision | Rationale |
|---|---|
| `proxy.run.http_port: 3000` | Nginx holds 80; avoid conflict |
| `proxy.run.https_port: 3001` | Nginx holds 443; avoid conflict |
| `deploy_timeout: 120` | 1 vCPU boot takes >30s; default 30s caused false failures |
| `DB_HOST: estimating-software-staging-db` | Docker container hostname; `127.0.0.1` is container loopback, not host |
| `SEED_ADMIN_EMAIL` env-var gate in seeds.rb | Allows seeding an admin in non-development environments without hardcoding credentials |
| Image registry: `ghcr.io/robknowles1/...` | Free tier, integrated with existing GitHub auth |
