# Spec: Materials Rework — Global Library, Per-Estimate Pricing, Product Catalog as Template Only

**ID:** SPEC-014
**Status:** done
**Priority:** high
**Created:** 2026-04-13
**Author:** pm-agent

---

## Summary

SPEC-013 replaced the per-estimate materials price book with flat `_unit_price` and `_description` columns stored directly on `line_items` and `products`. This broke the core estimating workflow: material costs are a property of the job, not the product, and entering a unit price on every line item individually makes job-wide repricing impossible. ADR-010 (accepted 2026-04-13) defines the correct replacement: a global `materials` library from which estimators draw and price materials per-job via an `estimate_materials` join table, plus named `material_sets` for bulk seeding. This spec implements that design in full. It removes all `_unit_price` and `_description` columns from `line_items` and `products`, replaces them with per-estimate material FK columns and the three new tables, rewrites `EstimateTotalsCalculator` to resolve costs through `estimate_materials`, and reframes `Product#apply_to` as a quantity-and-labor-hours template only.

Authority: ADR-010 (accepted 2026-04-13), which supersedes ADR-009 and amends ADR-008.

---

## User Stories

- As an estimator, I want a global materials library where I can maintain a catalog of materials with default prices, so that I have a curated starting point when building each job's price book.
- As an estimator, I want to add materials from the library to an estimate's price book with the library default price pre-filled but editable, so that I can enter job-specific supplier quotes in one place and have all product rows pick them up automatically.
- As an estimator, I want to create a new material from within the estimate workflow if the item is not in the library yet, so that the library stays up to date without requiring a separate admin step.
- As an estimator, I want to apply a named material set to bulk-add a standard group of materials to an estimate in one action, so that I can set up the price book faster for common job types.
- As an estimator, I want to update a material's quote price once and have all line items on the estimate recalculate immediately, so that I can reprice a job when a supplier quote changes without editing every row.
- As an estimator, I want the product catalog to pre-fill default quantities and labor hours when I apply a product to a line item, without overriding the material assignments I have already made.
- As an estimator, I want each material component slot on a line item to reference a specific entry in the estimate's price book, so that the calculator always uses the correct job-specific cost.

---

## Acceptance Criteria

1. Given the global materials library, when an authenticated user visits the materials index, then all non-soft-deleted materials are listed with their name, description, category, unit, and default_price; soft-deleted materials are not shown.

2. Given the materials library, when an authenticated user creates a material with a valid name, category, and default_price, then a `materials` record is created with `discarded_at` null; the record appears in the library index.

3. Given a material in the library that has no associated `estimate_materials` rows, when an authenticated user soft-deletes it, then `discarded_at` is set to the current time and the material no longer appears in the active library index.

4. Given a material in the library that has one or more associated `estimate_materials` rows, when an authenticated user attempts to soft-delete it, then the record is not soft-deleted and a validation error is returned to the UI explaining that the material is in use on one or more estimates.

5. Given an estimate's materials tab, when the estimator searches for a material by name or description fragment, then only active (non-soft-deleted) materials whose `name` or `description` contains the search term are returned.

6. Given an estimate's materials tab, when the estimator selects a search result to add it, then an `estimate_materials` row is created with `quote_price` pre-filled from `material.default_price`; the library record's `default_price` is not modified; if a row for that `material_id` already exists on the estimate, the existing row is left unchanged and no duplicate is created.

7. Given an estimate's materials tab, when the estimator chooses "create new" and submits a valid name, category, default_price, and optional description and unit, then a `materials` library record is created with those values and an `estimate_materials` row is created for this estimate with `quote_price` equal to `default_price`.

8. Given an `estimate_materials` row, when the estimator edits `quote_price` and saves, then `cost_with_tax` is stored as `quote_price * (1 + estimate.tax_rate)`, or equal to `quote_price` if the estimate is `tax_exempt`; the library record's `default_price` is not affected.

9. Given an estimate's `tax_rate` is changed and saved, then all `estimate_materials` rows for that estimate have `cost_with_tax` recalculated via a single SQL UPDATE — not a per-record loop.

10. Given an estimate's `tax_exempt` flag is toggled and saved, then all `estimate_materials` rows for that estimate have `cost_with_tax` recalculated via a single SQL UPDATE.

