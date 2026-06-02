# Spec: Product Presets Auto-Population

**ID:** SPEC-029
**Status:** in-progress
**Priority:** high
**Created:** 2026-05-27
**Author:** spec-agent

---

## Goal

When Blake selects a product on a new line item, the app should auto-populate all material slots (exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides) from the product's stored slot codes, resolved through the estimate's price book. This replicates the Excel Presets tab behavior — adding a product row fills in all defaults instantly — and eliminates the manual slot-by-slot assignment step for every line item.

---

## Non Goals

- Populating the product catalog with slot code data (seeding/data entry is not a code change)
- Bulk-editing slot codes across all products via import
- Per-estimate product preset overrides (the Presets tab is job-agnostic in the Excel model)
- Labor hour presets — already implemented via `Product#apply_to`
- Any changes to SPEC-022 or `LineItemAliasMatcherService` — that spec is finalized
- Slot-specific material assignment where exterior and interior use categorically different material types (future feature)
- Re-resolving existing line items when price book short codes change (a separate, lower-priority action)
- "Reset from product defaults" on an existing line item (out of scope for create-time auto-population)

---

## Definitions

| Term | Definition |
|------|-----------|
| Slot code | A string stored on a product (e.g., `"PL1"`, `"HINGE1"`) identifying which estimate price book entry the product expects for that material slot. Codes are strings, never FK references. |
| Price book | The set of `estimate_materials` records belonging to a specific estimate; each row may have a `short_code` set by the estimator (SPEC-022). |
| Level 1 | The job-specific price book mapping: `estimate_materials.short_code` → material and price for this job. |
| Level 2 | The product-type defaults mapping: `products.<slot>_slot_code` → which short code this product type uses for each slot. |
| `ProductSlotResolver` | New service object that resolves Level 2 (product slot codes) through Level 1 (price book) to assign `estimate_material` IDs to a line item's FK columns. |
| Slot | One of nine named material positions on a line item: exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides. (Locks has no `_material_id` FK; it resolves via `role = "locks"` at calculator time.) |

---

## Interfaces

### Input — `ProductSlotResolver`

- `product` — a `Product` instance with any combination of `*_slot_code` attributes set
- `estimate` — the parent `Estimate` instance whose price book is used for resolution
- `line_item` — an unsaved `LineItem` instance that already has qty and labor defaults applied via `Product#apply_to`

### Output — `ProductSlotResolver`

- The same `line_item` instance, with `*_material_id` attributes assigned for any slot whose code matched a price book entry. Returns the line item. Does not save.

### New columns — `products` table

Ten nullable string columns: `exterior_slot_code`, `interior_slot_code`, `interior2_slot_code`, `back_slot_code`, `banding_slot_code`, `drawers_slot_code`, `pulls_slot_code`, `hinges_slot_code`, `slides_slot_code`, `locks_slot_code`.

### New UI — product edit form

A "Material Slot Codes" section with one labeled text input per slot code column. All inputs are optional.

---

## Rules

R1: Each of the nine material slots on `products` (exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides) has a dedicated nullable string column named `<slot>_slot_code`. A tenth column `locks_slot_code` is added for completeness but is not resolved by `ProductSlotResolver` (locks has no `_material_id` FK on `line_items`).

R2: Slot code columns on `products` store short code strings only — never FK references to `materials` or `estimate_materials`. This preserves the two-level indirection: products use generic codes; resolution happens at estimate time through the price book.

R3: `ProductSlotResolver` loads the estimate's price book once at initialization, indexing by `short_code.downcase`. It performs exact case-insensitive matching — not substring matching — against each product slot code.

R4: For each non-blank slot code on the product, `ProductSlotResolver` looks up the estimate's price book index by `hint.downcase`. If an entry is found, the resolver assigns that `estimate_material.id` to the corresponding `<slot>_material_id` on the line item. If no match is found, the slot is left unchanged (remains nil).

R5: `ProductSlotResolver` does not overwrite a slot with nil. If a product has no slot code for a given slot, that slot on the line item is untouched.

R6: `ProductSlotResolver` does not assign `locks_material_id` (the column does not exist on `line_items`; locks resolves by role at calculator time).

