# CLAUDE.md — Project Configuration

## Product Context
- **Product name:** Estimating Software 2026
- **Primary user/persona:** Millwork/cabinetry shop estimator — trades professional building detailed material and labour cost estimates
- **Problem statement:** Replace a complex Excel-based estimating workflow with a structured web app that supports clients, estimates, sections, and line items backed by a material catalog
- **Non-goals:** Invoicing, job scheduling, accounting integration (post-MVP); self-service user registration (needs email infra first)

## Stack and Dependencies
- **Languages/frameworks:** Ruby on Rails 8.1, PostgreSQL, Hotwire (Turbo + Stimulus), Tailwind CSS
- **Key packages:** Propshaft (assets, no Sprockets), `tailwindcss-rails` (standalone CLI, no Node/npm), Importmap (JS, no Webpack), RSpec, FactoryBot, Faker, Shoulda Matchers, DatabaseCleaner, foreman
- **Data layer:** PostgreSQL 16 (development and production)
- **Build command:** `bin/rails tailwindcss:build`
- **Test command:** `bundle exec rspec`
- **Lint command:** `bundle exec rubocop`
- **Dev server command:** `bin/dev`

## Verification Commands
- **Run tests:** `bundle exec rspec`
- **Run linter:** `bundle exec rubocop`
- **Type check:** N/A (Ruby — no static type checker)

## Domain Glossary

