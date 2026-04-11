# Spec: Estimating Foundation — Data Layer and Materials Price Book

**ID:** SPEC-010
**Status:** done
**Priority:** high
**Created:** 2026-04-10
**Author:** pm-agent

---

## Summary

This phase rebuilds the estimating data layer from scratch, replacing the incorrect EstimateSection/EstimateMaterial/CatalogItem model with the flat, spreadsheet-accurate model documented in ADR-008. It delivers: all migrations to drop old tables and create the new schema; the `Material` model with per-estimate slot seeding; the updated `Estimate` model with new fields and callbacks; and the materials price book UI where an estimator can enter quote prices for all material slots before building the product grid. No line item entry is in scope for this phase. After this phase, a developer can create an estimate, have its full material slot list seeded automatically, enter prices for each slot, and see `cost_with_tax` recalculate on save.

## User Stories

- As an estimator, I want to create a new estimate for a client so that I can start building the cost breakdown.
- As an estimator, I want to see all material slots (plywood types, hardware) pre-populated when I open a new estimate so that I do not have to define them manually.
- As an estimator, I want to enter a quote price for each material slot so that line items can calculate material costs against real job prices.
- As an estimator, I want the tax-adjusted cost per material slot to be calculated for me so that I do not have to do that arithmetic manually.
- As an estimator, I want to set the tax rate on an estimate and have all material costs update automatically so that my price book stays accurate if rates change.
- As an estimator, I want to see the full estimate page without a sidebar so that every pixel is available for estimate data.

## Acceptance Criteria

1. Given a logged-in user creates a new estimate by selecting an existing client and providing a job title, the estimate is saved in "draft" status with an auto-generated estimate number in the format `EST-YYYY-NNNN`.
2. Given a new estimate is created, the `tax_exempt` boolean on the estimate is copied from the client's `tax_exempt` field at creation time and stored independently on the estimate record.
3. Given a new estimate is created, all material slots defined in `Material::SLOTS` are seeded as `Material` records for that estimate in a single `insert_all` call, each with `quote_price: 0` and `cost_with_tax: 0`.
4. Given an estimate's materials price book page, all seeded slots are displayed grouped by category (Sheet Goods, then Hardware), with each slot's `slot_key`, `description` field, `quote_price` input, and calculated `cost_with_tax` displayed.
5. Given an estimator saves a quote price for one or more material slots, `cost_with_tax` for each updated slot is recalculated as `quote_price * (1 + estimate.tax_rate)` and persisted before the save completes.
6. Given an estimator updates the `tax_rate` on an estimate and saves it, all `cost_with_tax` values for that estimate's materials are recalculated via a single SQL update — no N+1 per-record callbacks.
7. Given an estimate with `tax_exempt: true`, all `cost_with_tax` values equal `quote_price` (no tax applied), regardless of the `tax_rate` value.
8. Given the estimate show page, a persistent button or link in the estimate header navigates to the materials price book at all times.
9. Given the estimate show page, if no material slot has a non-zero `quote_price`, a prominent banner encourages the estimator to set up material costs first, with a direct link to the price book. The banner is dismissible or disappears once at least one price is entered.
10. Given the estimate layout, no sidebar is rendered. A slim top bar displays estimate number, client name, status badge, and a "Back to Estimates" link.
11. Given an estimate form submitted without a client, a validation error is shown and no record is saved.
12. Given an estimate form submitted without a title, a validation error is shown and no record is saved.
13. Given the estimates index page, estimates are listed with estimate number, client name, title, status, and last-modified date.

## Technical Scope

### Data / Models

#### Migrations (single batch on the feature branch — execute in order)