11. Given the materials setup banner on the estimate show page, when the estimate has zero `estimate_materials` rows, then the banner is displayed with a link to the materials tab; it is advisory only and does not prevent line item creation.

12. Given a material set, when an authenticated user applies it to an estimate, then one `estimate_materials` row is created per `material_set_item` with `quote_price` defaulted from `material.default_price`; any `material_id` already present on the estimate is skipped without error or overwrite.

13. Given the `line_items` table after migration, when the schema is inspected, then the ten `_unit_price` columns (`exterior_unit_price`, `interior_unit_price`, `interior2_unit_price`, `back_unit_price`, `banding_unit_price`, `drawers_unit_price`, `pulls_unit_price`, `hinges_unit_price`, `slides_unit_price`, `locks_unit_price`) and the ten `_description` columns (`exterior_description`, `interior_description`, `interior2_description`, `back_description`, `banding_description`, `drawers_description`, `pulls_description`, `hinges_description`, `slides_description`, `locks_description`) do not exist; and nine `_material_id` bigint nullable FK columns (`exterior_material_id`, `interior_material_id`, `interior2_material_id`, `back_material_id`, `banding_material_id`, `drawers_material_id`, `pulls_material_id`, `hinges_material_id`, `slides_material_id`) exist referencing `estimate_materials` with `ON DELETE SET NULL`; `locks_qty` remains; `locks` does not have a `_material_id` column.

14. Given the `products` table after migration, when the schema is inspected, then the ten `_unit_price` columns and ten `_description` columns do not exist; all `_qty` columns, all labor hour columns, `equipment_hrs`, `equipment_rate`, `other_material_cost`, `name`, `category`, and `unit` remain.

15. Given `Product#apply_to(line_item)` is called, when the method runs, then it copies only: the eight `_qty` values for the component slots that have qty columns (excluding banding, which has no qty), all six labor hour columns (`detail_hrs`, `mill_hrs`, `assembly_hrs`, `customs_hrs`, `finish_hrs`, `install_hrs`), `equipment_hrs`, `equipment_rate`, `other_material_cost`, and `unit`; it does not set any `_material_id`, `_unit_price`, or `_description` values.

16. Given a line item where `exterior_material_id` points to an `estimate_materials` record and `exterior_qty` is non-zero, when `EstimateTotalsCalculator#call` runs, then `exterior_qty * estimate_materials_by_id[exterior_material_id].cost_with_tax` is included in that line item's `material_cost_per_unit`; a null `_material_id` or a record not found in the index contributes zero without error.

17. Given a line item where `banding_material_id` points to an `estimate_materials` record, when `EstimateTotalsCalculator#call` runs, then `estimate_materials_by_id[banding_material_id].cost_with_tax` is added to `material_cost_per_unit` with no quantity multiplier.

18. Given a line item with a non-zero `locks_qty`, when `EstimateTotalsCalculator#call` runs, then `locks_qty * locks_em.cost_with_tax` is included in `material_cost_per_unit`, where `locks_em` is the `estimate_materials` row whose `role` column equals `"locks"`; if no such row exists, the contribution is zero.

19. Given `EstimateTotalsCalculator` is instantiated for an estimate, when `call` is invoked, then exactly two database queries are issued before iterating line items: one loading all `estimate_materials` for the estimate indexed by id, and one loading all `LaborRate` records indexed by `labor_category`; there are no per-line-item queries.

---

## Technical Scope

### Data / Models

#### `materials` table — new global library

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| name | string NOT NULL | e.g. "Maple Plywood 3/4" |
| description | string | additional detail; searchable alongside name |
| category | string NOT NULL | `"sheet_good"` or `"hardware"` |
| unit | string | e.g. "sheet", "each" |
| default_price | decimal(12,4) NOT NULL default 0 | set on creation; updated only via Materials CRUD — never auto-updated from estimate activity |
| discarded_at | datetime | NULL = active; non-NULL = soft-deleted |
| created_at / updated_at | datetime | |

Index: `name` (for search); no unique constraint on name.