| Term | Definition |
|------|-----------|
| Estimate | A project-level cost document belonging to a client; contains sections and line items |
| Section | A grouping of line items within an estimate (e.g., "Uppers", "Lowers") |
| Line Item | A single material or labour entry on an estimate with quantity, unit, and price |
| Material | A catalog entry representing a physical material (e.g., 3/4" maple plywood) |
| Short Code | A brief identifier for a material used for fast keyboard lookup (e.g., `PLY-34`) |
| Alias | An alternate short code or name that resolves to a canonical material |
| Client | The business or individual an estimate is prepared for |

## Local Development Setup
- **Prerequisites:** Ruby (see `.ruby-version`), PostgreSQL 16, Bundler
- **Install steps:**
  ```bash
  bundle install
  bin/rails db:create db:migrate db:seed   # prints generated admin password to stdout
  ```
- **How to run locally:** `bin/dev` (starts Rails + Tailwind watcher via foreman)
- **How to seed data:** `bin/rails db:seed` — prints generated admin credentials to stdout
- **How to run tests:** `bundle exec rspec`
- **Key URLs:** `http://localhost:3000` (local dev)

## Common Gotchas

- **Tailwind build required in CI** — `app/assets/builds/tailwind.css` is gitignored; run `bin/rails tailwindcss:build` before any job that renders views
- **No Node/npm** — Tailwind uses the standalone `tailwindcss-rails` CLI; JS is managed by Importmap
- **PostgreSQL only** — never use SQLite syntax; use `plpgsql` (not `pg_catalog.plpgsql`) in schema extension names
- **`has_secure_password` gotcha** — strip blank password params on user update or it overwrites the digest with an empty string
- **System specs need truncation** — DatabaseCleaner truncation strategy (not transactional fixtures) is configured in `spec/rails_helper.rb`
- **Session fixation** — always call `reset_session` before `session[:user_id]=` on login, and again on logout (not just `session.delete`)

## Integrations
- **GitHub repo:** `robknowles1/estimating_software_2026`
- **Staging URL:** N/A (pre-production)
- **CI pipeline:** `.github/workflows/ci.yml`

## Project Overrides

Rules here override global playbook rules for this project.

### Architecture Rules
- **Layering rules:** Controllers must be thin; computation and business logic belong in models or service objects. No logic in views.
- **Dependency boundaries:** All controllers inherit `require_login` via the `Authentication` concern. Authenticated layout: `application.html.erb`; unauthenticated: `sessions.html.erb`.
- **Error-handling conventions:** Never use bare `rescue` in views — use safe navigation (`&.`). Flash messages must use i18n (`t(".notice")`), never hardcoded strings.
- **i18n:** All user-facing strings must use Rails I18n lazy lookup (`t(".key")` in views, `t(".notice")` in controllers). Shared strings use full keys (`t("app.name")`). All keys in `config/locales/en.yml`.

### Delivery Rules
- **Branch strategy:** Feature branches off `main`. Format: `feature/<spec-id>-<short-description>` (e.g., `feature/spec-022-material-alias-auto-population`).
- **PR size policy:** One spec/feature per PR. Address all review comments and resolve GitHub threads before merging.
- **Commit format:** Conventional Commits — `type(scope): description`. Reference AC-# in commit footer where applicable.
- **Merge policy:** The human must always merge PRs and push to `main`. Agents must never merge or push directly to `main`.
- **PR comment resolution:** Reply to each review thread individually, then resolve it. Never batch-resolve threads without a reply.

### Model Overrides
<!-- Uncomment to override default model assignments:
- Override agent models: create `.claude/agents/<name>.md` with `model: sonnet` in frontmatter
- Increase turn limit: add `maxTurns: 80` to project agent frontmatter
-->

## Agent Workflow

This project uses the Claude Playbook agent system. Recommended workflow:

```
spec → architect (if complex) → developer → reviewer → qa
                                     ↑_______________|
                                     (fix and re-review)
```

| Agent | When to use |
|-------|-------------|
| `pm` | Translating requirements into business docs |
| `spec` | Translating requirements into implementation specs (`docs/specs/`) |
| `architect` | Complex features, new data models, system-wide decisions |
| `developer` | Implementing a ready spec, writing tests |
| `reviewer` | Code review before QA |
| `qa` | Verifying tests pass and spec is satisfied |
| `devops` | CI/CD, deployment, environment configuration |
| `scribe` | Keeping documentation and changelogs current |
| `security` | Auditing security-sensitive features |
| `ux` | UI/UX specs, component specs, accessibility |

### Pull Request Process

1. Developer completes work and hands off to reviewer (`/reviewer`)
2. Reviewer approves or returns feedback
3. QA runs tests (`/qa`)
4. Open PR with `gh pr create` — include summary, first-login/setup notes if relevant, and a test plan checklist
5. Address all review comments before merging; reply to each thread individually before resolving
6. Human merges the PR — agents never merge or push to `main`

---

## Rails Conventions

### Layout
- Authenticated pages: `app/views/layouts/application.html.erb` (sidebar layout)
- Unauthenticated pages (login): `app/views/layouts/sessions.html.erb` (split-panel)
- Sidebar nav: `app/views/layouts/_sidebar.html.erb`
- Flash messages: `app/views/layouts/_flashes.html.erb`
- Keep layout files thin — extract logic into partials

### Controllers
- Instance variables (`@resource`) are the standard Rails pattern — correct and expected
- All controllers inherit `require_login` via the `Authentication` concern
- Strip blank password params on update so `has_secure_password` doesn't overwrite the digest

### Database
- PostgreSQL only — use `plpgsql` (not `pg_catalog.plpgsql`) in schema extension names
- Use `FOR UPDATE` locking (not `BEGIN EXCLUSIVE`) — PostgreSQL supports it natively
- Partial unique indexes: `WHERE (is_primary = TRUE)` (PostgreSQL syntax)

---

## Test Conventions

- **System specs** use Selenium with headless Chrome (`driven_by(:selenium_chrome_headless)`)
- System specs use `DatabaseCleaner` truncation strategy — do not use transactional fixtures
- Use `around` hooks with `ensure` for any config that must be restored after a spec
- Session helper: `sign_in(user, password: "password123")` accepts an optional `password:` keyword arg
- Test selectors must match actual rendered text — verify button/link text in views before writing specs

---

## CI

Workflow file: `.github/workflows/ci.yml`

- `lint` — RuboCop
- `scan_ruby` — Brakeman + bundler-audit
- `scan_js` — importmap audit
- `test` — model + request specs (`bundle exec rspec spec/models spec/requests`)
- `system-test` — system specs (`bundle exec rspec spec/system`)

Both `test` and `system-test` jobs require:
1. A `postgres:16` service container
2. `DATABASE_URL` env var pointing to the service
3. A `bin/rails tailwindcss:build` step before running specs (built CSS is gitignored)

---

## Spec Build Order

Spec files live in `docs/specs/`. Architecture Decision Records live in `docs/architecture/`.

| Spec | Title | Status |
|------|-------|--------|
| SPEC-010 | Estimating Foundation | ✅ done |
| SPEC-011 | Line Item Grid | ✅ done |
| SPEC-012 | Job-Level Costs & Totals | ✅ done |
| SPEC-013 | Product Catalog | ✅ done |
| SPEC-014 | Materials Rework | ✅ done |
| SPEC-015 | Searchable Material Dropdown | ✅ done |
| SPEC-016 | Formula Input Qty Field | ✅ done |
| SPEC-017 | Estimate Totals UX | ✅ done |
| SPEC-018 | Other Material Slot | ✅ done |
| SPEC-019 | Line Item Form Tom Select | ✅ done |
| SPEC-020 | Exterior Back Qty Autofill | ✅ done |
| SPEC-021 | CSV Import Line Items | ✅ done |
| SPEC-022 | Material Alias Auto-Population | ✅ done |
| SPEC-023 | Estimate Date Fields | 📋 ready |
| SPEC-024 | Materials Library Search & Pagination | 📋 ready |
| SPEC-025 | Room Tracking on CSV Import | 📋 ready |
| SPEC-026 | Proposal / Bid Letter Wizard | 📋 ready |
| SPEC-027 | CRM Expansion on Clients | 📋 ready |
| SPEC-028 | Asana Material Price Sync | 📋 draft |
| SPEC-029 | Product Presets Auto-Population | 🔄 in progress |

---

## First-Time Setup

```bash
bundle install
bin/rails db:create db:migrate db:seed   # prints generated admin password to stdout
bin/dev                                   # starts Rails + Tailwind watcher
```

Test suite: `bundle exec rspec`
