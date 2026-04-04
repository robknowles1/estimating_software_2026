# Spec: Phase 4 — Line Items and Real-Time Totals

**ID:** SPEC-006
**Status:** ready
**Priority:** high
**Created:** 2026-04-04
**Author:** pm-agent

---

## Summary

This is the core estimating loop — the most technically complex phase in the build. Estimators add line items to sections, entering a description, quantity, unit, unit cost, and markup percentage. Extended cost and sell price are calculated and displayed in real time as the estimator types (client-side Stimulus controller), and section subtotals and the estimate grand total update via Turbo Streams whenever a line item is saved, updated, or deleted. No totals are stored in the database; all math lives in `EstimateTotalsCalculator`. After this phase, the app can demonstrate the end-to-end estimating workflow without catalog or print features.

## User Stories

- As an estimator, I want to add line items to a section with a description, quantity, unit, unit cost, and markup so that the estimate reflects actual job scope.
- As an estimator, I want to see extended cost and sell price calculated in real time as I type so that I do not have to do math manually.
- As an estimator, I want section subtotals and a grand total to update automatically when I save a line item so that I always see the current bottom line.
- As an estimator, I want to edit or delete a line item so that I can correct mistakes or adjust scope.
- As an estimator, I want to reorder line items within a section so that the estimate reads in the right sequence.

## Acceptance Criteria

1. Given a section on an estimate, when an estimator clicks "Add line item," a line item entry form or row appears.
2. Given a line item form with quantity and unit_cost entered, the extended cost (quantity × unit_cost) is displayed in real time without a server round-trip.
3. Given a line item form with extended cost and markup_percent entered, the sell price (extended_cost × (1 + markup_percent / 100)) is displayed in real time without a server round-trip.
4. Given a line item form with no description, when submitted, a validation error is shown and the line item is not saved.
5. Given a valid line item is saved, it appears in the section immediately and the section subtotal updates without a full page reload.
6. Given a line item is saved or updated, the estimate grand total updates without a full page reload.
7. Given a line item is deleted, it is removed from the section, the section subtotal updates, and the estimate grand total updates — all without a full page reload.
8. Given multiple line items in a section, the estimator can reorder them using up/down controls. The new order persists on page reload.
9. Given an existing line item, the estimator can click to edit any field. On save, updated values are reflected immediately.
10. Given a line item deletion, a single confirmation step is required before the record is destroyed.
11. Given a new line item is created in a section, `markup_percent` is pre-filled with the section's `default_markup_percent` value.
12. Given a section with line items, the section header displays the section subtotal of sell prices.
13. Given all sections with line items, the estimate footer displays the grand total of all sell prices and the grand total of all extended costs.

## Technical Scope

### Data / Models

- New model: `LineItem`
  - Columns: `id`, `estimate_section_id integer not null FK`, `catalog_item_id integer null FK`, `description string not null`, `quantity decimal(10,4) not null default 0`, `unit string null`, `unit_cost decimal(10,2) not null default 0`, `markup_percent decimal(5,2) not null default 0`, `position integer not null default 0`, `notes text null`, `cost_type string null`, `created_at`, `updated_at`
  - `belongs_to :estimate_section`
  - `belongs_to :catalog_item, optional: true`
  - `acts_as_list scope: :estimate_section`
  - Computed methods (NOT stored columns): `extended_cost` → `quantity * unit_cost`; `sell_price` → `extended_cost * (1 + markup_percent / 100)`
  - Validates presence of `description`; validates numericality of `quantity` (>= 0) and `unit_cost` (>= 0).
  - Indexes: `estimate_section_id`; composite `(estimate_section_id, position)`; `catalog_item_id`.

- New service object: `app/services/estimate_totals_calculator.rb`
  - Public interface: `EstimateTotalsCalculator.new(estimate).section_subtotals` → hash of `{ section_id => { extended_cost: X, sell_price: Y } }`; `.grand_total` → `{ extended_cost: X, sell_price: Y }`.
  - All section and grand total arithmetic lives here. No totals math in view helpers, AR callbacks, or controller actions.

### API / Logic

