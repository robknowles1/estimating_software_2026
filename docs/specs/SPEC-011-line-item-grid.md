# Spec: Line Item Grid — Product Rows and Per-Item Totals

**ID:** SPEC-011
**Status:** ready
**Priority:** high
**Created:** 2026-04-10
**Author:** pm-agent

---

## Summary

This phase delivers the core estimating loop: the product row grid where an estimator adds finished products, assigns material types from the estimate's price book, enters labor hours per trade category, and sees per-item and running totals update via Turbo Streams. Each line item represents one finished product (e.g., "Base 2 Door") and carries the full material breakdown (up to nine component slots) and labor hour breakdown (six labor categories) as flat columns on a single record. The `EstimateTotalsCalculator` is rewritten from scratch for the flat model. After this phase, an estimator can build a complete product list and see non-burdened and burdened totals per item and for the job as a whole.

## User Stories

- As an estimator, I want to add a finished product row to an estimate so that I can capture its material and labor costs.
- As an estimator, I want to assign material types from the estimate's price book to each component slot on a product row so that costs calculate from real quote prices.
- As an estimator, I want to enter labor hours per category for each product row so that labor costs roll up correctly.
- As an estimator, I want to see collapsed product rows by default so that the estimate does not feel overwhelming, and expand individual rows to edit them.
- As an estimator, I want collapsed row headers to show the key totals (material subtotal, labor subtotal, non-burdened total) so that I can scan the estimate without opening every row.
- As an estimator, I want to reorder product rows so that the estimate reads in the order I want to present it.
- As an estimator, I want to delete a product row and see totals update immediately so that scope changes are reflected right away.

## Acceptance Criteria

1. Given an estimate show page, when an estimator clicks "Add Product," a new line item form appears without a full page reload.
2. Given a line item form with no description, when submitted, a validation error is shown and no record is created.
3. Given a valid line item is saved, it appears on the estimate immediately as a collapsed card and the estimate-level non-burdened total updates without a full page reload.
4. Given a collapsed line item card, it displays: description, `quantity × unit`, material subtotal, labor subtotal, and non-burdened total per unit.
5. Given a collapsed line item card, when the estimator clicks to expand it, the full material and labor form is revealed inline. No navigation away from the estimate page occurs.
6. Given an expanded line item form, the Material section shows the following component slots: Exterior (qty + material dropdown), Interior (qty + material), Interior 2nd (qty + material), Back (qty + material), Banding (material dropdown only — no qty field), Drawers (qty + material), Pulls (qty + material), Hinges (qty + material), Slides (qty + material), Locks (qty only — no material dropdown).
7. Given an expanded line item form, material dropdowns are populated exclusively from the current estimate's seeded material slots, grouped by category (Sheet Goods, Hardware).
8. Given an expanded line item form, the Labor section shows input fields for: Detail (hrs), Mill (hrs), Assembly (hrs), Customs (hrs), Finish (hrs), Install (hrs).
9. Given an expanded line item form, an Equipment section shows: Equipment Hours and Equipment Rate fields.
10. Given a line item is saved with material quantities and types assigned, the material subtotal for that item is calculated as the sum of `(component_qty * material.cost_with_tax)` over all assigned component slots, plus `locks_qty * locks_material.cost_with_tax` (looked up by slot_key "LOCKS"), plus `other_material_cost`. The displayed value is correct to two decimal places.
11. Given a line item is saved with labor hours, the labor subtotal is calculated as `sum of (hrs * labor_rate)` for each labor category where hrs > 0, using the `labor_rates` table. The displayed value is correct to two decimal places.
12. Given a line item is saved or updated, the per-item non-burdened total displayed on the collapsed card equals `(material_subtotal + labor_subtotal + equipment_total) * quantity`. The estimate-level grand non-burdened total also updates.
13. Given multiple line items, the estimator can reorder them using up/down controls. The new order persists after page reload.
14. Given a line item delete button is clicked, a confirmation step is required. On confirmation, the line item is removed and estimate totals update without a full page reload.
15. Given an `other_material_cost` value entered on a line item, it is included in the material subtotal calculation for that item.

