# ADR-007: Phase 4 Data Model Review

**Status:** accepted
**Date:** 2026-04-05
**Deciders:** architect-agent


## Context

Phase 4 (SPEC-006) introduces the core estimating loop: `EstimateMaterial`, `LineItem`, job-level settings on `Estimate`, `quantity` on `EstimateSection`, and an expanded `EstimateTotalsCalculator`. This is the largest schema change in the project so far and several of the decisions are hard to reverse once estimates are in production. This ADR records findings from the architect review and the decisions required before development starts.

The current schema (as of Phase 3) contains: `users`, `clients`, `contacts`, `estimates`, `estimate_sections`. There is no `line_items` table yet — it will be created in Phase 4.

---

## Decision

The Phase 4 data model as specified in SPEC-006 (revised 2026-04-05) is **approved to proceed** with the following modifications and clarifications documented below. No structural blockers exist. One open question (OQ-13, MVP labor rate) must be resolved by the developer before writing migrations — both options are acceptable; a seeded `LaborRate` table is recommended and that recommendation is reaffirmed here.

---

## Findings by Review Area

### 1. EstimateMaterial Auto-Seed — after_create Callback

**Finding: The after_create callback approach is correct. Use it with a single insert call, not 36 individual creates.**

The spec proposes seeding 36 `EstimateMaterial` records via an `after_create` callback on `Estimate`. This is the right mechanism for several reasons:
- Estimates are created infrequently (one per job); 36 inserts is not a performance concern.
- Seeding in the same transaction as estimate creation means the materials grid is always consistent — there is no window where an estimate exists with a partially-populated or empty materials grid.
- Lazy seeding (create on first access) is rejected because it would require nil-handling throughout the calculator and the materials edit form, and it makes the grid unpredictable for the user.

**Correctness concern — use `insert_all` to avoid 36 round-trips:**

The spec's example code calls `estimate_materials.create!` in a nested loop, which fires 36 individual INSERT statements. This is acceptable but unnecessary. Use `EstimateMaterial.insert_all` with a prepared array instead:

```ruby
MATERIAL_CATEGORIES = %w[pl pull hinge slide banding veneer].freeze

after_create :seed_material_slots

private

def seed_material_slots
  rows = MATERIAL_CATEGORIES.flat_map do |cat|
    (1..6).map do |slot|
      {
        estimate_id:    id,
        category:       cat,
        slot_number:    slot,
        price_per_unit: 0,
        created_at:     Time.current,
        updated_at:     Time.current
      }
    end
  end
  EstimateMaterial.insert_all(rows)
end
```

`insert_all` fires one INSERT with 36 value tuples. It does not invoke model callbacks or validations on the individual records — which is intentional here since all 36 rows are system-generated with known-valid values. If model-level callbacks are later added to `EstimateMaterial`, revisit this.

**Test isolation concern:** `after_create` callbacks run in all test contexts including FactoryBot factories. Any factory that creates an `Estimate` will also create 36 `EstimateMaterial` records. For specs that do not need the materials, this is harmless but adds rows. For the `EstimateMaterial` uniqueness spec, the factory must not double-create. To avoid this, either:
  - Use `create_list` only in specs that test the material grid, or
  - Add a `skip_material_seeding` trait to the factory: `trait :skip_material_seeding { after(:build) { |e| e.define_singleton_method(:seed_material_slots) { nil } } }`

The second approach is more robust in a test suite that creates many `Estimate` records.

**Not a blocker.** Developer chooses the approach; the `skip_material_seeding` factory trait is recommended.

---

### 2. Two-Pass Burden Calculator

**Finding: Formula is correct. BigDecimal usage rules need clarification. One structural issue with the Result struct.**

**Formula correctness:** The two-pass algorithm in ADR-006 is mathematically correct and matches the spreadsheet model:
- Pass 1 sums `non_burdened` per section and accumulates `grand_total_non_burdened`.
- Pass 2 computes `section_travel_share = total_travel_cost × (section_non_burdened / grand_total_non_burdened)` and then `burdened = (non_burdened × burden_multiplier) + section_travel_share`.
- Guard for `grand_total_non_burdened = 0` is specified and must be implemented.
- `burden_multiplier = (1 + profit_overhead_percent / 100) × (1 + pm_supervision_percent / 100)` is multiplicative, matching the spreadsheet. This is correct.

