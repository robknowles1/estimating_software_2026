# Estimating Software 2026

A web application that replaces a manually duplicated Excel estimating workflow for a millwork and finish-carpentry shop. Estimators can manage clients, build structured cost estimates, and produce printable internal cost sheets and client-facing proposals — all from a shared, multi-user environment.

## Prerequisites

- Ruby 4.0.1 (see `.ruby-version`)
- PostgreSQL 9.5 or later
- Bundler (`gem install bundler`)

## Setup

```bash
# 1. Clone the repository
git clone <repo-url>
cd estimating_software_2026

# 2. Install gems
bundle install

# 3. Create and migrate the database
bin/rails db:create db:migrate
```

`db/seeds.rb` is currently empty. The first user must be created via the Rails console:

```bash
bin/rails console
# Then in the console:
User.create!(name: "Your Name", email: "you@example.com", password: "choose-a-strong-password", password_confirmation: "choose-a-strong-password")
```

## Running the Application

```bash
bin/rails server
```

The app starts on `http://localhost:3000`. All routes require login; you will be redirected to the login page automatically.

## Testing

```bash
# Run the full test suite
bin/rails test

# Run system tests (requires Chrome)
bin/rails test:system
```

The test suite uses Rails' built-in Minitest. System tests use Capybara with Selenium WebDriver.

## Deployment

The application is deployed as a Docker container using [Kamal](https://kamal-deploy.org).

```bash
# First-time setup
kamal setup

# Deploy a new version
kamal deploy
```

Kamal configuration lives in `.kamal/`. Secrets are managed via `.kamal/secrets` (not committed to the repository).

**Production requirements:**
- `RAILS_MASTER_KEY` — required to decrypt credentials
- `ESTIMATING_SOFTWARE_2026_DATABASE_PASSWORD` — PostgreSQL password for the production user
- TLS must be terminated at the proxy level. `config.force_ssl = true` is enabled in production. Ensure the Kamal config includes a valid SSL certificate.

The production database runs four PostgreSQL databases (primary, cache, queue, cable) as defined in `config/database.yml`.

## Architecture

Rails 8.1 application using Hotwire (Turbo + Stimulus) for real-time interactions and browser print CSS for document output. No API layer — standard Rails MVC throughout.

**Core domain models:** `User`, `Client`, `Contact`, `Estimate`, `EstimateSection`, `LineItem`, `CatalogItem`

**Key architectural decisions:**
- Markup is stored per `LineItem`; `EstimateSection` provides a `default_markup_percent` that pre-fills new items at creation (ADR-001)
- Document output uses browser print CSS with two separate controller actions and templates (`cost_sheet`, `client_pdf`) — no PDF generation gem (ADR-002)
- Real-time totals use a two-layer approach: Stimulus for in-form arithmetic before save, Turbo Streams to update section and grand total partials after save (ADR-003)
- Authentication via `has_secure_password` with session-based auth; no Devise or OAuth; any logged-in user can create other users (ADR-004)
- Line item entry uses Pattern C: freeform description with catalog autocomplete (ADR-005, pending estimator validation)
- All totals math lives in `app/services/estimate_totals_calculator.rb` — not in models, views, or helpers

See `docs/architecture/` for Architecture Decision Records and the full data model review.

See `docs/specs/` for phase-by-phase implementation specs.

### Build Order

```
Phase 0 — Foundation (bcrypt + acts_as_list gems)
  Phase 1 — Authentication and User Management
    Phase 2 — Client and Contact Management
      Phase 3 — Estimate Scaffold and Sections
        Phase 4 — Line Items and Real-Time Totals  (core loop)
          Phase 5 — Catalog and Autocomplete
          Phase 6 — Document Output (print views)
            Phase 7 — Polish and Hardening
```