R7: In `LineItemsController#create`, when a product is present, the call order is:
  1. `product.apply_to(line_item)` — sets qty and labor defaults
  2. `ProductSlotResolver.new(product, @estimate).call(line_item)` — resolves material slot IDs
  3. `line_item.assign_attributes(line_item_params)` — estimator-supplied params win last

R8: Estimator-supplied params always take precedence over resolver-assigned values. Any `*_material_id` value explicitly submitted in the form will overwrite what the resolver set.

R9: If the estimate's price book has no entries with matching short codes, the resolver is a no-op. All material slots remain nil. No error is raised and no flash message is shown for unresolved slots.

R10: `ProductSlotResolver` is a separate service from `LineItemAliasMatcherService`. They share the same resolution mechanism (price book lookup by short code) but have different inputs, triggers, and domains.

R11: The product form must include a labeled text input for each `*_slot_code` column under a "Material Slot Codes" section. All inputs are optional. Blank values are stored as null.

R12: The products index and/or show page must display which slot codes are set on a product where they are non-blank (read-only display).

R13: When a line item is created via CSV import and the line item's product is resolved, `ProductSlotResolver` runs in addition to `LineItemAliasMatcherService`. `LineItemAliasMatcherService` runs after `ProductSlotResolver` and may overwrite slot assignments made by the resolver.

---

## Edge Cases

E1: Product has slot codes set but the estimate's price book has no `short_code` values — resolver is a no-op; line item material slots remain nil; no error or warning is surfaced.

E2: Product slot code is set but the short code does not match any price book entry (e.g., product uses `"PULL1"` but the price book has no entry with `short_code = "PULL1"`) — that slot remains nil; other slots that do match are still resolved.

E3: Estimator submits the new line item form with an explicit `pulls_material_id` override — the resolver's assignment is overwritten by `assign_attributes(line_item_params)` in step 3 of the create action; estimator value wins.

E4: Product has a blank (`""`) slot code — resolver skips it; slot remains nil.

E5: Price book has a short code with different casing than the product slot code (e.g., product stores `"pull1"`, price book has `"PULL1"`) — case-insensitive matching resolves correctly.

E6: Line item is created without a product selected (freeform entry) — `ProductSlotResolver` is not called; no material slots are auto-assigned.

E7: Line item is created via CSV import with a product matched by name — `ProductSlotResolver` runs first on the new line item, then `LineItemAliasMatcherService` runs and may overwrite the primary slots (exterior, interior, interior2, back) if a description substring match is found.

E8: `locks_slot_code` is set on a product — the resolver reads it but makes no assignment (no `locks_material_id` column exists on `line_items`). The field is stored and displayed for catalog completeness but has no effect on slot resolution.

---

## Acceptance Criteria

AC-1: Given the products table, ten new nullable string columns are present: `exterior_slot_code`, `interior_slot_code`, `interior2_slot_code`, `back_slot_code`, `banding_slot_code`, `drawers_slot_code`, `pulls_slot_code`, `hinges_slot_code`, `slides_slot_code`, `locks_slot_code`. All default to null. No index is required.

AC-2: Given the product edit form, a "Material Slot Codes" section is present with one labeled text input for each of the ten slot code columns. Labels are clear: "Exterior Slot Code", "Interior Slot Code", "Interior 2 Slot Code", "Back Slot Code", "Banding Slot Code", "Drawers Slot Code", "Pulls Slot Code", "Hinges Slot Code", "Slides Slot Code", "Locks Slot Code". All inputs are optional.

AC-3: Given a product with one or more slot codes entered and saved, the values are persisted to the database. The slot codes are visible on the product show or index page for non-blank values.

AC-4: Given a `Product` instance with `pulls_slot_code: "PULL1"` and an estimate with an `estimate_material` with `short_code: "PULL1"`, when `ProductSlotResolver.new(product, estimate).call(line_item)` is called, then `line_item.pulls_material_id` is set to that `estimate_material.id`.

AC-5: Given a `Product` with `hinges_slot_code: "HINGE1"` and the estimate's price book has no entry with `short_code: "HINGE1"`, when the resolver runs, then `line_item.hinges_material_id` remains nil and no error is raised.

AC-6: Given a `Product` with `exterior_slot_code: "PL1"` and an estimate price book entry with `short_code: "pl1"` (different case), when the resolver runs, then `line_item.exterior_material_id` is assigned (case-insensitive match).