**BigDecimal input sourcing:** The calculator will receive values from ActiveRecord decimal columns. Rails maps `decimal` columns to `BigDecimal` automatically — no explicit `BigDecimal()` conversion is needed when reading from the database. However, when reading from the `Estimate` model attributes (e.g., `estimate.profit_overhead_percent`), confirm the column type is `decimal` not `float` in the migration. If the migration uses `t.decimal`, AR returns `BigDecimal`. If anyone uses `t.float`, all burden arithmetic becomes IEEE 754 floating-point, which is wrong for financial calculations. This must be checked at migration time.

**Result struct — `alternate_total` key inconsistency:** SPEC-006 defines `alternate_total` with keys `{ non_burdened: X, burdened: Y }` but ADR-006 defines it with keys `{ non_burdened: X, sell: Y }`. These must be unified before implementation. The correct choice is `{ non_burdened: X, sell: Y }` because alternates do not go through the burden calculation — they have a simple `sell_price` derived from `markup_percent`. The term "burdened" applied to an alternate item is a misnomer. **The spec must be updated: `alternate_total` uses key `sell:`, not `burdened:`.**

**Mileage rate configuration:** ADR-006 recommends storing `MILEAGE_RATE` in a YAML config loaded via `Rails.application.config`. The correct home is `config/initializers/burden_constants.rb`:

```ruby
# config/initializers/burden_constants.rb
Rails.application.config.burden_constants = {
  mileage_rate:       BigDecimal("0.67"),
  round_trip_factor:  2
}.freeze
```

Reference in the calculator as `Rails.application.config.burden_constants[:mileage_rate]`. Do not define constants inside the `EstimateTotalsCalculator` class — they make the rate untestable without stubbing constants.

**Calculator preload requirement:** The `.includes` clause for N+1 prevention must include `LaborRate` if labor rate lookup is not already cached. Since `LaborRate.rate_for` hits the database, the calculator must either:
  a. Accept a pre-fetched `labor_rates` hash keyed by category, or
  b. Cache the result of `LaborRate.all.index_by(&:labor_category)` at the start of `.call` (one query, then in-memory lookups).

Option (b) is simpler. Implement as:

```ruby
def call
  @labor_rates = LaborRate.all.index_by(&:labor_category)
  # ... rest of calculator
end
```

Then reference `@labor_rates[category]&.hourly_rate || BigDecimal("0")` instead of calling `LaborRate.rate_for` per line item, which would fire one query per labor line item.

---

### 3. EstimateSection quantity Field

**Finding: Semantically sound. One migration concern. Validation must be tighter than specified.**

Adding `quantity decimal(10,2) not null default 1` to `estimate_sections` is the right approach. Storing the cabinet count on the section (not on each line item) is correct because all line items in the section share the same quantity multiplier.

**Migration concern — existing sections:** The migration adds the column with `default: 1`. All existing `EstimateSection` rows will receive `quantity = 1`. This is the correct default (one cabinet of this type), and Phase 3 data will not be broken.

**Validation — minimum of 1, not 0:** The spec says "validates numericality of quantity (>= 1)." This is correct but the spec also uses `decimal(10,2)` which allows fractional values. A quantity of 0.5 sections is not meaningful for a cabinet count. The validator should be:

```ruby
validates :quantity, numericality: { greater_than: 0 }
```

Not `greater_than_or_equal_to: 0` (which would allow 0 sections and produce divide-by-zero in `burdened_unit_price`). Not `only_integer: true` — the spec leaves the column as decimal, which is reasonable if the shop ever estimates partial cabinet replacements. The guard in `burdened_unit_price` against `quantity = 0` (from ADR-006) must remain even with this validation, because a section could theoretically be calculated before it is validated.

**Semantics compatibility with Phase 3:** Phase 3 built `EstimateSection` as a named group with a `default_markup_percent`. Adding `quantity` changes what a section represents — from "a grouping of line items" to "a cabinet type with a count." This is a legitimate semantic change but it means:
- The `default_markup_percent` column is now partially vestigial for the main burden calculation. It remains relevant for alternate/buy-out items within the section.
- Phase 3 views that render sections need to show `quantity` where appropriate. This is a UI addition, not a model incompatibility.

No rollback risk.

---

### 4. LineItem Component Fields — String-Discriminated Polymorphism

**Finding: The polymorphic-via-strings approach (not STI, not separate tables) is correct for this domain. One naming concern. One index gap.**