**`Material` model:**
- `has_many :estimate_materials`
- `before_discard` (discard gem pattern): raise a validation error — do not call `discard` — if any associated `estimate_materials` rows exist; return the error to the controller so the UI can display it.
- Scope `active` (or `kept`): `where(discarded_at: nil)`.
- Scope `search(term)`: `where("name ILIKE :q OR description ILIKE :q", q: "%#{term}%")` on active records.
- `validates :name, presence: true`
- `validates :category, inclusion: { in: %w[sheet_good hardware] }`
- `validates :default_price, numericality: { greater_than_or_equal_to: 0 }`

#### `estimate_materials` table — per-estimate pricing

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| estimate_id | bigint NOT NULL FK → estimates ON DELETE CASCADE | |
| material_id | bigint NOT NULL FK → materials | |
| quote_price | decimal(12,4) NOT NULL default 0 | this job's price; defaults from `material.default_price` on creation |
| cost_with_tax | decimal(12,4) NOT NULL default 0 | stored computed: `quote_price * (1 + tax_rate)`, or `quote_price` if tax_exempt |
| role | string | nullable; `"locks"` or `"banding"` to allow calculator slot resolution for components without a `_material_id` FK; any other role values are reserved for future use |
| created_at / updated_at | datetime | |

Unique index: `(estimate_id, material_id)`.

**`EstimateMaterial` model:**
- `belongs_to :estimate`
- `belongs_to :material`
- `before_save :compute_cost_with_tax`: `self.cost_with_tax = estimate.tax_exempt? ? quote_price : quote_price * (1 + estimate.tax_rate)`; `estimate` must be preloaded — building through `estimate.estimate_materials.build` satisfies this.
- `validates :quote_price, numericality: { greater_than_or_equal_to: 0 }`
- `validates :material_id, uniqueness: { scope: :estimate_id }`

**`Estimate` model — update:**
- `has_many :estimate_materials, dependent: :destroy`
- `has_many :materials, through: :estimate_materials`
- Add callback: `after_save :recalculate_material_costs, if: :saved_change_to_tax_rate?`
- Add callback: `after_save :recalculate_material_costs, if: :saved_change_to_tax_exempt?`
- `recalculate_material_costs`: single SQL UPDATE — `estimate_materials.where(estimate_id: id).update_all(...)` with conditional for `tax_exempt`; do not loop over records.
- Do NOT add `after_create :seed_materials` — the new design has no auto-seeding. The estimator builds the price book manually or via a material set.
- Remove the `skip_material_seeding` factory trait if it exists — it is no longer relevant.

#### `material_sets` table — new

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| name | string NOT NULL | display name for the set |
| created_at / updated_at | datetime | |

**`MaterialSet` model:**
- `has_many :material_set_items, dependent: :destroy`
- `has_many :materials, through: :material_set_items`
- `validates :name, presence: true`

#### `material_set_items` table — new

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| material_set_id | bigint NOT NULL FK → material_sets ON DELETE CASCADE | |
| material_id | bigint NOT NULL FK → materials | |
| created_at / updated_at | datetime | |

**`MaterialSetItem` model:**
- `belongs_to :material_set`
- `belongs_to :material`
- `validates :material_id, uniqueness: { scope: :material_set_id }`

#### `line_items` table — changes from current SPEC-013 state

**Remove** (20 columns total):
- `exterior_unit_price`, `interior_unit_price`, `interior2_unit_price`, `back_unit_price`, `banding_unit_price`, `drawers_unit_price`, `pulls_unit_price`, `hinges_unit_price`, `slides_unit_price`, `locks_unit_price`
- `exterior_description`, `interior_description`, `interior2_description`, `back_description`, `banding_description`, `drawers_description`, `pulls_description`, `hinges_description`, `slides_description`, `locks_description`

**Add** (9 columns):
- `exterior_material_id`, `interior_material_id`, `interior2_material_id`, `back_material_id`, `banding_material_id`, `drawers_material_id`, `pulls_material_id`, `hinges_material_id`, `slides_material_id` — all bigint nullable, FK → `estimate_materials` ON DELETE SET NULL.

**Keep unchanged:** all `_qty` columns, `locks_qty`, `other_material_cost`, all six labor hour columns, `equipment_hrs`, `equipment_rate`, `description`, `quantity`, `unit`, `position`, `estimate_id`, `product_id`.

**Note:** `locks` does not get a `_material_id` column. Locks cost is resolved at calculator time via the `estimate_materials` row where `role = "locks"`. `banding_material_id` exists as a FK but banding cost is applied without a qty multiplier.