AC-7: Given `LineItemsController#create` is called with a `product_id` and the estimate has a price book with matching short codes, when the line item is saved, then `*_material_id` columns are populated from the product's slot codes via the resolver.

AC-8: Given `LineItemsController#create` is called with a `product_id` and the estimator also submits an explicit `pulls_material_id` param, when the line item is saved, then `pulls_material_id` reflects the estimator's submitted value, not the resolver's value.

AC-9: Given `LineItemsController#create` is called with a `product_id` and the estimate's price book has no short codes, when the line item is saved, then all `*_material_id` columns are nil and the line item is saved without error.

AC-10: Given a freeform line item (no `product_id`), when created, then `ProductSlotResolver` is not invoked and all material slot IDs remain nil.

AC-11: Given a line item created via CSV import with a matched product that has slot codes, when the import runs, then `ProductSlotResolver` is called before `LineItemAliasMatcherService`. Any primary slots assigned by `LineItemAliasMatcherService` (exterior, interior, interior2, back) will overwrite what the resolver set.

AC-12: Given an unauthenticated request to any product route, when the request is received, then it redirects to the login page and no records are modified.

---

## Acceptance Tests

AT1
Given a product with `pulls_slot_code: "PULL1"` and `hinges_slot_code: "HINGE1"`
And an estimate with price book entries `short_code: "PULL1"` and `short_code: "HINGE1"`
And an unsaved line item associated with that estimate
When `ProductSlotResolver.new(product, estimate).call(line_item)` is called
Then `line_item.pulls_material_id` equals the pulls estimate material's id
And `line_item.hinges_material_id` equals the hinges estimate material's id
And `line_item.exterior_material_id` is nil (no exterior slot code set)
Covers: R3, R4, R5

AT2
Given a product with `exterior_slot_code: "PL1"`
And an estimate whose price book has no entry with `short_code: "PL1"`
And an unsaved line item
When the resolver runs
Then `line_item.exterior_material_id` is nil
And no exception is raised
Covers: R4, R9

AT3
Given a product with `exterior_slot_code: "pl1"`
And an estimate with a price book entry where `short_code: "PL1"` (uppercase)
When the resolver runs
Then `line_item.exterior_material_id` is assigned (case-insensitive match)
Covers: R3

AT4
Given a product with no slot codes set (all `*_slot_code` columns are null)
And an estimate with a populated price book
When the resolver runs
Then no `*_material_id` is assigned on the line item
And no error is raised
Covers: R4, R5, R9

AT5
Given an estimate with a price book entry `short_code: "SLIDE1"`
And a product with `slides_slot_code: "SLIDE1"`
When a logged-in estimator creates a new line item selecting that product via the form
Then the saved line item has `slides_material_id` set to the matching estimate material's id
Covers: R7

AT6
Given an estimator creates a new line item selecting a product whose slot codes include `pulls_slot_code: "PULL1"`
And the form also submits `pulls_material_id` pointing to a different estimate material
When the line item is saved
Then `line_item.pulls_material_id` equals the estimator-submitted value, not the resolver's value
Covers: R7, R8

AT7
Given a product with all nine slot codes set
And an estimate whose price book has no `short_code` values at all
When the estimator creates a line item with that product selected
Then all `*_material_id` columns are nil on the saved line item
And the line item is created without error
Covers: R9

AT8
Given a product with `banding_slot_code: "BANDING3"` and `pulls_slot_code: "PULL1"`
And an estimate with `short_code: "BANDING3"` in the price book but no `"PULL1"` entry
When the resolver runs
Then `line_item.banding_material_id` is assigned
And `line_item.pulls_material_id` is nil
Covers: R4, R5

AT9
Given a product with `locks_slot_code: "LOCK1"`
And an estimate with a price book entry `short_code: "LOCK1"`
When the resolver runs
Then no `locks_material_id` assignment is attempted (column does not exist on line_items)
And no error is raised
Covers: R6

AT10
Given a logged-in user visits the product edit form
When they enter "PL1" in the "Exterior Slot Code" field and save
Then the product record has `exterior_slot_code: "PL1"` persisted
And the value is displayed on the product detail or index page
Covers: R11, R12

AT11
Given an unauthenticated user sends a GET request to `/products/:id/edit`
When the request is received
Then it redirects to the login page
Covers: AC-12

---

## Technical Scope

### Data — Migration

