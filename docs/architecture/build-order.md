# Recommended Build Order: Estimating Software MVP

**Date:** 2026-04-01
**Author:** architect-agent

---

## Guiding Principles

1. Unblock blockers first. OQ-01 (markup level) is resolved in ADR-001. OQ-02 (line item UX) is conditionally resolved in ADR-005 pending estimator validation. Build the data layer before the UX layer so a UX pivot does not require schema changes.
2. Build the dependency spine before the branches. You cannot create an estimate without a client. You cannot create a line item without an estimate and a section. Build depth-first along the primary user journey.
3. Validate the core loop early. The sooner an estimator can log in, create a client, build an estimate, and see a total, the sooner you get real feedback. Every phase should end with something demoable.
4. Defer polish. PDF output, autocomplete, and drag-and-drop ordering are valuable but not required to validate the core workflow. Do them last.

---

## Phase 0: Foundation (Day 1 — not optional)

These are prerequisites for everything else. None are features; all are blockers.

- [ ] Uncomment `gem "bcrypt", "~> 3.1.7"` in Gemfile and run `bundle install`
- [ ] Add `gem "acts_as_list"` to Gemfile
- [ ] Create `docs/architecture/` directory (done — this file is in it)
- [ ] Confirm with shop owner: estimate number format (OQ-12), branding for PDF (OQ-09), client deletion policy (OQ-03)
- [ ] Schedule estimator validation session for Pattern C UX recommendation (OQ-02)

**Do not begin model work until bcrypt is in the bundle. `has_secure_password` will raise at runtime without it.**

---

## Phase 1: Authentication and User Management

**Why first:** Every other controller depends on `require_login`. Building auth first means all subsequent controllers start with the correct security posture rather than bolting it on afterward.

- [ ] Generate `User` model with migration (email, name, password_digest, timestamps)
- [ ] Add unique index on `users.email`
- [ ] Implement `has_secure_password` and email validations on User model
- [ ] Create `Authentication` concern in `ApplicationController`
- [ ] `SessionsController` (new, create, destroy) with login/logout views
- [ ] Add login/logout routes
- [ ] Seed one initial user in `db/seeds.rb`
- [ ] `UsersController` (index, new, create, edit, update) — all require login
- [ ] Unit tests: User model authentication, email uniqueness
- [ ] Integration test: POST /sessions with valid/invalid credentials
- [ ] Confirm: unauthenticated request to any route redirects to login

**Demoable:** Log in, log out, create a second user.

---

## Phase 2: Client and Contact CRUD

**Why second:** The `Estimate` model requires a `client_id`. Client data must exist before any estimate work can proceed. This phase is also the simplest CRUD in the system — a good place to establish patterns (controller structure, view partials, Turbo Frame conventions) before the more complex estimate editing.

- [ ] Generate `Client` model and migration (company_name, address, notes)
- [ ] Add index on `clients.company_name`
- [ ] Generate `Contact` model and migration (all fields including is_primary)
- [ ] Add index on `contacts.client_id`
- [ ] Add partial unique index: `contacts (client_id) WHERE is_primary = true`
- [ ] Client model: `has_many :contacts, dependent: :destroy`; `has_many :estimates, dependent: :restrict_with_error`
- [ ] Contact model: `belongs_to :client`; primary contact toggle logic (clear other primaries in same transaction)
- [ ] `ClientsController` (index, show, new, create, edit, update, destroy)
- [ ] Destroy action: render error (not redirect) if client has estimates
- [ ] `ContactsController` nested under clients (new, create, edit, update, destroy)
- [ ] Views: client list (alphabetical), client detail page with contacts, client form
- [ ] Unit tests: Client validation (company_name required), Contact primary uniqueness
- [ ] Integration tests: POST /clients, POST /clients/:id/contacts, DELETE /clients with estimates

**Demoable:** Create a client with two contacts, mark one as primary, edit, view list.

---

## Phase 3: Estimate Scaffold and Sections