**`LineItem` model — update:**
- Add nine `belongs_to :<slot>_material, class_name: "EstimateMaterial", optional: true` associations for the nine FK columns (e.g., `belongs_to :exterior_material, class_name: "EstimateMaterial", foreign_key: :exterior_material_id, optional: true`).
- Remove all references to `_unit_price` and `_description` column accessors from comments and any existing attribute lists.

#### `products` table — changes from current SPEC-013 state

**Remove** (20 columns total, same list as line_items):
- All ten `_unit_price` columns: `exterior_unit_price`, `interior_unit_price`, `interior2_unit_price`, `back_unit_price`, `banding_unit_price`, `drawers_unit_price`, `pulls_unit_price`, `hinges_unit_price`, `slides_unit_price`, `locks_unit_price`
- All ten `_description` columns: `exterior_description`, `interior_description`, `interior2_description`, `back_description`, `banding_description`, `drawers_description`, `pulls_description`, `hinges_description`, `slides_description`, `locks_description`

**Keep unchanged:** all `_qty` columns, `detail_hrs`, `mill_hrs`, `assembly_hrs`, `customs_hrs`, `finish_hrs`, `install_hrs`, `equipment_hrs`, `equipment_rate`, `other_material_cost`, `name`, `category`, `unit`.

**`Product` model — rewrite `apply_to`:**

```ruby
def apply_to(line_item)
  # Eight qty slots (banding has no qty column)
  %i[exterior interior interior2 back drawers pulls hinges slides].each do |slot|
    line_item.public_send(:"#{slot}_qty=", public_send(:"#{slot}_qty"))
  end
  # locks_qty is also a qty column
  line_item.locks_qty = locks_qty

  LABOR_CATEGORIES.each do |cat|
    line_item.public_send(:"#{cat}_hrs=", public_send(:"#{cat}_hrs"))
  end

  line_item.other_material_cost = other_material_cost
  line_item.equipment_hrs       = equipment_hrs
  line_item.equipment_rate      = equipment_rate
  line_item.unit                = unit
end
```

Remove the `_description=` and `_unit_price=` assignment loop from `apply_to`. `MATERIAL_SLOTS` and `LABOR_CATEGORIES` constants may be retained if still useful elsewhere; `_material_id` values are never set by `apply_to`.

### API / Logic

#### New routes

```ruby
# Global materials library
resources :materials   # index, new, create, edit, update, destroy (soft-delete)

# Material sets
resources :material_sets do
  resources :material_set_items, only: [:create, :destroy]
  member do
    post :apply_to_estimate   # params: estimate_id
  end
end

# Per-estimate materials (nested under estimates)
resources :estimates do
  resources :estimate_materials, only: [:index, :new, :create, :edit, :update, :destroy]
  # estimate_materials#new has two paths: search-from-library and create-new-library-entry
end
```

#### `MaterialsController` (global library)

Standard CRUD. `destroy` action calls the soft-delete guard: if `material.estimate_materials.any?`, render the form with a validation error; otherwise set `discarded_at`. Hard delete is not supported.

#### `EstimateMaterialsController` (nested under estimates)

- `index` — lists all `estimate_materials` for the estimate, joined with `materials` for display; shows quote_price, cost_with_tax, name, category, unit; includes an "Apply set" dropdown.
- `new` — renders two sub-paths controlled by a tab or parameter:
  - **Search path:** a search field that queries `Material.active.search(term)` via a Turbo Frame (or simple form submit); displays results; selecting a result POSTs to `create`.
  - **Create-new path:** a form for name, description, category, unit, default_price; submitting creates both a `Material` and an `EstimateMaterial` in one controller action.
- `create` — accepts either `material_id` (from search) or new-material params:
  - If `material_id` present: find or initialize `estimate_materials` row; if it already exists, redirect with an informational notice (no duplicate); otherwise create with `quote_price = material.default_price`.
  - If new-material params: create `Material` with `default_price` = submitted price; create `EstimateMaterial` with `quote_price = material.default_price`.
- `edit` / `update` — edit `quote_price` (and optionally `role`) for a single row; `before_save` on `EstimateMaterial` updates `cost_with_tax`.
- `destroy` — removes the row; if any `line_items` reference it via a `_material_id` FK, those FKs are nullified by the DB `ON DELETE SET NULL` constraint.