## Technical Scope

### Data / Models

The `line_items` table was created in SPEC-010. This phase populates its model, associations, and calculation logic.

#### `LineItem` (new model)
- `belongs_to :estimate`
- Material associations (all `optional: true`): `belongs_to :exterior_material, class_name: "Material"`, and equivalent for `interior`, `interior2`, `back`, `banding`, `drawers`, `pulls`, `hinges`, `slides`. No association for locks — the LOCKS slot is looked up by `slot_key` at calculation time.
- `acts_as_list scope: :estimate`
- Validations: `description` presence; `quantity` numericality `> 0`; `unit` presence.
- All foreign keys on material associations set at the DB level to `ON DELETE SET NULL` (established in SPEC-010 migrations).
- Model comment block documenting the three column groups: Identity (description, quantity, unit, position), Materials (exterior through other_material_cost), Labor/Equipment (detail_hrs through equipment_rate). This comment is required per ADR-008 consequences.

#### `EstimateTotalsCalculator` (full rewrite at `app/services/estimate_totals_calculator.rb`)

Complete replacement of the prior calculator. The new calculator:

1. Loads all `Material` records for the estimate, indexed by `id` (one query).
2. Loads the LOCKS material for the estimate by `slot_key: "LOCKS"` (included in the above query — index the materials hash by `id`, also build a hash by `slot_key` for the LOCKS lookup).
3. Loads all `LaborRate` records, indexed by `labor_category` (one query, memoized).
4. For each `LineItem`:
   - `material_cost_per_unit` = sum of `(component_qty.to_d * materials[component_material_id]&.cost_with_tax.to_d)` for each of the nine typed component slots + `(locks_qty.to_d * locks_material&.cost_with_tax.to_d)` + `other_material_cost.to_d`.
   - `subtotal_materials` = `material_cost_per_unit * quantity`.
   - Per-category labor subtotals: `detail_subtotal = detail_hrs.to_d * labor_rates["detail"].hourly_rate.to_d * quantity`, etc. for all six categories.
   - `equipment_total` = `equipment_hrs.to_d * equipment_rate.to_d * quantity`.
   - `non_burdened_total` = `subtotal_materials + sum(all six labor subtotals) + equipment_total`.
5. Sums all line item `non_burdened_total` values → `grand_non_burdened_total`.
6. Burden multiplier: `(1 + profit_overhead_percent / 100) * (1 + pm_supervision_percent / 100)` (job-level fixed costs and final burdened total are SPEC-012 scope).
7. Returns a value object (plain Ruby struct or `Data.define(...)`) with: `line_item_results` (array or hash keyed by line_item_id), `grand_non_burdened_total`, `burden_multiplier`.

All arithmetic uses `BigDecimal`. No `Float`. `nil` component values are treated as zero.

Public interface: `EstimateTotalsCalculator.new(estimate).call` returns the value object. The calculator eagerly loads all materials and labor rates; it must not fire per-item queries inside the loop.

### API / Logic

- `LineItemsController`: scoped to parent estimate. Actions: `new`, `create`, `edit`, `update`, `destroy` — all require login. Route: `resources :estimates do; resources :line_items; end`.
  - `create` / `update`: respond with Turbo Stream that: (a) replaces or inserts the line item card partial (`dom_id(@line_item)`), (b) updates the estimate totals partial (`estimate_<id>_totals`). On validation failure: respond with Turbo Stream that replaces the form with errors, or render unprocessable entity.
  - `destroy`: respond with Turbo Stream that removes the line item card and updates the estimate totals partial.
- Reorder action: `PATCH /estimates/:estimate_id/line_items/:id/move` — accepts `direction: up|down`, calls `acts_as_list` `move_higher` / `move_lower`, responds with redirect (303 See Other) or a Turbo Stream that re-renders the full line items list.
- Strong params: all columns from the `line_items` schema except calculated fields and `estimate_id` (set from route).