**Why third:** Establishes the estimate shell and section structure before adding the complex line item layer on top of it. Estimate number generation and status enum are addressed here.

- [ ] Generate `Estimate` model and migration (all fields — see data-model-review.md; use `job_start_date` / `job_end_date` not `job_date`)
- [ ] Add all indexes on estimates (client_id, created_by_user_id, estimate_number unique, status, updated_at)
- [ ] Implement `estimate_number` auto-generation callback (before_validation on: :create) with transaction lock
- [ ] Status string enum on Estimate model
- [ ] Estimate model associations (belongs_to client, belongs_to created_by user)
- [ ] Generate `EstimateSection` model and migration (estimate_id, name, position, default_markup_percent)
- [ ] Add `acts_as_list scope: :estimate` to EstimateSection
- [ ] Add composite index on (estimate_id, position)
- [ ] EstimateSection model associations
- [ ] `EstimatesController` (index, show, new, create, edit, update, destroy)
- [ ] Estimates dashboard (list with number, client, title, status, updated_at; filter by status; search)
- [ ] `EstimateSectionsController` (new, create, edit, update, destroy) nested under estimates
- [ ] Section ordering: up/down controls (defer drag-and-drop to Phase 5)
- [ ] Section delete: warn + confirm before cascade (use Turbo confirm dialog)
- [ ] Estimate status change action (PATCH /estimates/:id/status)
- [ ] Unit tests: estimate number generation, status enum transitions
- [ ] Integration test: POST /estimates creates with auto-number; POST /estimate_sections

**Demoable:** Create an estimate for a client, add sections, reorder sections, change status.

---

## Phase 4: Line Items and Totals (Core Estimating Loop)

**Why fourth:** This is the heart of the application and the most technically complex phase. It builds on Phase 3 (sections exist) and requires ADR-001 (markup) and ADR-003 (totals) patterns to be followed precisely.

- [ ] Generate `LineItem` model and migration (all fields — see data-model-review.md including catalog_item_id and cost_type)
- [ ] Add `acts_as_list scope: :estimate_section` to LineItem
- [ ] Add all indexes (estimate_section_id, composite with position, catalog_item_id)
- [ ] LineItem model: `extended_cost` and `sell_price` computed methods (no stored columns)
- [ ] Create `EstimateTotalsCalculator` service object (app/services/)
- [ ] `LineItemsController` (new, create, edit, update, destroy) nested under estimate_sections
- [ ] Line item form partial with quantity × unit_cost = extended_cost display
- [ ] Stimulus controller: `line_item_calculator_controller.js` for in-form real-time calculation (Layer 1 — see ADR-003)
- [ ] Turbo Stream responses from create/update/destroy: replace line item row, section subtotal partial, estimate grand total partial (Layer 2 — see ADR-003)
- [ ] Named partials: `_line_item.html.erb`, `_section_subtotal.html.erb`, `_estimate_totals.html.erb`
- [ ] DOM IDs via Rails `dom_id` helper — document naming convention in code comments
- [ ] Section subtotal displayed in section header
- [ ] Estimate grand total displayed at bottom of estimate edit view
- [ ] Unit tests: LineItem extended_cost, sell_price; EstimateTotalsCalculator section and grand totals
- [ ] Integration test: PATCH /line_items returns Turbo Stream with updated totals

**Demoable:** Full estimate editing loop — add items, see totals update in real time, edit and delete items.

---

## Phase 5: Catalog and Autocomplete

**Why fifth:** The catalog improves UX but does not block the core loop. Phase 4 must be working and validated with real estimators before investing in autocomplete. If the estimator validation session (OQ-02) changes the UX to Pattern B, this phase changes significantly but the data layer from Phase 4 does not.