#### `MaterialSetsController`

Standard CRUD on `material_sets`. The `apply_to_estimate` member action:
1. Receives `estimate_id` param.
2. Loads the estimate; authorizes it (must belong to a visible estimate scope).
3. For each `material_set_item`: find or initialize `EstimateMaterial` for `(estimate_id, material_id)`; skip if already exists; otherwise create with `quote_price = material.default_price`.
4. Redirects to the estimate's materials index with a notice indicating how many materials were added and how many were skipped.

#### `EstimateTotalsCalculator` — rewrite material cost section

Remove `TYPED_SLOTS` constant and its flat-column loop. Remove `banding_unit_price` reference.

Replace with:

```
# Two queries before line item iteration — loaded once, not per line item
estimate_materials_by_id = EstimateMaterial
  .where(estimate_id: @estimate.id)
  .index_by(&:id)

locks_em   = estimate_materials_by_id.values.find { |em| em.role == "locks" }
labor_rates = LaborRate.all.index_by(&:labor_category)

For each line item:
  material_cost_per_unit = BigDecimal("0")

  # Eight FK-backed qty slots
  %w[exterior interior interior2 back drawers pulls hinges slides].each do |slot|
    qty = li.public_send(:"#{slot}_qty").to_d
    em  = estimate_materials_by_id[li.public_send(:"#{slot}_material_id")]
    material_cost_per_unit += qty * em&.cost_with_tax.to_d
  end

  # Banding — no qty multiplier
  banding_em = estimate_materials_by_id[li.banding_material_id]
  material_cost_per_unit += banding_em&.cost_with_tax.to_d

  # Locks — resolved by role, not FK
  material_cost_per_unit += li.locks_qty.to_d * locks_em&.cost_with_tax.to_d

  # Freeform
  material_cost_per_unit += li.other_material_cost.to_d
```

All arithmetic remains BigDecimal. Nil `_material_id` or nil record in index contributes zero via safe navigation + `.to_d`.

All other calculator logic (labor subtotals, equipment total, burden multiplier, job-level fixed costs, COGS breakdown) is unchanged.

### UI / Frontend

#### Global materials library (`/materials`)

- Index page: table of active materials with name, description, category, unit, default_price; "Edit" and "Archive" actions per row; "New Material" button.
- New/Edit form: name (required), description, category (select: sheet_good / hardware), unit, default_price; standard flash on save/error.
- Archive (soft-delete): confirmation prompt; if the material is in use, display the validation error inline instead of archiving.
- Archived materials are not shown on the index by default; a "Show archived" toggle is a future enhancement.

#### Material Sets (`/material_sets`)

- Index: list of sets with item counts; "Edit", "Delete", and "Apply to estimate..." actions.
- New/Edit form: set name; add/remove materials from the library (search-select or checkboxes over the active library list).
- Apply modal or page: select an estimate from a dropdown; submit triggers `apply_to_estimate`; result page shows added and skipped counts.

#### Per-estimate materials tab

- Accessible via a "Materials" button or tab in the estimate top bar (restore the link removed in SPEC-013).
- The tab shows: a table of all `estimate_materials` for the estimate with name, category, unit, quote_price (editable inline or via edit link), cost_with_tax (read-only computed); a "role" badge if the row has `role = "locks"`.
- An "Add material" button opens the search-first flow described in `EstimateMaterialsController#new`.
- An "Apply set" dropdown or button applies a named material set.
- On the estimate show page: the materials setup banner is displayed when `estimate.estimate_materials.none?`; it contains a link to the materials tab and reads something like "Add materials before pricing products — material costs will be zero until materials are set up."

#### Line item form

- Replace the ten `_description` text fields and ten `_unit_price` decimal inputs with nine `_material_id` select fields — one per FK-backed component slot.
- Each select lists the estimate's `estimate_materials` entries with a human-readable label (material name + quote_price); blank/null option is available.
- `locks_qty` field remains as a numeric input; there is no material selector for locks on the line item form (the locks `estimate_materials` row is identified by `role = "locks"`, set in the price book).
- When a product is applied via catalog picker, `_qty` fields and labor hours are pre-filled by `apply_to`; `_material_id` fields remain null — the estimator assigns them manually.