1. Drop `catalog_items`, `estimate_sections`, and `estimate_materials` tables.
2. Drop and recreate `line_items` with the new schema (columns listed in ADR-008 schema section). All material_id FK columns use `ON DELETE SET NULL`. Indexes: `(estimate_id)`, `(estimate_id, position)`.
3. Modify `estimates`: add `tax_rate decimal(5,4) NOT NULL default 0.08`, `tax_exempt boolean NOT NULL default false`, `install_travel_qty decimal(8,2)`, `delivery_qty decimal(8,2)`, `delivery_rate decimal(10,2) default 400`, `per_diem_qty decimal(8,2)`, `per_diem_rate decimal(10,2) default 65`, `hotel_qty decimal(8,2)`, `airfare_qty decimal(8,2)`, `equipment_cost decimal(12,2)`, `countertop_quote decimal(12,2)`. Change defaults: `installer_crew_size default 2`, `delivery_crew_size default 2`, `pm_supervision_percent default 4.00`, `profit_overhead_percent default 10.00`.
4. Fix TD-01: `change_column :estimates, :created_by_user_id, :bigint` and remove `default: 0`.
5. Create `materials` table: `id bigint PK`, `estimate_id bigint NOT NULL FK → estimates ON DELETE CASCADE`, `slot_key string NOT NULL`, `category string NOT NULL`, `description string`, `quote_price decimal(12,4) NOT NULL default 0`, `cost_with_tax decimal(12,4) NOT NULL default 0`, `created_at`, `updated_at`. Unique index: `(estimate_id, slot_key)`.
6. Update `db/seeds.rb`: update `LaborRate` seed rates to match the spreadsheet (detail $65, mill $100, assembly $45, customs $65, finish $75, install $80). Remove any `EstimateMaterial`, `EstimateSection`, `CatalogItem` seed code.

#### Models to delete
- `app/models/estimate_section.rb`
- `app/models/estimate_material.rb`
- `app/models/catalog_item.rb`

#### `Material` (new model)
- `belongs_to :estimate`
- `before_save :compute_cost_with_tax` — sets `cost_with_tax = estimate.tax_exempt? ? quote_price : quote_price * (1 + estimate.tax_rate)`. Requires `estimate` to be preloaded — do not allow this callback to fire a separate query.
- `Material::SLOTS` — ordered array of hashes as defined in ADR-008. This list is provisional; developer must verify against the actual spreadsheet before writing the seed callback.
- Validates: `slot_key` presence; `quote_price` numericality `>= 0`.

#### `Estimate` (updated model)
- Remove `has_many :estimate_sections`, `has_many :estimate_materials`, `has_many :catalog_items`.
- Add `has_many :materials, dependent: :destroy`.
- Add `has_many :line_items, dependent: :destroy, -> { order(:position) }`.
- `before_create :copy_tax_exempt_from_client` — sets `self.tax_exempt = client.tax_exempt`.
- `after_create :seed_materials` — calls `Material.insert_all(Material::SLOTS.map { ... })` with `estimate_id` and defaults. Must run after the record is fully persisted so `tax_rate` is available.
- `after_save :recalculate_material_costs, if: :saved_change_to_tax_rate?` — issues a single SQL update: `materials.update_all("cost_with_tax = quote_price * (1 + #{tax_rate})")` with appropriate handling for `tax_exempt`.
- `after_save :recalculate_material_costs, if: :saved_change_to_tax_exempt?` — same recalculation trigger.
- Validates: `title` presence; `client_id` presence; `tax_rate` numericality.
- Existing `estimate_number` generation logic (FOR UPDATE lock) is unchanged.

### API / Logic

- `EstimatesController`: `index`, `show`, `new`, `create`, `edit`, `update` — all require login. `create` sets `created_by_user_id` from `current_user.id`. Strong params updated for new estimate fields (tax_rate, tax_exempt, miles_to_jobsite, installer_crew_size, delivery_crew_size, on_site_time_hrs, pm_supervision_percent, profit_overhead_percent — but NOT the job-level cost qty fields, which are SPEC-012 scope).
- `MaterialsController` (new, replaces `EstimateMaterialsController`): scoped to a parent estimate. Actions: `edit`, `update`. Edit renders all slots for the estimate in a single form. Update uses `materials_attributes` (accepts_nested_attributes_for) or a bulk-update pattern — developer's choice, but a single form POST for all slots is required; do not require individual per-slot requests.
- Routes: `resources :estimates do; resource :materials, only: [:edit, :update]; end`. Note: `resource` (singular) because there is one price book per estimate.