The proposed design uses string columns (`line_item_category`, `component_type`, `labor_category`) as discriminators that determine which fields are used for a given row. This is sometimes called a "wide table" approach.

**Why not STI:** STI would require a `type` column and subclasses. The subclasses would share all columns (as in the proposed design) but would add the overhead of Ruby subclassing, which does not simplify the `extended_cost` routing logic here. STI also interacts poorly with `acts_as_list`, which scopes by the association — STI would need additional configuration. Rejected.

**Why not separate tables:** Separate tables for material line items and labor line items would require a polymorphic association for the section-to-line-items relationship, or a through-table. Turbo Stream DOM ID generation and `acts_as_list` both assume a single `line_items` table. Rejected.

**The current approach is correct.** The `extended_cost` routing method (strategy pattern from the existing Technical Guidance section) cleanly handles the three computation paths without conditional spaghetti.

**Naming concern — `quantity` vs. `component_quantity`:** The existing `line_items` table will have BOTH a `quantity` column (from the original design, for buy-out/freeform items) AND a new `component_quantity` column (for material line items). Having two quantity-like columns on the same model is a code smell and a source of future confusion. The options are:

  - (a) Rename the existing `quantity` column to `freeform_quantity` to make the distinction explicit — **this is a breaking change to the Phase 3 data model spec, but the line_items table does not exist yet**, so it can be done cleanly.
  - (b) Leave both columns and document clearly that `component_quantity` is used for material items and `quantity` is used for buy-out/freeform items.

**Recommendation: Option (a) — rename the column to `freeform_quantity` before creating the table.** Since `line_items` does not yet exist in the schema, this is not a migration rename; it is simply naming the column correctly from the start. The `extended_cost` method for the freeform path becomes `freeform_quantity * unit_cost`, which is unambiguous. Update the spec and data-model-review.md accordingly.

If the team prefers Option (b), document the convention prominently in the model and add a model-level comment. **This decision must be made before writing the migration.**

**Index gap:** The spec calls for an index on `line_item_category`. This is only useful if queries filter by category across the entire `line_items` table. The more common query is "all line items in a section" — already covered by the existing `estimate_section_id` index. The `line_item_category` index is low-value for a shop with < 10,000 line items total. It does not hurt to add, but it should not be considered load-bearing. More important: add a composite index `(estimate_section_id, line_item_category)` if the calculator ever queries sections for only material or only labor items separately. For Phase 4 the calculator loads all line items and filters in Ruby, so the composite index is not needed yet.

**FK on `estimate_material_id`:** The FK from `line_items` to `estimate_materials` must be declared with `optional: true` in the model and `ON DELETE SET NULL` in the database FK declaration. If an `EstimateMaterial` slot is deleted (unlikely but possible if an estimate is restructured), the line item should not be cascade-deleted. Use:

```ruby
add_foreign_key :line_items, :estimate_materials, on_delete: :nullify
```

This mirrors the `catalog_item_id` FK behavior.

---

### 5. OQ-13: MVP Labor Rate Approach — RESOLVED

**Decision: Use a seeded `LaborRate` model with a class method. Do not use a constant.**

A constant requires a code deploy to change the rate. A seeded `LaborRate` table allows the shop owner to change rates via an admin form (Phase 5 introduces this UI, but the table and data model can be created in Phase 4 to unblock the calculator).

**Create the `LaborRate` model in Phase 4 migrations, seeded in `db/seeds.rb`.** Phase 5 adds the admin UI. The Phase 4 MVP calculator uses `LaborRate.rate_for(category)` with a fallback:

```ruby
# app/models/labor_rate.rb
class LaborRate < ApplicationRecord
  CATEGORIES = %w[detail mill assembly customs finish install].freeze

  validates :labor_category, presence: true, uniqueness: true,
            inclusion: { in: CATEGORIES }
  validates :hourly_rate, numericality: { greater_than_or_equal_to: 0 }

  class NotFound < StandardError; end

  def self.rate_for(category)
    find_by(labor_category: category)&.hourly_rate ||
      raise(NotFound, "No labor rate found for category: #{category}")
  end
end
```

Seed file:

```ruby
# db/seeds.rb (additions for Phase 4)
{
  "detail"   => 55,
  "mill"     => 55,
  "assembly" => 55,
  "customs"  => 65,
  "finish"   => 60,
  "install"  => 70
}.each do |category, rate|
  LaborRate.find_or_create_by!(labor_category: category) do |lr|
    lr.hourly_rate = rate
  end
end
```

