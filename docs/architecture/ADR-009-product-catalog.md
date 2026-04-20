# ADR-009: Product Catalog — Data Model and Integration with Line Items

**Status:** superseded
**Date:** 2026-04-11
**Deciders:** architect-agent
**Superseded by:** ADR-010 (2026-04-13)

Extends: ADR-008 (estimating refactor — flat column line items, no stored calculated fields)

---

## Context

The app currently builds estimates by having estimators enter each line item from scratch: description, material types (selected from the per-estimate price book), quantities, and labor hours. The business wants a product catalog — a library of reusable product templates (e.g., "MDF Base 2-door", "Plywood Upper 1-door") that an estimator can select to pre-fill a line item. The per-estimate `materials` price book is being eliminated entirely; material costs (description + unit price) will live directly on the product and on the line item.

This ADR records six schema and integration decisions that govern the catalog feature. The app is pre-production; existing estimate data can be cleared.

---

## Decisions

### Decision 1 — Product schema: flat columns, mirroring line_items

The `products` table uses flat columns for all material slot data: for each of the nine component slots (exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides) plus locks, the product stores `<slot>_description` (string), `<slot>_unit_price` (decimal), and `<slot>_qty` (decimal, except banding which has no qty per ADR-008). `other_material_cost` (decimal) and the six labor hour columns and two equipment columns are also flat columns on the product, mirroring the line_items schema exactly minus the estimate and position columns.

The FK-based material associations are gone. Products store the actual values, not pointers.

### Decision 2 — LineItem schema: replace material FKs with flat description + unit_price columns

The nine `<slot>_material_id` FK columns and the `materials` association are removed from `line_items`. For each slot, `<slot>_material_id` is replaced by `<slot>_description` (string) and `<slot>_unit_price` (decimal). The existing `<slot>_qty` columns are kept. `locks_unit_price` is added (there is already a `locks_qty`). `other_material_cost` stays.

This is a direct extension of ADR-008 Decision 2 (flat columns). The only change is that the unit cost of a material slot is now stored inline on the line item instead of being a FK to a per-estimate price book row.

### Decision 3 — Product → LineItem copy: model method on Product; product_id retained on line_item

When an estimator selects a catalog product for a line item, all product values are copied into the line item's flat columns by calling `product.apply_to(line_item)` — a model method on `Product` that assigns each column individually. This is an explicit snapshot: the line item becomes independent of the product at copy time. Future product edits do not affect existing line items.

`line_items` retains a nullable `product_id` FK to `products` (`ON DELETE SET NULL`). This is for display and audit only — it allows the UI to show "based on MDF Base 2-door" and is useful for future analytics (e.g., which product templates are used most). It carries no semantic weight in calculations; the calculator reads only the flat columns.

The copy is triggered in `LineItemsController#create` (and potentially `#update` if the estimator swaps the product). The controller sets `@line_item.product = product` and then calls `product.apply_to(@line_item)` before saving. This is controller-level coordination, not a callback — callbacks on product assignment would be implicit and hard to test.

### Decision 4 — Estimate model cleanup

The following are removed from `Estimate`:

- `has_many :materials, dependent: :destroy` association
- `after_create :seed_materials` callback
- `after_update :recalculate_material_costs` callback
- `seed_materials` private method
- `recalculate_material_costs` private method

The `tax_rate` and `tax_exempt` columns stay on `Estimate` — they are used in the burden calculation, not in material cost storage. The `copy_tax_exempt_from_client` before_create callback stays. The `assign_estimate_number` before_validation callback stays.

The `materials` table is dropped entirely. No replacement is needed. Material costs now live on products and on line items.

### Decision 5 — Calculator changes

`EstimateTotalsCalculator` no longer needs to load materials by id or by slot_key. It no longer resolves a LOCKS material record. The calculation simplifies to:

```
material_cost_per_unit =
  (exterior_qty   * exterior_unit_price)
  + (interior_qty  * interior_unit_price)
  + (interior2_qty * interior2_unit_price)
  + (back_qty      * back_unit_price)
  + banding_unit_price                       # no qty; full unit price applied when present
  + (drawers_qty   * drawers_unit_price)
  + (pulls_qty     * pulls_unit_price)
  + (hinges_qty    * hinges_unit_price)
  + (slides_qty    * slides_unit_price)
  + (locks_qty     * locks_unit_price)
  + other_material_cost

subtotal_materials     = material_cost_per_unit * quantity
labor_subtotal[cat]    = <cat>_hrs * labor_rates[cat].hourly_rate * quantity
equipment_total        = equipment_hrs * equipment_rate * quantity
non_burdened_total     = subtotal_materials + sum(labor subtotals) + equipment_total
```