### UI / Frontend

- Estimate show page: the main content area renders the line items list followed by an estimate totals summary partial. "Add Product" button triggers the new line item form (Turbo Frame or inline).
- Line item card partial (`_line_item.html.erb`): accordion/card pattern. Collapsed state (default): description, `qty × unit`, material subtotal, labor subtotal, non-burdened total, edit/delete controls, expand toggle. Expanded state: full material + labor form rendered inside the same card. Use a Stimulus controller (`line_item_accordion_controller.js`) to toggle expanded/collapsed state client-side without a server round-trip.
- Line item form partial (`_form.html.erb`): Material section with labeled subsections per component type. Labor section. Equipment section. Per AC-6, Banding shows no qty field, Locks shows no material dropdown.
- Material dropdowns: grouped `<select>` — optgroup "Sheet Goods" and optgroup "Hardware" — populated from the estimate's materials, displaying the slot label (or slot_key) and the `cost_with_tax` as a hint. Use Rails `grouped_collection_select` or a custom helper.
- Estimate totals partial (`_estimate_totals.html.erb`): DOM id `estimate_<id>_totals`. Displays grand non-burdened total. In this phase, shows a note that job-level costs and burdened total are added in the next phase.
- Per-item totals in collapsed view are derived from `EstimateTotalsCalculator` results and passed into the partial — do not call the calculator per item; call it once per estimate render and distribute results.
- All monetary values formatted with `number_to_currency`. All i18n strings in `config/locales/en.yml`.
- Error states: inline validation errors on the expanded form. Empty state on estimate show: "No products added yet."

### Background Processing
- None.

## Test Requirements

### Unit Tests

- `LineItem`: validates presence of `description`; numericality of `quantity > 0`; presence of `unit`.
- `LineItem`: `acts_as_list` inserts at the bottom of the estimate's list on create.
- `EstimateTotalsCalculator`: given one line item with known material prices and labor rates, returns correct `material_cost_per_unit`, `subtotal_materials`, per-category labor subtotals, `non_burdened_total`.
- `EstimateTotalsCalculator`: nil material assignments on a line item contribute zero to `material_cost_per_unit`.
- `EstimateTotalsCalculator`: `locks_qty` with a non-null LOCKS slot price is included in material cost.
- `EstimateTotalsCalculator`: `other_material_cost` is included in material subtotal.
- `EstimateTotalsCalculator`: uses `BigDecimal` — no floating point rounding errors on standard test inputs.
- `EstimateTotalsCalculator`: fires exactly two queries (materials + labor rates) regardless of the number of line items on the estimate.

### Integration Tests

- `POST /estimates/:id/line_items` with valid params: creates line item, responds with Turbo Stream that includes the line item card and updated totals.
- `POST /estimates/:id/line_items` without description: returns 422, responds with Turbo Stream containing validation errors.
- `PATCH /estimates/:id/line_items/:id` with updated quantity: updates record, Turbo Stream updates the card and totals.
- `DELETE /estimates/:id/line_items/:id`: destroys record, Turbo Stream removes the card and updates totals.
- `PATCH /estimates/:id/line_items/:id/move` with direction "up": decrements position.
- `GET /estimates/:id`: renders line items list (no N+1 queries — verify with bullet or query count assertion).

### End-to-End Tests

- Create an estimate, set up material prices for at least three slots, then add two product rows with material types and labor hours assigned. Confirm: collapsed cards show correct material and labor subtotals; estimate totals partial updates after each save.
- Delete a product row. Confirm: card disappears and estimate totals update without a page reload.
- Reorder two product rows. Confirm: new order persists after page reload.

## Out of Scope

