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

# 3. Create, migrate, and seed the database
bin/rails db:create db:migrate db:seed
```

`bin/rails db:seed` creates a development admin user and **prints the generated password to stdout** — copy it before the terminal scrolls. Sign in at `http://localhost:3000` and change the password via Users → Edit after first login.

> **Production:** `db/seeds.rb` is gated to `Rails.env.development?` and will not run in production. Create the first production user via the Rails console with a strong password of your choosing.

## Running the Application

```bash
bin/dev
```

`bin/dev` starts both the Rails server and the Tailwind CSS watcher via foreman. The app is available at `http://localhost:3000`.

The app starts on `http://localhost:3000`. All routes require login; you will be redirected to the login page automatically.

## Testing

```bash
# Run the full test suite
bundle exec rspec

# Run a specific file
bundle exec rspec spec/models/user_spec.rb

# Run system specs only (requires Chrome)
bundle exec rspec spec/system
```

The test suite uses RSpec with FactoryBot, Shoulda Matchers, and DatabaseCleaner. System specs use Capybara with Selenium (headless Chrome).

## Deployment

The application is deployed as a Docker container using [Kamal 2](https://kamal-deploy.org). Container images are pushed to GitHub Container Registry (`ghcr.io`).

See **[docs/deployment/digital_ocean.md](docs/deployment/digital_ocean.md)** for the full runbook, including first-time Droplet bootstrap, required GitHub secrets, and troubleshooting.

### Automatic deploys

Every merge to `main` triggers the `deploy_staging` job in `.github/workflows/ci.yml` (after all CI checks pass), which builds a new image and deploys it to the staging Droplet at `64.23.238.38:3000`.

### Manual deploy (staging)

```bash
export RAILS_MASTER_KEY=$(cat config/master.key)
export KAMAL_REGISTRY_PASSWORD=<github-pat-with-write-packages>
export ESTIMATING_SOFTWARE_2026_DATABASE_PASSWORD=<db-password>
export SEED_ADMIN_PASSWORD=<admin-password>

# First time only — bootstraps Docker + Postgres on the Droplet
bin/kamal setup -d staging

# Subsequent deploys
bin/kamal deploy -d staging
```

### Required secrets

| Secret | Purpose |
|--------|---------|
| `RAILS_MASTER_KEY` | Decrypts `config/credentials.yml.enc` |
| `KAMAL_REGISTRY_PASSWORD` | GitHub PAT with `write:packages` scope — authenticates to `ghcr.io` |
| `ESTIMATING_SOFTWARE_2026_DATABASE_PASSWORD` | Postgres password for the app user |
| `SEED_ADMIN_PASSWORD` | Initial admin account password on first deploy |
| `DEPLOY_SSH_PRIVATE_KEY` | Private key for SSH access to the Droplet (set in GitHub Actions secrets) |

Set these under **Settings → Secrets and variables → Actions** in the GitHub repo.

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