All nil values are treated as zero (`.to_d` on nil returns BigDecimal("0")). All arithmetic remains BigDecimal. The calculator loads only `LaborRate` records (one query); the materials-by-id and materials-by-slot_key queries are eliminated.

The public interface is unchanged: `EstimateTotalsCalculator.new(estimate).call`.

### Decision 6 — Migration strategy

1. Drop `materials` table (and all FK constraints from `line_items` to `materials`).
2. Remove material FK columns from `line_items` (`exterior_material_id`, etc. — nine columns).
3. Add material description + unit price columns to `line_items` (nine `<slot>_description` string columns, nine `<slot>_unit_price` decimal columns, plus `locks_unit_price`).
4. Create `products` table (see schema below).
5. Add `product_id` nullable FK to `line_items` (`ON DELETE SET NULL`).
6. Delete `app/models/material.rb`, `app/controllers/materials_controller.rb`, and associated views and specs.
7. Clear existing line item and estimate data (`LineItem.delete_all`, `Estimate.delete_all`).

No data migration is needed — existing data is cleared. Run as a single migration batch on a feature branch.

### Decision 7 — Product category field: yes, include it

Products have a `category` string column (e.g., "Base Cabinets", "Upper Cabinets", "Tall Cabinets", "Specialty"). This is not a FK to a separate table — it is a plain string. Rationale: the catalog will grow to dozens of products; without grouping, the selection UI becomes an undifferentiated list. A string category allows `<optgroup>` grouping in select menus and basic filtering without the overhead of a categories table. A separate table adds no value at this catalog size. If the shop later needs to rename categories across many products, a simple SQL update handles it.

---

## Rationale

### Decision 1 and 2 — Flat columns over normalized or JSONB

This continues the pattern established in ADR-008 Decision 2. The slot structure is fixed (nine slots plus locks), defined by the shop's workflow, and has been stable for years. The arguments against a join table are the same: it forces the calculator to join, forces the UI to reconstruct a dynamic grid from rows, and adds upsert logic on every save. JSONB sacrifices type safety and queryability for no meaningful gain at this data volume.

The primary cost of flat columns is table width. `line_items` gains approximately 19 columns (9 descriptions + 9 unit prices + 1 locks_unit_price), reaching roughly 50 columns total. This is wide by normalized standards but is not a performance concern at the record volumes this app will see. The columns are directly readable and map one-to-one with the spreadsheet grid.

### Decision 3 — Copy-on-select vs. live reference

A live FK from line_item to product with values read at calculation time would mean that changing a product's prices silently reprices all existing estimates. That is incorrect behavior for a quoting document — estimates must be point-in-time snapshots. Copy-on-select is the only correct choice. This is the same principle as ADR-008 Decision 5 (tax_exempt copied from client).

Retaining `product_id` as a display-only reference is low-cost and useful. It does not complicate the calculator because the calculator ignores it. Setting it to `ON DELETE SET NULL` means deleting a catalog product does not destroy any estimate data.

### Decision 4 — Removing the materials table

The per-estimate materials price book was always the awkward part of this design. It required seeding 50 rows on every estimate create, maintaining `cost_with_tax` recalculation callbacks whenever the estimate's tax rate changed, and a two-step UI workflow (set prices on materials, then assign them to line items). With material unit prices stored directly on the product and line item, all of this overhead disappears. The tax rate on the estimate is still used in burden calculations but is no longer used to maintain a derived `cost_with_tax` column on a separate table.

### Decision 5 — Calculator simplification

Eliminating the materials lookup is not just a performance improvement — it removes a class of bugs (stale `cost_with_tax` values, LOCKS slot lookup by string key across estimate boundary). The new formula is purely arithmetic on columns that are always present on the record.

