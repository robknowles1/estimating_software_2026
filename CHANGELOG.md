# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not yet use semantic versioning — entries are grouped by phase.

---

## [Unreleased]

No unreleased changes.

---

## [Phase 1 — Authentication and User Management] - 2026-04-05

**SPEC-003 complete.**

### Added
- `User` model with `has_secure_password`, email uniqueness/format validations, email downcased on save
- `Authentication` concern: `require_login` before action, `current_user`, `logged_in?` helpers
- `SessionsController`: login (`POST /session`) and logout (`DELETE /session`)
- `UsersController`: full CRUD except destroy (index, new, create, edit, update)
- Placeholder `EstimatesController` with index action (login redirect target)
- `db/seeds.rb`: idempotent development-only seed that generates a random admin password on first run
- RSpec test suite: 23 examples across model, request, and system specs
- `tailwindcss-rails` gem and full UI redesign: dark `slate-900` sidebar, `amber-600` accent, split-panel login page
- `bin/dev` + `Procfile.dev` for multi-process development (Rails server + Tailwind watcher)
- `database_cleaner-active_record` gem for correct system spec isolation

---

## [Phase 0 — Foundation] - 2026-04-04

**SPEC-002 complete.**

### Added
- Rails 8.1.2 application scaffolded with PostgreSQL, Propshaft, Hotwire (Turbo + Stimulus), and importmap
- `bcrypt` gem added for `has_secure_password` support
- `acts_as_list` gem added for ordered section and line item management
- `solid_cache`, `solid_queue`, `solid_cable` included for production background and cable adapters
- Kamal deployment configuration in `.kamal/`
- Docker build file (`Dockerfile`) and `.dockerignore`
- `.rubocop.yml` with `rubocop-rails-omakase` rules
- `bundler-audit` and `brakeman` added to development/test group for security scanning
- Production database configuration for four PostgreSQL databases (primary, cache, queue, cable)

---

## Architecture Decisions Logged

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| ADR-001 | Markup Level | accepted | 2026-04-01 |
| ADR-002 | PDF Generation Strategy | accepted | 2026-04-01 |
| ADR-003 | Real-Time Totals | accepted | 2026-04-01 |
| ADR-004 | Authentication | accepted | 2026-04-01 |
| ADR-005 | Line Item Entry UX | accepted (pending estimator validation) | 2026-04-01 |

See `docs/architecture/` for full decision records.

---

## Spec Index at This Point

| ID | Title | Status |
|----|-------|--------|
| SPEC-001 | Estimating Software MVP | draft |
| SPEC-002 | Phase 0 — Foundation | done |
| SPEC-003 | Phase 1 — Authentication and User Management | done |
| SPEC-004 | Phase 2 — Client and Contact Management | ready |
| SPEC-005 | Phase 3 — Estimate Scaffold and Sections | ready |
| SPEC-006 | Phase 4 — Line Items and Real-Time Totals | ready |
| SPEC-007 | Phase 5 — Catalog and Line Item Autocomplete | draft |
| SPEC-008 | Phase 6 — Document Output | draft |
| SPEC-009 | Phase 7 — Polish and Hardening | draft |