Add ten nullable string columns to the `products` table. All default to null. No index required (resolution is always scoped to a single product, done in Ruby).

```
add_column :products, :exterior_slot_code,  :string
add_column :products, :interior_slot_code,  :string
add_column :products, :interior2_slot_code, :string
add_column :products, :back_slot_code,      :string
add_column :products, :banding_slot_code,   :string
add_column :products, :drawers_slot_code,   :string
add_column :products, :pulls_slot_code,     :string
add_column :products, :hinges_slot_code,    :string
add_column :products, :slides_slot_code,    :string
add_column :products, :locks_slot_code,     :string
```

Migration is additive only. No existing data is altered. No rollback concern.

### Service — `ProductSlotResolver` (`app/services/product_slot_resolver.rb`)

```ruby
# Resolves an estimate's price book short codes against a product's slot code
# hints, and assigns matched estimate_material IDs to a line item's FK columns.
#
# Usage:
#   ProductSlotResolver.new(product, estimate).call(line_item)
#
# Does not save. Caller is responsible for persisting the line item.
class ProductSlotResolver
  SLOT_MAP = {
    exterior:  :exterior_slot_code,
    interior:  :interior_slot_code,
    interior2: :interior2_slot_code,
    back:      :back_slot_code,
    banding:   :banding_slot_code,
    drawers:   :drawers_slot_code,
    pulls:     :pulls_slot_code,
    hinges:    :hinges_slot_code,
    slides:    :slides_slot_code,
  }.freeze

  def initialize(product, estimate)
    @product = product
    @code_index = estimate.estimate_materials
                          .where.not(short_code: [nil, ""])
                          .index_by { |em| em.short_code.downcase }
  end

  def call(line_item)
    return line_item if @code_index.empty?

    SLOT_MAP.each do |slot, code_attr|
      hint = @product.public_send(code_attr).to_s.strip.downcase
      next if hint.blank?

      matched = @code_index[hint]
      line_item.public_send(:"#{slot}_material_id=", matched&.id)
    end

    line_item
  end
end
```

Key design decisions:
- Exact match (not substring) — slot codes are precise identifiers, unlike description text matching in SPEC-022
- Builds an in-memory index once per resolver instantiation — O(1) per slot lookup
- Does not touch quantities or labor hours — `Product#apply_to` handles those
- `locks` is excluded from `SLOT_MAP` intentionally — no `locks_material_id` column exists on `line_items`

### Controller — `LineItemsController#create`

Insert `ProductSlotResolver` call after `apply_to` and before `assign_attributes`. The existing call to `assign_attributes(line_item_params)` ensures estimator overrides always win.

```ruby
def create
  product = Product.find_by(id: params.dig(:line_item, :product_id))

  @line_item = @estimate.line_items.new
  if product
    product.apply_to(@line_item)
    ProductSlotResolver.new(product, @estimate).call(@line_item)
  end
  @line_item.assign_attributes(line_item_params)
  @line_item.description = product.name if product && @line_item.description.blank?
  @line_item.product_id = product&.id

  if @line_item.save
    redirect_to edit_estimate_path(@estimate), notice: t(".notice")
  else
    @products = Product.by_category
    render :new, status: :unprocessable_content
  end
end
```

### CSV Import — `LineItemCsvImporter`

When a CSV line item's product is resolved and a `product_id` is set, call `ProductSlotResolver` on the line item before calling `LineItemAliasMatcherService#match`. The description-matching service runs second and may overwrite primary slots (exterior, interior, interior2, back) — this is correct and intentional per E7.

The importer already receives the estimate as context (used by `LineItemAliasMatcherService`). Instantiate `ProductSlotResolver` once per product (or per line item if the product varies). The resolver is cheap (O(price book size) at init, O(1) per slot).

### Model — `Product`

Add the ten slot code columns to the permitted attributes in `ProductsController` strong params. No model-level validations are required — blank and nil values are valid.

Consider adding a `SLOT_CODE_COLUMNS` constant on `Product` mirroring `MATERIAL_SLOTS` for use in forms and the resolver:

```ruby
SLOT_CODE_COLUMNS = %i[
  exterior_slot_code interior_slot_code interior2_slot_code back_slot_code
  banding_slot_code drawers_slot_code pulls_slot_code hinges_slot_code
  slides_slot_code locks_slot_code
].freeze
```