---

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Normalized `product_components` table (slot_name, unit_price, qty, description) | Flexible; easy to add slots without migrations | Join on every calculator pass; upsert logic on save; breaks flat-column pattern; UI must reconstruct grid from rows | Same reasons as ADR-008 Decision 2; slot structure is fixed |
| JSONB `material_components` column on products/line_items | Very flexible; no schema change for slot additions | No type safety; no column-level indexing; calculator must parse JSON; breaks pattern | Flexibility not needed; type safety matters for financial data |
| Keep materials table, add product catalog on top | Less migration disruption | Maintains the double-price-book complexity; two places where material costs live; seeding and recalculation callbacks stay | The materials table is the source of complexity; eliminating it is the point |
| Separate categories table for product grouping | Referential integrity; rename in one place | Overkill for a catalog that will have ~50 products; adds a FK and admin screen for no benefit | Category string is sufficient; SQL update handles renames |
| Copy product values via `after_assign` callback or concern | Code stays on the model | Implicit behavior; hard to test in isolation; controller intent is clearer | Explicit controller call is more readable and testable |

---

## Consequences

### Positive

- `EstimateTotalsCalculator` drops its materials query entirely. It now makes one query (labor rates). Line item renders need no material preload.
- `Estimate` model sheds three private methods and two callbacks. The `after_create` seed and the `after_update` tax recalculation are gone.
- The materials controller, views, and associated specs are deleted. A meaningful surface area of complexity is removed.
- Estimators get a catalog-driven workflow: select a product, values pre-fill, override as needed. Freeform entry remains available.
- The line item form now shows material description + price inline — no need to navigate away to a price book.

### Negative

- `line_items` table grows to approximately 50 columns. The model comment block (required by ADR-008) must be kept current.
- Adding a new material slot in future requires a migration on both `products` and `line_items`. This risk exists now and is unchanged.
- The materials price book UI and its specs are deleted. If the shop later wants a global price book (shared across estimates), that is a new feature not covered by this ADR.

### Risks

| Risk | Mitigation |
|------|-----------|
| Estimator sets unit prices on the product once and never updates them; inflation causes old products to underprice | Product edit should be easy to access; "last updated" timestamp visible in the catalog UI |
| `product.apply_to(line_item)` called without checking line item is new (could overwrite estimator overrides on an update) | Controller must only call `apply_to` on new line items or when the estimator explicitly requests "reset from catalog"; guard with a request param |
| Banding unit_price set to non-zero but banding_qty is nil — cost silently applied at 1x | Calculator applies banding_unit_price directly (no qty multiplier per ADR-008); this is correct by design, but the UX should make it clear banding is a per-unit flat cost |
| `product_id` FK retained but values diverge over time — estimator does not know how stale the line item is | Display "based on [product name]" on the line item card without implying current parity |

---

## Schema — Approved Design

### `products` table (new)

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| name | string NOT NULL | e.g. "MDF Base 2-door" |
| category | string | e.g. "Base Cabinets" — plain string, no FK |
| unit | string NOT NULL default 'EA' | |
| exterior_description | string | |
| exterior_unit_price | decimal(12,4) | |
| exterior_qty | decimal(10,4) | |
| interior_description | string | |
| interior_unit_price | decimal(12,4) | |
| interior_qty | decimal(10,4) | |
| interior2_description | string | |
| interior2_unit_price | decimal(12,4) | |
| interior2_qty | decimal(10,4) | |
| back_description | string | |
| back_unit_price | decimal(12,4) | |
| back_qty | decimal(10,4) | |
| banding_description | string | |
| banding_unit_price | decimal(12,4) | no qty — flat per-unit cost |
| drawers_description | string | |
| drawers_unit_price | decimal(12,4) | |
| drawers_qty | decimal(10,4) | |
| pulls_description | string | |
| pulls_unit_price | decimal(12,4) | |
| pulls_qty | decimal(10,4) | |
| hinges_description | string | |
| hinges_unit_price | decimal(12,4) | |
| hinges_qty | decimal(10,4) | |
| slides_description | string | |
| slides_unit_price | decimal(12,4) | |
| slides_qty | decimal(10,4) | |
| locks_description | string | |
| locks_unit_price | decimal(12,4) | |
| locks_qty | decimal(10,4) | |
| other_material_cost | decimal(12,2) | |
| detail_hrs | decimal(8,4) | |
| mill_hrs | decimal(8,4) | |
| assembly_hrs | decimal(8,4) | |
| customs_hrs | decimal(8,4) | |
| finish_hrs | decimal(8,4) | |
| install_hrs | decimal(8,4) | |
| equipment_hrs | decimal(8,4) | |
| equipment_rate | decimal(10,2) | |
| created_at / updated_at | datetime | |