### UI / Frontend

- Estimate layout: `app/views/layouts/estimate.html.erb` — a separate layout file. No sidebar. Slim top bar with estimate number (bold), client name, status badge, "Materials" button linking to the price book, "Back to Estimates" link. All estimate pages use this layout.
- Estimates index (`/estimates`): table with estimate number, client name, title, status badge, last-modified date. Each row links to estimate show.
- Estimate show page: currently a placeholder — displays estimate header (number, client, title, status) and a "Line Items" section that renders as empty until SPEC-011. Shows the materials setup banner if no material has a non-zero `quote_price`.
- Materials price book (`/estimates/:id/materials/edit`): a single-page form. Sheet goods and hardware rendered in separate labeled groups. Each slot row: slot label (human-readable, from `Material::SLOTS` label or slot_key), description text field, quote price decimal input, cost_with_tax displayed as read-only (updated on save, not real-time in this phase). A single "Save Prices" submit button for the entire form.
- All monetary values formatted with `number_to_currency`. All i18n strings in `config/locales/en.yml`; no hardcoded strings in views.
- Error states: validation errors rendered inline. Empty state on estimate show: "No line items yet — add your first product after setting up material costs."

### Background Processing
- None.

## Test Requirements

### Unit Tests

- `Material`: `compute_cost_with_tax` sets `cost_with_tax = quote_price * (1 + tax_rate)` when `tax_exempt` is false.
- `Material`: `compute_cost_with_tax` sets `cost_with_tax = quote_price` when estimate `tax_exempt` is true.
- `Material`: validates presence of `slot_key`; validates numericality of `quote_price >= 0`.
- `Estimate`: `copy_tax_exempt_from_client` copies client's `tax_exempt` on create only, not on update.
- `Estimate`: `seed_materials` creates exactly `Material::SLOTS.length` material records after estimate creation.
- `Estimate`: `recalculate_material_costs` updates all material `cost_with_tax` values when `tax_rate` changes.
- `Estimate`: `recalculate_material_costs` sets all `cost_with_tax` to `quote_price` when `tax_exempt` changes to true.
- `Estimate`: validates presence of `title` and `client_id`.
- `Estimate`: `assign_estimate_number` generates `EST-YYYY-NNNN` format on create.

### Integration Tests

- `POST /estimates` with valid params: creates estimate, seeds materials, redirects to estimate show with materials banner visible.
- `POST /estimates` without a client: returns 422, shows validation error.
- `GET /estimates/:id/materials/edit`: renders all material slots grouped by category.
- `PATCH /estimates/:id/materials`: updates quote_price values, recalculates cost_with_tax, redirects back to materials edit with success flash.
- `PATCH /estimates/:id` with new `tax_rate`: recalculates all material `cost_with_tax` values.
- `GET /estimates`: lists estimates with correct columns; requires login (redirect to login if not authenticated).

### End-to-End Tests

- Create a new estimate for an existing client. Confirm: estimate number generated, materials banner appears, all slots visible in the price book.
- Enter quote prices for three material slots, save. Confirm: cost_with_tax values are displayed correctly on the materials edit page.
- Change the estimate tax rate, save. Confirm: all cost_with_tax values update to reflect the new rate.

## Out of Scope

- Line item entry and the product grid (SPEC-011).
- Job-level cost fields UI form (SPEC-012) — columns are added to the schema in this phase but no edit form is built.
- Real-time cost_with_tax update in the materials form as the user types (post-MVP; save-and-recalculate is sufficient for now).
- Estimate deletion (deferred — listed in pre-production tech debt).
- Estimate duplication / cloning (Phase 7 polish).
- PDF output (SPEC-013).
- The `delivery_rate` and `per_diem_rate` fields are added to the schema here but are not surfaced in any form until SPEC-012.