### UI — Product Form (`app/views/products/_form.html.erb`)

Add a "Material Slot Codes" section after the existing Material Slots section. For each of the ten slot code columns, render a labeled text input. Example structure (i18n labels required):

```
Section heading: "Material Slot Codes"
Subheading or hint: "Enter the price book short code this product uses for each material slot."

Exterior Slot Code   [ text input ]
Interior Slot Code   [ text input ]
Interior 2 Slot Code [ text input ]
Back Slot Code       [ text input ]
Banding Slot Code    [ text input ]
Drawers Slot Code    [ text input ]
Pulls Slot Code      [ text input ]
Hinges Slot Code     [ text input ]
Slides Slot Code     [ text input ]
Locks Slot Code      [ text input ]
```

All inputs are optional. No client-side validation required.

### UI — Product Index/Show (read-only display)

On the products index table or product show page, display a compact read-only list of non-blank slot codes alongside the product name or in a details panel. Example: a row of small monospace badges ("PL1", "HINGE1", "PULL1") or a "Slot codes: PL1, HINGE1, PULL1" label. Blank slot codes are omitted from display. This is informational only.

### i18n Keys Required

Add under `config/locales/en.yml`:

```yaml
products:
  form:
    slot_codes_heading: "Material Slot Codes"
    slot_codes_hint: "Enter the price book short code this product uses for each slot."
    exterior_slot_code: "Exterior Slot Code"
    interior_slot_code: "Interior Slot Code"
    interior2_slot_code: "Interior 2 Slot Code"
    back_slot_code: "Back Slot Code"
    banding_slot_code: "Banding Slot Code"
    drawers_slot_code: "Drawers Slot Code"
    pulls_slot_code: "Pulls Slot Code"
    hinges_slot_code: "Hinges Slot Code"
    slides_slot_code: "Slides Slot Code"
    locks_slot_code: "Locks Slot Code"
```

---

## Test Requirements

### Unit Tests — `ProductSlotResolver` (`spec/services/product_slot_resolver_spec.rb`)

Follow the AAA test structure. Use inline variables; no `let` or `before` blocks for domain setup.

- Given a product with `pulls_slot_code: "PULL1"` and a price book entry with `short_code: "PULL1"`, `call` assigns that estimate material's id to `line_item.pulls_material_id`.
- Given a product with `pulls_slot_code: "PULL1"` and no price book entry with `short_code: "PULL1"`, `call` leaves `line_item.pulls_material_id` nil.
- Short code matching is case-insensitive: product stores `"pull1"`, price book has `"PULL1"` — match succeeds.
- Given a product with `exterior_slot_code: nil`, the resolver skips that slot with no error.
- Given a product with `exterior_slot_code: ""` (empty string), the resolver skips that slot.
- Given a price book with no `short_code` values, `call` returns the line item immediately without assigning any slot.
- Given a product with multiple slot codes set and all matching price book entries, all matching `*_material_id` columns are assigned.
- `locks_slot_code` is not processed — no `locks_material_id` assignment attempt is made even when `locks_slot_code` is set and a matching price book entry exists.
- The resolver does not save the line item — after `call`, the line item is not persisted.
- The resolver does not modify qty or labor hour columns.

### Unit Tests — `Product` model additions (`spec/models/product_spec.rb`)

- A product with all `*_slot_code` columns nil is valid.
- A product with `pulls_slot_code: "PULL1"` is valid and persists the value.
- `SLOT_CODE_COLUMNS` constant lists all ten slot code attribute symbols (if added to the model).

### Request Tests — `LineItemsController` (`spec/requests/line_items_spec.rb`)

- `POST /estimates/:estimate_id/line_items` with a `product_id` for a product with `pulls_slot_code: "PULL1"` and an estimate price book entry with `short_code: "PULL1"` — the created line item has `pulls_material_id` set to the matching estimate material's id.
- `POST /estimates/:estimate_id/line_items` with a `product_id` for a product with slot codes and an estimate with no `short_code` values — the line item is created with all `*_material_id` nil; response redirects.
- `POST /estimates/:estimate_id/line_items` with a `product_id` and an explicit `pulls_material_id` param pointing to a different estimate material — the saved `pulls_material_id` reflects the submitted value, not the resolver's value.
- `POST /estimates/:estimate_id/line_items` without a `product_id` — line item is created with all `*_material_id` nil; `ProductSlotResolver` is not called.

