# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not yet use semantic versioning — entries are grouped by phase.

---

## [Unreleased]

### In Progress
- Phase 1 — Authentication and User Management (SPEC-003)

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
| SPEC-003 | Phase 1 — Authentication and User Management | ready |
| SPEC-004 | Phase 2 — Client and Contact Management | ready |
| SPEC-005 | Phase 3 — Estimate Scaffold and Sections | ready |
| SPEC-006 | Phase 4 — Line Items and Real-Time Totals | ready |
| SPEC-007 | Phase 5 — Catalog and Line Item Autocomplete | draft |
| SPEC-008 | Phase 6 — Document Output | draft |
| SPEC-009 | Phase 7 — Polish and Hardening | draft |