## Open Questions

- **OQ-A (from ADR-008, blocking):** Verify the `Material::SLOTS` list against the actual Excel spreadsheet before writing the seed callback. The ADR list is provisional. Developer must confirm slot count and slot_key identifiers with the shop owner or the actual template before shipping this spec.
- **OQ-B (from ADR-008, non-blocking):** Is banding a type-only selection per product row (no quantity), or does the shop enter a linear-foot quantity? ADR-008 defaults to type-only. No line items exist in this phase — but the answer affects the SPEC-011 schema and should be confirmed before SPEC-011 begins.
- **OQ-C (non-blocking):** Should `cost_with_tax` in the materials edit form update in real time as the user types a quote price (Stimulus controller), or only on save? Recommendation is save-only for this phase; can be upgraded in polish phase.

## Dependencies

- SPEC-004 (Phase 2 — Clients) must be done. Estimate creation requires a `client_id`, and `copy_tax_exempt_from_client` reads from the client record.
- SPEC-002 (Phase 0 — Foundation): `acts_as_list` gem must be in the bundle (used in SPEC-011 but line_items table is created here).
- ADR-008 is the authoritative schema reference for this phase. Any deviation must be documented in a new ADR or an ADR amendment before the PR is opened.

---

## Technical Guidance

**Reviewed by:** architect-agent (via ADR-008)
**Relevant ADRs:** ADR-008 (supersedes ADR-005, ADR-006, ADR-007 for estimating scope)

---

### Estimate layout file

Create `app/views/layouts/estimate.html.erb` as a copy of `application.html.erb` with the sidebar removed and a slim top bar added. Add a `layout "estimate"` declaration to `EstimatesController` (and `MaterialsController`, `LineItemsController`, etc.). Do not modify `application.html.erb`. Authenticated pages outside the estimating module must continue to use the sidebar layout.

---

### Material seeding — use insert_all, not individual saves

The `seed_materials` callback must use `Material.insert_all` (or `insert_all!`), not `Material.create` in a loop. Inserting ~50 rows per estimate via individual saves is unnecessary overhead and fires the `before_save :compute_cost_with_tax` callback 50 times. With `insert_all`, all rows are inserted in one SQL statement and `cost_with_tax` can default to zero at seed time (quote_price is also zero). The recalculation callback on the Material model is not invoked by `insert_all` — this is the correct behavior; there is nothing to calculate when quote_price is zero.

---

### skip_material_seeding factory trait

The `after_create :seed_materials` callback will fire in all test contexts unless suppressed. Add a `:skip_material_seeding` trait to the `:estimate` factory:

```ruby
trait :skip_material_seeding do
  after(:create) { |e| e.materials.delete_all }
  # or: before(:create) { allow_any_instance_of ... } — prefer the delete_all approach
end
```

Most model and request specs should use this trait unless they specifically test material seeding behavior. System specs that test the full estimate creation flow should NOT use this trait.

---

### tax_rate recalculation — single SQL update

When `tax_rate` or `tax_exempt` changes, recalculate via SQL, not Ruby iteration:

```ruby
# tax_exempt = false
materials.update_all("cost_with_tax = ROUND(quote_price * (1 + #{connection.quote(tax_rate)}), 4)")
# tax_exempt = true
materials.update_all("cost_with_tax = quote_price")
```

Do not call `material.save!` in a loop. The goal is one UPDATE statement for all materials on the estimate.

---

### Slot label display

`Material::SLOTS` entries may have an optional `label` key (e.g., `label: "1/4\" MEL"`). If present, display the label; if absent, display the `slot_key`. A helper method on `Material` or a view helper `material_label(slot)` is appropriate — do not put this logic inline in the view partial.