- `LineItemsController`: nested under `estimate_sections`. Actions: `new`, `create`, `edit`, `update`, `destroy` — all require login.
  - `create` / `update`: respond with Turbo Stream that replaces the line item row, the section subtotal partial, and the estimate grand total partial.
  - `destroy`: respond with Turbo Stream that removes the line item row and updates section subtotal and grand total partials.
  - `create`: pre-fills `markup_percent` from parent `EstimateSection#default_markup_percent` if not provided.
- Reorder action: `PATCH /estimate_sections/:section_id/line_items/:id/move` — accepts `direction: up|down`.
- Routes: nested `resources :line_items` under `estimate_sections`; member route for reorder.

### UI / Frontend

- Line item row partial: `_line_item.html.erb` — displays description, quantity, unit, unit_cost, markup_percent, extended_cost, sell_price, edit/delete controls.
- Section subtotal partial: `_section_subtotal.html.erb` — displays section name, sum of extended_cost, sum of sell_price. Used in section header and updated via Turbo Stream.
- Estimate grand total partial: `_estimate_totals.html.erb` — displays grand total extended_cost and sell_price. Updated via Turbo Stream.
- DOM IDs: use Rails `dom_id` helper consistently. Convention: `dom_id(line_item)`, `dom_id(section, :subtotal)`, `dom_id(estimate, :totals)`. Document this convention in a comment at the top of each partial.
- Stimulus controller: `line_item_calculator_controller.js`
  - Targets: `quantity`, `unitCost`, `markupPercent`, `extendedCost`, `sellPrice`.
  - On any target input event: recalculate and update display values client-side. No server call.
- Line item form: inline in the section (Turbo Frame) or modal — developer's choice, but the section must not require a full page reload to add an item.
- Monetary values formatted with `number_to_currency` in all views.

### Background Processing
- None.

## Test Requirements

### Unit Tests

- `LineItem#extended_cost`: returns `quantity * unit_cost` correctly (including edge case: quantity = 0).
- `LineItem#sell_price`: returns `extended_cost * (1 + markup_percent / 100)` correctly.
- `LineItem#sell_price`: with markup_percent = 0, returns value equal to extended_cost.
- `LineItem`: validates presence of description.
- `EstimateTotalsCalculator#section_subtotals`: returns correct extended_cost and sell_price per section for a known fixture.
- `EstimateTotalsCalculator#grand_total`: sums correctly across multiple sections.

### Integration Tests

- `POST /estimate_sections/:id/line_items` with valid params: creates line item, response includes Turbo Stream replacing section subtotal and estimate totals partials.
- `PATCH /estimate_sections/:id/line_items/:id` with updated unit_cost: response includes Turbo Stream with recalculated totals.
- `DELETE /estimate_sections/:id/line_items/:id`: response removes line item row, updates subtotal and totals.
- `PATCH /estimate_sections/:id/line_items/:id/move` with direction "up": position decrements.
- Line item with blank description returns 422.

### End-to-End Tests

- Full core loop: log in, open an estimate, add a section, add three line items with different quantities and costs, verify grand total equals the sum. Edit one line item's cost, verify the grand total updates immediately.

## Out of Scope

- Catalog autocomplete on the description field (Phase 5).
- Drag-and-drop reordering (Phase 7 polish).
- Storing computed totals in the database.
- `cost_type` UI — the column exists in the schema (forward compatibility) but there is no form field or display logic for it in MVP.

## Open Questions

- OQ-01 (markup level) is resolved by ADR-001: per line item, with section default pre-filling new items.
- OQ-02 (line item UX Pattern C) is conditionally accepted per ADR-005. The data model is UX-agnostic. If the estimator validation session changes the pattern to B (catalog-first), only the frontend form and autocomplete behavior changes — this spec's model and controller work is unaffected.
- No blockers for this phase.

## Dependencies

- SPEC-005 (Phase 3 — Estimates and Sections) must be complete. Line items require an `estimate_section_id`.
- SPEC-002 (Phase 0 — Foundation): `acts_as_list` gem must be in the bundle.

---

## Technical Guidance