Indexes: `(name)` for search; `(category)` for grouping filter.

### `line_items` table changes

Remove: `exterior_material_id`, `interior_material_id`, `interior2_material_id`, `back_material_id`, `banding_material_id`, `drawers_material_id`, `pulls_material_id`, `hinges_material_id`, `slides_material_id` (9 FK columns, plus all `add_foreign_key` constraints to materials).

Add:
- `exterior_description string`, `exterior_unit_price decimal(12,4)`
- `interior_description string`, `interior_unit_price decimal(12,4)`
- `interior2_description string`, `interior2_unit_price decimal(12,4)`
- `back_description string`, `back_unit_price decimal(12,4)`
- `banding_description string`, `banding_unit_price decimal(12,4)`
- `drawers_description string`, `drawers_unit_price decimal(12,4)`
- `pulls_description string`, `pulls_unit_price decimal(12,4)`
- `hinges_description string`, `hinges_unit_price decimal(12,4)`
- `slides_description string`, `slides_unit_price decimal(12,4)`
- `locks_description string`, `locks_unit_price decimal(12,4)`
- `product_id bigint nullable FK → products ON DELETE SET NULL`

Keep: all `<slot>_qty` columns, `other_material_cost`, all labor and equipment columns, `estimate_id`, `description`, `quantity`, `unit`, `position`.

---

## Implementation Notes

### Product model

```ruby
class Product < ApplicationRecord
  MATERIAL_SLOTS = %i[exterior interior interior2 back banding drawers pulls hinges slides locks].freeze
  LABOR_CATEGORIES = %i[detail mill assembly customs finish install].freeze

  validates :name, presence: true
  validates :unit, presence: true

  # Copies all product values into a line item's flat columns.
  # Does not save — caller is responsible for persisting.
  def apply_to(line_item)
    MATERIAL_SLOTS.each do |slot|
      line_item.public_send(:"#{slot}_description=", public_send(:"#{slot}_description"))
      line_item.public_send(:"#{slot}_unit_price=", public_send(:"#{slot}_unit_price"))
      line_item.public_send(:"#{slot}_qty=", public_send(:"#{slot}_qty")) unless slot == :banding
    end
    LABOR_CATEGORIES.each do |cat|
      line_item.public_send(:"#{cat}_hrs=", public_send(:"#{cat}_hrs"))
    end
    line_item.other_material_cost = other_material_cost
    line_item.equipment_hrs       = equipment_hrs
    line_item.equipment_rate      = equipment_rate
    line_item.unit                = unit
  end
end
```

### LineItemsController copy trigger

```ruby
def create
  @line_item = @estimate.line_items.build(line_item_params)
  if params[:product_id].present?
    product = Product.find(params[:product_id])
    @line_item.product = product
    product.apply_to(@line_item)
    # line_item_params may override product values if the estimator edited the form
    # before submitting — re-apply params after the product copy:
    @line_item.assign_attributes(line_item_params)
  end
  # ... save and respond
end
```

Apply params after `apply_to` so that any estimator edits in the new-line-item form take precedence over the product defaults.

### Calculator — materials query removed

Delete the materials preload from `EstimatesController#show` and replace with:

```ruby
@estimate = Estimate.includes(:line_items).find(params[:id])
```

No material eager-load needed. The calculator constructor no longer loads materials:

```ruby
def initialize(estimate)
  @estimate     = estimate
  @line_items   = estimate.line_items
  @labor_rates  = LaborRate.all.index_by(&:labor_category)  # one query
end
```

### Factory changes

- Delete `:material` factory and all factory traits/helpers that reference materials.
- Remove `skip_material_seeding` trait from `:estimate` factory (no longer needed).
- Add `:product` factory with sensible defaults.
- Update `:line_item` factory to use flat description/unit_price columns instead of material FKs.

### Specs to update

- Delete all specs for `Material`, `MaterialsController`, and any spec that sets up materials price book data.
- Update `EstimateTotalsCalculator` specs: remove materials setup; add direct `<slot>_unit_price` / `<slot>_qty` values to line item fixtures.
- Add `Product` model specs: presence validations; `apply_to` copies all expected columns.
- Add `LineItemsController` specs: creating with a product_id pre-fills values; creating without product_id allows freeform entry.