Rates shown are illustrative defaults — the shop owner must confirm actual rates before first production use. This is not a code blocker.

---

### 6. Overall Data Model Integrity

**Finding: The model correctly captures the shop's workflow. Two structural concerns noted below.**

The core hierarchy `Estimate → EstimateSection (quantity) → LineItem (component_type | labor_category → EstimateMaterial | LaborRate)` maps directly to how the Excel spreadsheet is structured: a section is a cabinet type with a count, and its line items are the component costs per cabinet. This is the right model.

**Concern A — `catalog_item_id` FK table mismatch (BLOCKER):**

The existing `line_items` data model (from data-model-review.md) has `catalog_item_id` pointing to a `catalog_items` table. Phase 5 (SPEC-007) supersedes `CatalogItem` with `MaterialCatalogItem` in a `material_catalog_items` table. Phase 4 creates `estimate_materials` with a `catalog_item_id` column that is supposed to reference `material_catalog_items` (per SPEC-007 note: "Note: EstimateMaterial#catalog_item_id references material_catalog_items, not a separate catalog_items table").

There is no `catalog_items` table in the current schema — Phase 3 did not build it. This means:
- The `catalog_item_id` FK on `line_items` (from the Phase 0 design) was planned but never implemented.
- Phase 4 must decide: add the FK pointing to `material_catalog_items` (Phase 5's table) now, or leave it nullable with no FK constraint until Phase 5 creates the table.

**Decision: In Phase 4, add `catalog_item_id` and `estimate_material.catalog_item_id` as nullable integer columns with NO foreign key constraint yet.** The FK constraint will be added in Phase 5 when `material_catalog_items` is created. This is cleaner than creating a placeholder `catalog_items` table that will be renamed or dropped. Document this explicitly in the Phase 4 migration comment.

**Concern B — `default_markup_percent` on EstimateSection is vestigial for main items:**

`EstimateSection#default_markup_percent` was introduced in ADR-001 for the original per-line-item markup model. Under the burden model (ADR-006), main cabinet items do not use `markup_percent`. The column is now only relevant as a default for alternate and buy-out items within the section. It should be retained — removing it is a breaking change to the already-delivered Phase 3 spec — but its purpose should be clarified in the model comment.

**Concern C — hours_per_unit stored on LineItem vs. labor rate lookup:**

`LineItem#hours_per_unit` stores hours per cabinet. `labor_rate` is looked up at calculation time from `LaborRate`. This is correct — the hours are job-specific (this cabinet takes 0.375 assembly hours) while the rate is company-wide. Do not denormalize the rate onto the line item. If rates change between estimate creation and recalculation, the burdened total will update automatically on next load — which is the intended behavior.

---

### 7. Migration Ordering

The Phase 4 migrations must be created and run in the following order. Rails uses the timestamp prefix to sequence migrations; ensure each migration file's timestamp is later than its dependency.

```
1. create_labor_rates
   — No dependencies. New table; standalone.

2. create_estimate_materials
   — Depends on: estimates (already exists)
   — Columns: estimate_id FK (NOT NULL), catalog_item_id (nullable, NO FK constraint yet)
   — Add unique index: (estimate_id, category, slot_number)
   — Add FK: estimate_materials.estimate_id → estimates.id ON DELETE CASCADE

3. add_job_settings_to_estimates
   — Depends on: estimates (already exists)
   — Adds: miles_to_jobsite, installer_crew_size, delivery_crew_size,
           on_site_time_hrs, profit_overhead_percent, pm_supervision_percent
   — All as decimal or integer; see precision notes below

4. add_quantity_to_estimate_sections
   — Depends on: estimate_sections (already exists)
   — Adds: quantity decimal(10,2) not null default 1

5. create_line_items
   — Depends on: estimate_sections (already exists), estimate_materials (#2)
   — Columns: all line_item columns including estimate_material_id (nullable)
   — Add FK: line_items.estimate_section_id → estimate_sections.id
   — Add FK: line_items.estimate_material_id → estimate_materials.id ON DELETE NULLIFY
   — Do NOT add FK for catalog_item_id yet (table does not exist until Phase 5)
   — Indexes: estimate_section_id, (estimate_section_id, position), estimate_material_id
```

**Precision requirements for estimate columns (migration 3):**
- `miles_to_jobsite` — `decimal(8,2)` (allows up to 999,999.99 miles; more than sufficient)
- `installer_crew_size`, `delivery_crew_size` — `integer not null default 1`
- `on_site_time_hrs` — `decimal(6,2)` (allows up to 9,999.99 hours)
- `profit_overhead_percent`, `pm_supervision_percent` — `decimal(5,2) not null default 0`

Do not use `float` for any of these columns. All feed into BigDecimal arithmetic in the calculator.

---

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Lazy-create EstimateMaterial on first access | No overhead on estimate creation | Grid always shows incomplete state; nil-handling proliferates | Consistency and simplicity favor eager creation |
| STI for LineItem variants | Rails-idiomatic polymorphism | acts_as_list friction; subclasses share all columns anyway | No simplification gained |
| Separate labor_line_items and material_line_items tables | Perfectly normalized | Polymorphic FK needed for section relationship; breaks Turbo Stream dom_id pattern | Not worth the complexity for this domain size |
| Constant for mileage rate | Zero DB queries | Code deploy required to update rate | Admin configurability is higher value |
| LaborRate as JSON column on ShopSettings | Fewer tables | Non-idiomatic, harder to validate per-category; Rails enum-style lookups harder | Multi-row table is Rails-standard and more testable |
| Add FK for catalog_item_id in Phase 4 | Referential integrity earlier | catalog_items / material_catalog_items table doesn't exist yet | Cannot constrain a FK to a non-existent table |

---

## Consequences

### Positive
- `EstimateTotalsCalculator` can be built and tested in Phase 4 with real labor rates from the database.
- `insert_all` for EstimateMaterial seeding keeps estimate creation fast.
- Migration ordering is dependency-clean — each migration can run independently.
- No stored totals means no cache invalidation work.

### Negative
- Two quantity-like columns on `line_items` (`quantity` / `component_quantity`, or renamed `freeform_quantity`) require developer discipline and clear documentation.
- `catalog_item_id` on both `line_items` and `estimate_materials` has no DB-level FK enforcement until Phase 5. Application code must handle nil gracefully.
- The `after_create` callback on `Estimate` will fire in all test contexts — factory traits needed to avoid test database bloat.

### Risks

| Risk | Mitigation |
|------|-----------|
| `float` column used instead of `decimal` for burden settings | Code review checklist: verify column type in migration before merge |
| `alternate_total` key naming inconsistency (`burdened` vs. `sell`) causes wrong values displayed | Fix in spec before development; unit test the Result struct keys |
| `LaborRate.rate_for` fires per labor line item in calculator | Cache at start of `.call` using `index_by` — documented above |
| EstimateMaterial FK pointing to wrong table when Phase 5 arrives | Document FK deferral explicitly in Phase 4 migration comments; Phase 5 migration adds the constraint |

---

## Implementation Notes

### Sequence for the developer agent

1. Create `LaborRate` model and migration first. Seed with default rates. Write model spec for `rate_for` including `NotFound` case.

2. Create `EstimateMaterial` model and migration. Add `after_create :seed_material_slots` with `insert_all` to `Estimate`. Add `skip_material_seeding` factory trait. Write uniqueness and slot_number range specs.

3. Migrate `estimates` table: add six job-level columns. All `decimal`, never `float`. Update `EstimatesController` strong params. Write request spec for `PATCH /estimates/:id` with job settings.

4. Migrate `estimate_sections` table: add `quantity decimal(10,2) not null default 1`. Update `EstimateSection` validations: `validates :quantity, numericality: { greater_than: 0 }`. Add `has_many :line_items` to `EstimateSection` (remove the stub `line_items_count` method). Update `Estimate` model to add `has_many :line_items, through: :estimate_sections`.

5. Create `line_items` migration. Name the freeform quantity column clearly (recommended: `freeform_quantity`). Add all component fields. Add `acts_as_list scope: :estimate_section`. Implement `extended_cost` routing strategy. Do NOT add FK for `catalog_item_id`.

6. Build `EstimateTotalsCalculator`: cache labor rates at start of `.call`, two-pass algorithm, all BigDecimal, mileage rate from `Rails.application.config.burden_constants`. Return `Result` struct with correct key names (`sell:` not `burdened:` for `alternate_total`).

7. Build `EstimateMaterialsController` and the 36-slot edit form.

8. Build `LineItemsController` with Turbo Stream responses. Pass preloaded estimate to calculator on every mutating action.

9. Verify: run calculator spec with a known fixture and assert both non-burdened and burdened totals match hand calculation.

### Key invariant to preserve

The `EstimateTotalsCalculator` must be the only place where burdened totals are computed. No controller, model, or view may contain burden arithmetic. The Stimulus controller (`line_item_calculator_controller.js`) may display real-time `extended_cost` and `sell_price` for buy-out/alternate items, but these are display-only; the canonical values come from the server.

---

## Deferred to Phase 7 (Polish)

The following items are intentionally deferred. They are not blockers for MVP but should be addressed in the Phase 7 polish pass.

### P7-01: Soft delete on Estimates

**File:** `app/controllers/estimates_controller.rb` — `destroy` action

Currently `destroy` calls `@estimate.destroy`, which hard-deletes the record. Once real job data exists, hard deletion is risky — an accidentally deleted estimate is unrecoverable.

**Planned fix:** Add a `deleted_at:datetime` column to `estimates` and use the [Discard gem](https://github.com/jhawthorn/discard) (or a manual `default_scope`/`kept` scope). The `destroy` action becomes `@estimate.discard` and the index scope filters to undiscarded records only. A future admin UI can show and restore soft-deleted estimates.

This is safe to defer for MVP because there is no live data yet and accidental deletion can be corrected via the Rails console.

### P7-02: User-manageable category lists

**File:** `app/models/line_item.rb`

Three constants are currently hardcoded:
- `LINE_ITEM_CATEGORIES` — structural (app logic branches on these); keep hardcoded.
- `COMPONENT_TYPES` — cabinet component labels (exterior, interior, banding, etc.); good candidate for user management.
- `LABOR_CATEGORIES` — labor trade types (detail, mill, assembly, etc.); most likely to need expansion (e.g. adding "painting"); highest priority for user management.

**Planned fix:** In Phase 7, extract `COMPONENT_TYPES` and `LABOR_CATEGORIES` into DB-backed models with admin CRUD. `LABOR_CATEGORIES` should be migrated first as it's the most volatile. `LINE_ITEM_CATEGORIES` stays hardcoded since the app's rendering and calculation logic depends on its specific values.

---

## Known Tech Debt — Required Before First Production Deploy

The following items are low-risk in development (no live data, PostgreSQL handles type coercion) but must be resolved before the first production database is provisioned:

### TD-01: `created_by_user_id` column type should be `bigint`

**File:** `db/migrate/20260405213346_add_columns_to_estimates.rb`

`created_by_user_id` was added as `:integer` (32-bit). Rails generates `users.id` as `bigint` (64-bit) by default. While PostgreSQL allows the FK comparison via implicit cast, the column type mismatch is technically incorrect and could cause surprises on DBs with stricter type checking.

**Required fix:** Write a compensating migration before the production schema is loaded:
```ruby
change_column :estimates, :created_by_user_id, :bigint
```

Also remove the `default: 0` — it was needed to add the column with `null: false` on a potentially populated table, but `0` is not a valid user id. In the compensating migration, also drop the default:
```ruby
change_column_default :estimates, :created_by_user_id, from: 0, to: nil
```

### TD-02: `estimate_material_id` column type on `line_items` should be `bigint`

**File:** `db/migrate/20260406000005_create_line_items.rb`

`estimate_material_id` was declared as `t.integer` (32-bit) while `estimate_materials.id` is `bigint`. Same issue as TD-01.

**Required fix:** Write a compensating migration:
```ruby
change_column :line_items, :estimate_material_id, :bigint
```

### TD-03: `RecordNotUnique` rescue on estimate number assignment

**File:** `app/models/estimate.rb` — `assign_estimate_number`

The `FOR UPDATE` lock defends against concurrent creates when rows already exist for the current year. Two simultaneous first-of-year creates could both observe zero rows, assign `EST-YYYY-0001`, and let the unique index reject one with `ActiveRecord::RecordNotUnique` (unhandled → 500).

**Required fix:** Wrap `Estimate.create` at the call site or add a retry loop:
```ruby
def create
  retries = 0
  begin
    @estimate.save
  rescue ActiveRecord::RecordNotUnique => e
    raise unless e.message.include?("estimate_number") && (retries += 1) <= 3
    @estimate.estimate_number = nil
    retry
  end
end
```

This is safe because after the retry `assign_estimate_number` will re-run and now sees the first-of-year row that the other transaction committed.

---