#### Product catalog form

- Remove all `_unit_price` and `_description` input fields from the product new/edit form.
- Form retains: `name`, `category`, `unit`, all `_qty` fields, all six labor hour fields, `equipment_hrs`, `equipment_rate`, `other_material_cost`.

### Background Processing

None. `recalculate_material_costs` is a synchronous SQL UPDATE fired by the `after_save` callback on `Estimate`. At the data volumes this app handles this is appropriate and requires no background job.

---

## Migration Strategy

The app is pre-production with no user data that must be preserved. All estimate and line item data is cleared before schema changes.

Steps (single migration file or ordered sequence — developer's choice):

1. `LineItem.delete_all` and `Estimate.delete_all` via `execute` in the migration (or equivalent data-clearing step before column changes).
2. Remove ten `_unit_price` columns from `line_items`.
3. Remove ten `_description` columns from `line_items`.
4. Add nine `_material_id` bigint nullable columns to `line_items`; add FKs → `estimate_materials` with `ON DELETE SET NULL` after step 7.
5. Remove ten `_unit_price` columns from `products`.
6. Remove ten `_description` columns from `products`.
7. Create `materials` table (id, name, description, category, unit, default_price decimal(12,4) default 0, discarded_at datetime, timestamps). Add index on `name`.
8. Create `estimate_materials` table (id, estimate_id bigint NOT NULL FK → estimates ON DELETE CASCADE, material_id bigint NOT NULL FK → materials, quote_price decimal(12,4) default 0, cost_with_tax decimal(12,4) default 0, role string, timestamps). Add unique index on `(estimate_id, material_id)`.
9. Add FKs: `add_foreign_key :estimate_materials, :estimates, on_delete: :cascade` and `add_foreign_key :estimate_materials, :materials`.
10. Add FKs for the nine `_material_id` columns on `line_items`: `add_foreign_key :line_items, :estimate_materials, column: :exterior_material_id, on_delete: :nullify` (repeat for each of the nine columns).
11. Create `material_sets` table (id, name string NOT NULL, timestamps).
12. Create `material_set_items` table (id, material_set_id bigint NOT NULL FK → material_sets ON DELETE CASCADE, material_id bigint NOT NULL FK → materials, timestamps). Add unique index on `(material_set_id, material_id)`.
13. Add FKs for material_sets and material_set_items.

---

## Test Requirements

### Unit Tests

**`Material` model (`spec/models/material_spec.rb`):**
- Valid factory creates an active (discarded_at nil) record.
- `validates :name, presence: true` — blank name is invalid.
- `validates :category, inclusion` — value outside `%w[sheet_good hardware]` is invalid.
- `validates :default_price, numericality: { gte: 0 }` — negative price is invalid.
- `Material.active` scope excludes soft-deleted records.
- `Material.search("maple")` returns records matching name or description; case-insensitive.
- Soft-delete is blocked (validation error, record not discarded) when any `estimate_materials` rows exist.
- Soft-delete succeeds when no `estimate_materials` rows exist.

**`EstimateMaterial` model (`spec/models/estimate_material_spec.rb`):**
- `before_save` sets `cost_with_tax = quote_price * (1 + estimate.tax_rate)` when estimate is not tax exempt.
- `before_save` sets `cost_with_tax = quote_price` when estimate is tax exempt.
- `before_save` sets `cost_with_tax = 0` when `quote_price = 0`.
- `validates :material_id, uniqueness: { scope: :estimate_id }` — duplicate (estimate_id, material_id) pair is invalid.

**`Estimate` model (`spec/models/estimate_spec.rb`):**
- `after_create` does NOT seed any `estimate_materials` rows — estimate is created with zero estimate_materials.
- `after_save` with `tax_rate` change triggers `recalculate_material_costs`; all `estimate_materials` `cost_with_tax` values update correctly.
- `after_save` with `tax_exempt` change to true sets all `cost_with_tax` equal to `quote_price`.
- `after_save` with unrelated field change (e.g., `title`) does not trigger `recalculate_material_costs`.

**`MaterialSet` model (`spec/models/material_set_spec.rb`):**
- `validates :name, presence: true`.
- `has_many :material_set_items, dependent: :destroy` — destroying the set destroys its items.

**`Product` model (`spec/models/product_spec.rb`):**
- `apply_to` copies `_qty` values for the eight qty-having component slots and `locks_qty`.
- `apply_to` copies all six labor hour columns.
- `apply_to` copies `equipment_hrs`, `equipment_rate`, `other_material_cost`, `unit`.
- `apply_to` does not set any `_material_id` value on the line item.
- `apply_to` does not set any `_unit_price` or `_description` value (those columns no longer exist; the test confirms no NoMethodError is raised and no such attribute is assigned).

**`EstimateTotalsCalculator` (`spec/services/estimate_totals_calculator_spec.rb`):**
- FK-backed slot with non-null `_material_id` and non-zero qty: result includes `qty * estimate_material.cost_with_tax`.
- Null `_material_id` contributes zero; does not raise.
- Record referenced by FK not found in index (e.g., was deleted and FK nullified) contributes zero; does not raise.
- Banding: `banding_material_id` non-null → `cost_with_tax` added with no qty multiplier.
- Banding: `banding_material_id` null → zero contribution.
- Locks: non-zero `locks_qty` with a locks-role `estimate_material` → `locks_qty * em.cost_with_tax` added.
- Locks: no locks-role `estimate_material` present → zero contribution, no error.
- Two database queries total before line item iteration (estimate_materials + labor_rates); no per-line-item queries.
- Labor subtotals, equipment total, and burden multiplier calculations are unchanged from pre-SPEC-014 behaviour.

### Integration Tests

**`MaterialsController` (`spec/requests/materials_spec.rb`):**
- `GET /materials` — 200 for authenticated user; shows active materials; does not show soft-deleted materials.
- `POST /materials` with valid params — creates record; redirects.
- `POST /materials` with invalid params — re-renders form with errors.
- `PATCH /materials/:id` with valid params — updates record; redirects.
- `DELETE /materials/:id` on a material with no `estimate_materials` rows — sets `discarded_at`; redirects.
- `DELETE /materials/:id` on a material with active `estimate_materials` rows — does not soft-delete; renders error.
- Unauthenticated requests — redirect to login.

**`EstimateMaterialsController` (`spec/requests/estimate_materials_spec.rb`):**
- `GET /estimates/:estimate_id/estimate_materials` — 200; lists the estimate's materials.
- `POST /estimates/:estimate_id/estimate_materials` with `material_id` — creates `estimate_materials` row with `quote_price = material.default_price`; redirects.
- `POST /estimates/:estimate_id/estimate_materials` with new-material params — creates `Material` and `EstimateMaterial` in one request; redirects.
- `POST` with a `material_id` already present on the estimate — does not create a duplicate; redirects with informational notice.
- `PATCH /estimates/:estimate_id/estimate_materials/:id` with updated `quote_price` — updates `quote_price` and `cost_with_tax`; redirects.
- Params containing `exterior_unit_price` or `exterior_description` on `line_items` create/update are not accessible via strong params (verify strong params filter).
- Unauthenticated requests — redirect to login.

**`MaterialSetsController` (`spec/requests/material_sets_spec.rb`):**
- `POST /material_sets/:id/apply_to_estimate` with valid `estimate_id` — creates expected `estimate_materials` rows; skips existing; redirects with counts.
- `POST` with an invalid `estimate_id` — 404 or redirect with error.

**`LineItemsController` (`spec/requests/line_items_spec.rb`):**
- `POST` with `exterior_material_id` pointing to a valid `estimate_materials` id — creates line item with FK set.
- `PATCH` with updated `exterior_material_id` — updates FK.

### End-to-End Tests

**Materials library flow (`spec/system/materials_spec.rb`):**
- Authenticated user visits `/materials`; sees the library index.
- User creates a new material (name: "Maple Plywood 3/4", category: sheet_good, default_price: 68); it appears in the index.
- User edits the material; changes default_price; saves; updated value is shown.
- User attempts to archive a material that is in use on an estimate; error message is shown; material remains in the list.
- User archives a material with no estimate uses; it disappears from the active list.

**Per-estimate materials price book flow (`spec/system/estimate_materials_spec.rb`):**
- Estimator creates an estimate; navigates to estimate show page; materials setup banner is visible.
- Estimator clicks the "Materials" link in the estimate top bar; materials tab loads showing an empty table.
- Estimator uses the search path to find "Maple Plywood 3/4"; selects it; row appears in the table with `quote_price` equal to the library default_price.
- Estimator edits the `quote_price` to a different value; saves; `cost_with_tax` in the table reflects `new_price * (1 + tax_rate)`.
- Estimator returns to estimate show page; setup banner is no longer visible.
- Estimator changes the estimate `tax_rate`; navigates back to the materials tab; all `cost_with_tax` values reflect the new rate.

**Material sets flow (`spec/system/material_sets_spec.rb`):**
- User creates a material set named "Standard Maple"; adds two library materials to it.
- User navigates to an estimate's materials tab; applies the "Standard Maple" set; both materials appear in the price book.
- User applies the same set again; a notice confirms that materials were already present and no duplicates were added.

**Line item material assignment flow (`spec/system/line_items_spec.rb`):**
- Estimator adds a material to the estimate's price book.
- Estimator adds a line item; the `exterior_material_id` selector lists the estimate's materials; selects the material; sets `exterior_qty`; saves.
- Estimate totals panel reflects `exterior_qty * estimate_material.cost_with_tax` for the line item.
- Estimator selects a product from the catalog; `_qty` fields and labor hours are pre-filled; `_material_id` selectors remain unset.

---

## Out of Scope

- Per-slot `_slot_type` hint columns on `products` (ADR-010 OQ-A): deferred to a future polish spec; the material selector on the line item form shows all estimate materials undifferentiated.
- Auto-matching `_material_id` on `apply_to` based on category hints (ADR-010 OQ-D): deferred.
- Inline Turbo Frame per-row editing of materials on the estimate show page (ADR-010 OQ-E): separate full-page form is sufficient.
- Archived materials "show archived" toggle on the library index: future enhancement.
- PDF/document output changes.
- Labor rate management UI.
- Role-based access control on materials CRUD.
- Hard delete of any record type.
- Duplicate detection or fuzzy matching in the global library — the team manages duplicates manually.
- Auto-suggesting specific library materials for each product slot when applying a product to a line item.

---

## Open Questions

| OQ | Question | Blocks progress? |
|----|---------|-----------------|
| OQ-A | The `role` column on `estimate_materials` covers `"locks"`. Should `"banding"` also have a role, or is banding always resolved via `banding_material_id` FK? The ADR notes banding has a FK; locks does not. Confirm that the role column is needed only for locks (and future slots that lack a FK column). | No — default: role is used only for locks; banding uses the FK. Developer should confirm before building. |
| OQ-B | Materials setup banner visibility condition: zero `estimate_materials` rows (new estimate, no setup done) vs. any `estimate_materials` with `quote_price = 0` (partial setup). ADR-010 uses "zero rows" as the condition. Confirm this is the desired trigger. | No — zero rows is the correct trigger per ADR-010; partial setup with zero-priced rows is a valid in-progress state. |
| OQ-C | The `apply_to_estimate` action on `MaterialSetsController` — should it live as a member route on `material_sets` or as a separate `EstimateMaterialsController` action (e.g., `POST /estimates/:id/estimate_materials/apply_set`)? | No — either is acceptable; nesting under `estimate_materials` may be more RESTful. Developer decides. |

---

## Dependencies

- ADR-010 (Materials Per-Estimate, Product Catalog as Template) — the accepted architecture decision this spec implements; primary reference.
- ADR-008 (Estimating Module Refactor) — original per-estimate materials design; relevant sections reinstated by ADR-010.
- Current `db/schema.rb` (as of 2026-04-13, version 2026_04_13_000001) — defines the SPEC-013 state being migrated from; confirms the exact columns to remove and keep.
- Current `app/models/product.rb` — defines `apply_to` and `MATERIAL_SLOTS`/`LABOR_CATEGORIES` constants to be updated.
- Current `app/models/line_item.rb` — flat-column model being replaced.
- Current `app/services/estimate_totals_calculator.rb` — flat-column calculator being rewritten.
- SPEC-013 (Product Catalog and Line Item Refactor) — done; this spec migrates away from its schema decisions.
- No other in-flight specs depend on the `_unit_price` columns being removed.
