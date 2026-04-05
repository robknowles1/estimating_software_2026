# CLAUDE.md — Project Instructions for Claude Code Agents

This file is automatically loaded by Claude Code. All agents (developer, reviewer, qa, architect, pm, scribe) must follow these instructions.

---

## Branching Workflow

**Always work on a feature branch off the latest `main`.** Never commit Phase work directly to `main`.

Before starting any new spec:
```bash
git checkout main
git pull origin main
git checkout -b feature/phase-N-<short-description>
```

Examples:
- `feature/phase-2-clients-contacts`
- `feature/phase-3-estimates-sections`

After work is complete, open a PR against `main` and follow the PR process below.

---

## Pull Request Process

1. Developer completes work and hands off to reviewer (`/reviewer`)
2. Reviewer approves or returns feedback
3. QA runs tests (`/qa`)
4. Open PR with `gh pr create` — include summary, first-login/setup notes if relevant, and a test plan checklist
5. Address all review comments before merging
6. Resolve all addressed comment threads on GitHub after pushing fixes

---

## Tech Stack

- **Rails 8.1** with PostgreSQL (development and production)
- **Propshaft** for assets (no Sprockets)
- **Tailwind CSS** via `tailwindcss-rails` gem (standalone CLI, no Node/npm)
  - Input: `app/assets/tailwind/application.css`
  - Output: `app/assets/builds/tailwind.css` (gitignored — must build in CI)
  - Run `bin/rails tailwindcss:build` before tests in any CI step that renders views
- **Hotwire** (Turbo + Stimulus) for real-time interactions
- **Importmap** for JavaScript (no Webpack/esbuild)
- **RSpec** for all tests (not Minitest) — run with `bundle exec rspec`
- **FactoryBot + Faker + Shoulda Matchers + DatabaseCleaner** for test infrastructure
- **foreman** via `bin/dev` to start Rails server + Tailwind watcher together

---

## Code Conventions

### Internationalisation (i18n)
All user-facing strings must use Rails I18n — no hardcoded strings in views or controllers.

- Views: use lazy lookup `t(".key")` scoped to the current view path
- Controllers: use lazy lookup `t(".notice")` / `t(".alert")` scoped to controller#action
- Shared strings (app name, nav labels, common actions): use full keys e.g. `t("app.name")`, `t("common.edit")`
- All keys live in `config/locales/en.yml`

### Layout
- Authenticated pages use `app/views/layouts/application.html.erb` (sidebar layout)
- Unauthenticated pages (login) use `app/views/layouts/sessions.html.erb` (split-panel)
- Sidebar nav lives in `app/views/layouts/_sidebar.html.erb`
- Flash messages live in `app/views/layouts/_flashes.html.erb`
- Keep layout files thin — extract any logic into partials

### Controllers
- Instance variables (`@resource`) are the standard Rails way to pass data to views — this is correct and expected
- All controllers inherit `require_login` from `ApplicationController` via the `Authentication` concern
- Flash messages must use i18n: `t(".notice")` not hardcoded strings
- Strip blank password params on update so `has_secure_password` doesn't overwrite digest

### Security
- Always call `reset_session` before setting `session[:user_id]` on login (session fixation prevention)
- Always call `reset_session` on logout (not just `session.delete`)
- Never use bare `rescue` in views — use safe navigation (`&.`)

### Database
- PostgreSQL only — use `plpgsql` (not `pg_catalog.plpgsql`) in schema extension names
- Use `FOR UPDATE` locking (not `BEGIN EXCLUSIVE`) for concurrency — PostgreSQL supports it natively
- Partial unique indexes use PostgreSQL syntax: `WHERE (is_primary = TRUE)`

---

## Test Conventions

- **System specs** use Selenium with headless Chrome (`driven_by(:selenium_chrome_headless)`)
- System specs use `DatabaseCleaner` truncation strategy (configured in `spec/rails_helper.rb`) — do not use transactional fixtures for system specs
- Use `around` hooks with `ensure` for any config that must be restored after a spec
- Session helper `sign_in(user, password: "password123")` accepts an optional `password:` keyword arg
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

## Spec Phases and Build Order

```
SPEC-002 (Phase 0: Foundation)                    ✅ done
  └── SPEC-003 (Phase 1: Auth + Users)            ✅ done
        └── SPEC-004 (Phase 2: Clients)           🔄 in progress
              └── SPEC-005 (Phase 3: Estimates)   ⏳ ready
                    └── SPEC-006 (Phase 4: Line Items + Totals)
                          ├── SPEC-007 (Phase 5: Catalog + Autocomplete)
                          └── SPEC-008 (Phase 6: Document Output)
                                └── SPEC-009 (Phase 7: Polish)
```

Spec files live in `docs/specs/`. Architecture Decision Records live in `docs/architecture/`.

---

## First-Time Setup

```bash
bundle install
bin/rails db:create db:migrate db:seed   # prints generated admin password to stdout
bin/dev                                   # starts Rails + Tailwind watcher
```

Test suite: `bundle exec rspec`