**Reviewed by:** architect-agent
**Date:** 2026-04-04
**Relevant ADRs:** [ADR-001](../architecture/ADR-001-markup-level.md), [ADR-003](../architecture/ADR-003-realtime-totals.md), [ADR-005](../architecture/ADR-005-line-item-entry-ux.md)

---

### EstimateTotalsCalculator interface — resolve discrepancy between spec and ADR-003

The spec (Technical Scope) defines the service as:
```ruby
EstimateTotalsCalculator.new(estimate).section_subtotals  # => hash
EstimateTotalsCalculator.new(estimate).grand_total        # => hash
```

ADR-003 (Implementation Notes) defines it as:
```ruby
EstimateTotalsCalculator.new(estimate).call  # => struct with section_subtotals + grand_total_cost + grand_total_sell
```

These are not the same. **Use the ADR-003 interface.** It avoids instantiating the calculator twice when both subtotals and grand total are needed on the same page render. The single `.call` approach is also more idiomatic for a service object. The recommended implementation:

```ruby
# app/services/estimate_totals_calculator.rb
class EstimateTotalsCalculator
  Result = Data.define(:section_subtotals, :grand_total_cost, :grand_total_sell)

  def initialize(estimate)
    @estimate = estimate
  end

  def call
    subtotals = {}
    grand_cost = BigDecimal("0")
    grand_sell = BigDecimal("0")

    @estimate.estimate_sections.includes(:line_items).each do |section|
      section_cost = section.line_items.sum(&:extended_cost)
      section_sell = section.line_items.sum(&:sell_price)
      subtotals[section.id] = { extended_cost: section_cost, sell_price: section_sell }
      grand_cost += section_cost
      grand_sell += section_sell
    end

    Result.new(section_subtotals: subtotals, grand_total_cost: grand_cost, grand_total_sell: grand_sell)
  end
end
```

Use `BigDecimal` for accumulation to avoid floating-point drift. The `LineItem#extended_cost` and `#sell_price` methods return `BigDecimal` because the underlying columns are `decimal` — this is safe as long as ActiveRecord's `decimal` columns are not cast to `Float` anywhere.

---

### LineItem computed methods — use BigDecimal arithmetic explicitly

The spec shows:
```ruby
def extended_cost = quantity * unit_cost
def sell_price    = extended_cost * (1 + markup_percent / 100)
```

`markup_percent / 100` on a `BigDecimal` is fine, but `1 + ...` will produce a `BigDecimal` only if `1` is written as `BigDecimal("1")` or `1.to_d`. In practice, Ruby will upcast the integer `1` when adding to a `BigDecimal`, so this is safe. However, for explicitness:

```ruby
def extended_cost = quantity * unit_cost
def sell_price    = extended_cost * (1 + markup_percent / BigDecimal("100"))
```

Write unit tests with edge cases: `markup_percent = 0`, `quantity = 0`, `quantity = 12.375` (fractional), and a case where rounding would differ between `Float` and `BigDecimal`.

---

### Turbo Stream DOM ID conventions — must match ADR-003 exactly

The spec states `dom_id(section, :subtotal)` and `dom_id(estimate, :totals)`. ADR-003 documents the resulting strings as `subtotal_estimate_section_42` and `totals_estimate_7`. This is correct — Rails `dom_id` prepends the prefix, not appends it. Verify this in a console before building the stream partials:

```ruby
dom_id(EstimateSection.new(id: 42), :subtotal)  # => "subtotal_estimate_section_42"
dom_id(Estimate.new(id: 7), :totals)            # => "totals_estimate_7"
```

Every Turbo Stream `target:` attribute in the controller response and every `id=` in the view partial must use `dom_id` — no hand-written strings. The spec is correct on this point; treat it as a hard rule.

---

### LineItemsController — Turbo Stream response structure

Each mutating action must respond with a stream that targets exactly three DOM regions (per ADR-003):

1. The line item row itself (`dom_id(line_item)` — replace on create/update, remove on destroy).
2. The section subtotal partial (`dom_id(section, :subtotal)` — replace).
3. The estimate grand total partial (`dom_id(estimate, :totals)` — replace).