- [ ] Generate `CatalogItem` model and migration
- [ ] Add indexes on description and category
- [ ] `CatalogItemsController` (index, new, create, edit, update, destroy) — basic management UI
- [ ] Search endpoint: GET /catalog_items/search?q=term (returns JSON, requires login)
- [ ] Stimulus controller: `description_autocomplete_controller.js` (debounced fetch, dropdown, field pre-fill)
- [ ] Seed `db/seeds.rb` with catalog items extracted from Excel sharedStrings (see ADR-005)
- [ ] Wire autocomplete into line item form description field
- [ ] Unit test: CatalogItem search query
- [ ] End-to-end test: type description, select autocomplete suggestion, fields pre-fill

**Demoable:** Type "door" in description field, see matching catalog items, select one.

---

## Phase 6: Document Output (Print Views)

**Why sixth:** Output views are straightforward once the data model is solid. They are valuable to the estimators but do not affect any other feature's correctness.

- [ ] Create `layouts/print.html.erb` (no nav, no Turbo, bare HTML + print stylesheet link)
- [ ] Create `app/assets/stylesheets/print.css` with `@page` rules and print media styles
- [ ] Add `cost_sheet` action to `EstimatesController`; route: GET /estimates/:id/cost_sheet
- [ ] Cost sheet view: full detail (all columns including unit_cost, markup, sell_price)
- [ ] Add `client_pdf` action to `EstimatesController`; route: GET /estimates/:id/client_pdf
- [ ] Client PDF view: separate template — structurally omits unit_cost, markup_percent, extended_cost columns (do NOT use CSS hide — see ADR-002)
- [ ] "Print Cost Sheet" and "Print Client PDF" buttons on estimate show/edit page (open in new tab)
- [ ] Optional: small Stimulus controller that calls `window.print()` automatically when the print layout loads
- [ ] Confirm with shop owner: branding/logo for client PDF header (OQ-09), line-item vs. section-total detail level (OQ-05)
- [ ] Integration test: GET /estimates/:id/cost_sheet renders with correct columns; GET /estimates/:id/client_pdf renders without cost columns

**Demoable:** Click "Print Cost Sheet" — browser print dialog opens with full detail. Click "Print Client PDF" — shows client version with no internal costs.

---

## Phase 7: Polish and Hardening

Features that improve the experience but are not on the critical path. Schedule based on feedback from real use.

- [ ] Drag-and-drop reordering for sections and line items (Stimulus + SortableJS or Stimulus Sortable)
- [ ] Dashboard search (filter by client name, job title)
- [ ] Estimate list filter by status
- [ ] Bulk markup update on a section ("apply to all items")
- [ ] User password change form (self-service)
- [ ] `cost_type` column visibility in line item form (if the shop wants cost-category breakdown)
- [ ] Estimate duplication action ("Clone this estimate")
- [ ] End-to-end test: full estimate creation flow (Capybara)
- [ ] Performance review: check N+1 queries on estimates index and estimate edit view; add `includes` as needed

---

## Open Questions Blocking Specific Phases

| Question | Blocks | Status |
|----------|--------|--------|
| OQ-01: Markup level | Phase 4 | Resolved by ADR-001 |
| OQ-02: Pattern C UX validation | Phase 5 | Needs estimator session |
| OQ-03: Client deletion policy | Phase 2 | Recommend block — confirm |
| OQ-08: Job date single vs. range | Phase 3 | Resolved: use date range |
| OQ-09: Branding for client PDF | Phase 6 | Needed before Phase 6 ships |
| OQ-10: User invite flow | Phase 1 | Resolved by ADR-004: admin creates |
| OQ-12: Estimate number format | Phase 3 | Confirm EST-YYYY-NNNN with shop |

---

## Dependency Graph (simplified)

```
Phase 0 (Foundation)
  └── Phase 1 (Auth)
        └── Phase 2 (Clients)
              └── Phase 3 (Estimates + Sections)
                    └── Phase 4 (Line Items + Totals)  ← core loop
                          ├── Phase 5 (Catalog + Autocomplete)
                          └── Phase 6 (Print Views)
                                └── Phase 7 (Polish)
```