### Request Tests — `ProductsController` (`spec/requests/products_spec.rb`)

- `GET /products/:id/edit` — response includes the "Material Slot Codes" form section (assert presence of at least one slot code field label or input name).
- `PATCH /products/:id` with `exterior_slot_code: "PL1"` — updates the product; redirects; `product.reload.exterior_slot_code` equals `"PL1"`.
- `PATCH /products/:id` with `exterior_slot_code: ""` — updates the product; stores null (blank is valid).

### System Tests — `spec/system/product_presets_spec.rb`

Follow the project's Selenium headless Chrome setup and `DatabaseCleaner` truncation strategy.

Scenario 1: Slot code entry and persistence
- A logged-in user visits the product edit page for an existing product.
- The "Material Slot Codes" section is visible.
- The user enters "PULL1" in the "Pulls Slot Code" field and saves.
- The product index or show page displays "PULL1" alongside the product.

Scenario 2: Auto-population on line item create
- A logged-in user has an estimate with a price book entry `short_code: "PULL1"`.
- The product has `pulls_slot_code: "PULL1"`.
- The user creates a new line item, selects the product, and submits.
- On the estimate edit page, the saved line item's pulls slot shows the matched material (price book entry name appears in the pulls slot field on the line item form or card).

Scenario 3: Graceful degradation — no price book match
- A logged-in user has an estimate with no price book short codes.
- The product has slot codes set.
- The user creates a new line item with that product.
- The line item is created without error; all material slots are blank on the line item card.

---

## Implementation Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-27 | Slot code columns are strings on `products`, not FK references | Preserves two-level indirection; codes are job-scoped identifiers, not global material references. See ADR-015. |
| 2026-05-27 | `ProductSlotResolver` is a separate service from `LineItemAliasMatcherService` | Different inputs (product slot codes vs description text), different triggers (create vs import/apply), different semantics. See ADR-015. |
| 2026-05-27 | Resolver uses exact match, not substring | Slot codes are precise identifiers; substring matching is SPEC-022's domain for description text. |
| 2026-05-27 | Estimator params applied last (`assign_attributes` after resolver) | Matches `apply_to` override convention from SPEC-013 / ADR-009. Estimator intent always wins. |
| 2026-05-27 | `locks_slot_code` stored but excluded from resolver's `SLOT_MAP` | `line_items` has no `locks_material_id` column; locks resolves by role at calculator time. Column is included for catalog completeness. |

---

## Dependencies

- SPEC-022 (Material Short Code and Auto-Population) — `estimate_materials.short_code` is the Level 1 mechanism this spec resolves against. Status: ready (merged per ADR-015).
- SPEC-014 (Materials Rework) — `estimate_materials` table, `EstimateMaterial` model, and the nine `*_material_id` FK columns on `line_items` must exist. Status: done.
- SPEC-013 (Product Catalog) — `products` table, `Product` model, `ProductsController`, and `Product#apply_to` must exist. Status: done.
- ADR-015 (Product Presets Auto-Population) — governs all architectural decisions in this spec. Status: proposed.

---

## Proposed Task Breakdown

| Task | ACs Covered | Complexity |
|------|-------------|-----------|
| T1: Migration — add 10 `*_slot_code` columns to `products` | AC-1 | 1 |
| T2: `ProductSlotResolver` service with unit tests | AC-4, AC-5, AC-6, AC-9 | 3 |
| T3: `LineItemsController#create` integration + request tests | AC-7, AC-8, AC-9, AC-10 | 2 |
| T4: Product form — "Material Slot Codes" section + strong params | AC-2, AC-3 | 2 |
| T5: Product index/show — read-only slot code display | AC-3, AC-12 | 1 |
| T6: CSV importer — call `ProductSlotResolver` before `LineItemAliasMatcherService` | AC-11 | 2 |
| T7: System specs — end-to-end scenarios | AT10, AT5, AT6 | 3 |

Total estimated complexity: 14 points. All tasks are 1–3 points and suitable for individual PRs or combined into 2–3 PRs (T1+T2, T3+T6, T4+T5+T7).

---

## Change Log

| Date | Change | Affected IDs | Rationale |
|------|--------|-------------|-----------|
| 2026-05-27 | Initial spec created | All | New feature — product presets auto-population |