The section subtotal partial and the grand total partial must each call `EstimateTotalsCalculator.new(estimate).call` independently — or the controller can compute the result once and pass it as a local. Passing it as a local from the controller is preferred:

```ruby
# LineItemsController#create (success path)
@totals = EstimateTotalsCalculator.new(@estimate).call
respond_to do |format|
  format.turbo_stream
  format.html { redirect_to edit_estimate_path(@estimate) }
end
```

Then in `create.turbo_stream.erb`, pass `@totals` into both partials so the calculator is invoked once per request, not once per partial render.

---

### Stimulus controller — targets naming

ADR-003 names the Stimulus targets as `quantityInput`, `unitCostInput`, `markupInput`, `extendedCostDisplay`, `sellPriceDisplay`. The spec names them slightly differently (`quantity`, `unitCost`, `markupPercent`, `extendedCost`, `sellPrice`). These are Stimulus target names, not Ruby symbols, so either is fine — but pick one set and be consistent across the controller and all views that connect to it. Recommendation: use the ADR-003 names since that document was written first and is the reference.

---

### LineItem form — inline Turbo Frame vs. modal

The spec says "developer's choice" between inline Turbo Frame and modal for the line item form. Recommendation: use an inline Turbo Frame inside the section. This avoids layering modals over a page that already has significant interactive content, and it is consistent with the pattern established by EstimateSections (which are also inline forms). A modal approach requires additional Stimulus controller work for open/close/focus management and is harder to test with Capybara.

The Turbo Frame wrapping the "Add line item" form should have a `src` that lazy-loads the new form only when clicked (use a link with `data-turbo-frame` pointing to the frame ID, plus a lazy-loaded `src`). This avoids rendering an empty form for every section on page load.

---

### markup_percent pre-fill from section default

AC-11 requires that `markup_percent` be pre-filled from the section's `default_markup_percent` when creating a new line item. Do this in the controller, not in a model callback:

```ruby
# LineItemsController#new
def new
  @line_item = @estimate_section.line_items.build(
    markup_percent: @estimate_section.default_markup_percent
  )
end

# LineItemsController#create
def create
  @line_item = @estimate_section.line_items.build(line_item_params)
  @line_item.markup_percent ||= @estimate_section.default_markup_percent
  ...
end
```

A model callback (`before_validation`) is tempting but couples the LineItem model to its parent in a way that makes unit testing harder and breaks if a line item is ever created without an associated section (e.g., in tests). Keep this in the controller.

---

### N+1 query risk in estimate edit view

The estimate edit view renders multiple sections, each with line items, and the grand total. Without eager loading, this will fire one query per section for line items plus a calculator query. Use:

```ruby
@estimate = Estimate.includes(estimate_sections: :line_items).find(params[:id])
```

Pass the preloaded estimate to `EstimateTotalsCalculator`. The calculator's `.each` over sections and their line items will use the already-loaded associations without additional queries. This is the most important performance concern in Phase 4.

---

### `cost_type` column — include in migration, omit from form

Per `data-model-review.md` and the spec's Out of Scope section, the `cost_type string null` column should be added to the `line_items` migration for forward compatibility, with no form field or display logic. Add a comment in the migration:

```ruby
t.string :cost_type, null: true  # Reserved for future cost-category reporting (material/labor/sub/etc.). No UI in MVP.
```

---

### Migration checklist

Ensure the migration includes:
- `add_index :line_items, :estimate_section_id`
- `add_index :line_items, [:estimate_section_id, :position]`
- `add_index :line_items, :catalog_item_id`
- `add_foreign_key :line_items, :estimate_sections`
- `add_foreign_key :line_items, :catalog_items` (nullable — PostgreSQL enforces FK constraints by default; include this migration and rely on `optional: true` at the application layer for the nullable association)

---

### Test: `EstimateTotalsCalculator` must test with preloaded vs. unloaded associations

Add a unit test that instantiates the calculator with an estimate where `estimate_sections` and `line_items` are NOT preloaded, to confirm it still produces correct results (no dependency on preloading for correctness). Then add a separate test or benchmark note that the preloaded path is the expected production path.