- Job-level cost fields and final burdened total (SPEC-012).
- COGS breakdown by category (SPEC-012).
- PDF output (SPEC-013).
- Drag-and-drop reordering of line items (Phase 7 polish — up/down controls are sufficient for this phase).
- Real-time per-item total recalculation as the estimator types (deferred — totals update on save via Turbo Stream; live client-side calculation is Phase 7 polish).
- Adding new component slot types (requires a migration and is not in scope for any current phase).

## Open Questions

- **OQ-B (from ADR-008, should be resolved before this phase ships):** Is banding a type-only selection (no qty) per the ADR, or does the shop enter a linear-foot quantity? This phase implements type-only per AC-6. If the answer is "qty required," a schema change is needed before this spec ships. Developer must confirm before writing the banding form field.
- **OQ-C (from ADR-008, non-blocking):** Mileage rate for installer travel calculations. Relevant to SPEC-012, not this phase.
- **OQ-F (from ADR-008, non-blocking):** Is the job-level equipment cost field distinct from per-line-item `equipment_hrs`/`equipment_rate`? No action needed in this phase — per-line-item equipment fields are implemented here as specified.
- **UX open question (non-blocking):** Should expanded line item forms auto-save on field blur (Turbo Stream), or require an explicit "Save" button click? The spec defaults to an explicit Save button. If auto-save is preferred, the developer should confirm with the estimator before building the Stimulus controller.

## Dependencies

- SPEC-010 must be complete. The `line_items` table, `materials` table, and material slot seeding must exist. The estimate layout and navigation shell must be in place.
- `acts_as_list` gem must be in the bundle (SPEC-002).
- `LaborRate` seed data must be updated per the SPEC-010 migration step (detail $65, mill $100, assembly $45, customs $65, finish $75, install $80).

---

## Technical Guidance

**Reviewed by:** architect-agent (via ADR-008)
**Relevant ADRs:** ADR-008 (Decision 2 — flat columns; Decision 3 — no stored calculated fields; Decision 4 — string slot_key)

---

### Calculator isolation — do not call it per-item

`EstimateTotalsCalculator.new(estimate).call` must be called once per page render (or once per Turbo Stream response), never once per line item. The controller should call the calculator and pass the result object into view locals:

```ruby
@totals = EstimateTotalsCalculator.new(@estimate).call
render partial: "estimate_totals", locals: { estimate: @estimate, totals: @totals }
```

The calculator must preload its own data internally. It should not accept line items or materials as constructor arguments — it loads what it needs.

---

### Turbo Stream DOM ID conventions (from ADR-008)

- Line item cards: `dom_id(@line_item)` → `line_item_<id>`
- Estimate totals partial: `id="estimate_<id>_totals"` — set this id in the partial's root element, not via `dom_id`.
- Do not use section-scoped IDs — there are no sections in this model.

---

### Accordion without a round-trip

The collapsed/expanded toggle must not require a server round-trip. Use a Stimulus controller (`line_item_accordion_controller.js`) with a `toggle` action bound to the card header. The expanded form content should be in the DOM from the initial page load (or Turbo Stream insert), with CSS classes controlling visibility. Do not use a Turbo Frame for the accordion open/close — that would fire a GET request on every expand.

---

### N+1 prevention on estimate show

The estimate show page renders all line items and their associated materials. Eager load:

```ruby
@estimate = Estimate.includes(:materials, line_items: [:exterior_material, :interior_material, :interior2_material, :back_material, :banding_material, :drawers_material, :pulls_material, :hinges_material, :slides_material]).find(params[:id])
```

The calculator also loads materials by id, so the materials are already in memory. Pass `@estimate` with preloaded associations to the calculator.

---

### BigDecimal in the calculator

All numeric fields on `line_items` and `materials` are `decimal` columns and arrive from ActiveRecord as `BigDecimal`. Do not convert to `Float` at any point in the calculator. Null-guard with `.to_d` (returns `0.0` as BigDecimal for nil). The final value object should expose `BigDecimal` values; formatting to currency string happens only in the view layer via `number_to_currency`.
