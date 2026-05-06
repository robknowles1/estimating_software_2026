# Spec: Tom Select on Line Item Form — Product Selector + All Material Slots + Inline Find-or-Create

**ID:** SPEC-019
**Status:** done
**Priority:** medium
**Created:** 2026-04-27
**Author:** pm-agent

**Unblocked:** SPEC-018 was merged in PR #26 (commit `8ce97c3`, 2026-05-05). The `other_material_id` column, the `other` slot row in `_form.html.erb`, and the `material_slot_other` i18n key are all in place.

---

## Summary

The line item form currently uses plain `collection_select` dropdowns for both the product selector and all material slot selectors. With a large product catalog or a well-stocked price book these lists become unwieldy to scroll. This spec replaces: (1) the product selector with a Tom Select searchable combobox (search-only, no create), and (2) all 10 material slot selectors — the 8 named slots (exterior, interior, interior2, back, drawers, pulls, hinges, slides), plus banding, plus the new "other" slot added in SPEC-018 — with Tom Select comboboxes that include inline find-or-create. When a user types a material name that does not exist in the estimate's price book, a small inline form appears within the dropdown allowing them to create the material on the spot — no page redirect and no modal. The locks slot has no selector and is not touched.

---

## User Stories

- As an estimator, I want to type part of a product name in the product selector and see matching results filtered instantly, so that I can find the right product without scrolling a long grouped list.
- As an estimator, I want the product description field to auto-populate when I pick a product from the combobox, so that I do not have to type it manually.
- As an estimator, I want to type part of a material name in any material slot and see only matching price book materials, so that I can locate the right material quickly when the price book contains many items.
- As an estimator, I want to add a brand-new material to the price book directly from within a material slot combobox without leaving the line item form, so that I do not have to interrupt my workflow to visit the price book separately.
- As an estimator, I want the inline create form to show me a clear error if I omit the cost, so that I know what to fix without losing what I typed.

---

## Acceptance Criteria

### Change 1 — Product Selector

1. Given the line item new/edit form, when the page renders, then the product `<select>` element is enhanced with Tom Select via a new `product-combobox` Stimulus controller (distinct from `product_selector_controller.js` which handles the fill behaviour and must continue to work). The existing `data-product-selector-target="select"` and `data-action="change->product-selector#fill"` attributes on the element are retained so description auto-population continues to fire. Tom Select is initialised with `create: false`.

2. Given the product combobox, when a user types characters, then Tom Select filters the product list in real time using client-side search across product names (the full option list is pre-rendered in the `<select>`; Tom Select searches the existing options, not a server endpoint).

3. Given the product combobox, when a user selects a product, then the `product-selector#fill` action fires (because the native `change` event is still dispatched by Tom Select on item add) and the description field populates as before, with no regression in existing behaviour.

4. Given the product combobox, when no products match the typed text, then Tom Select renders a "No products found" message. The text for this message is sourced from an i18n key `line_items.form.product_combobox_no_results`.

5. Given the product combobox placeholder, when no product is selected, then the placeholder text is sourced from an i18n key `line_items.form.product_combobox_placeholder`.

### Change 2 — Material Slot Comboboxes (search only, no create yet)

6. Given the line item form materials section, when the page renders, then each of the 10 selector slots — exterior, interior, interior2, back, drawers, pulls, hinges, slides, other, and banding — has its plain `collection_select` replaced by a Tom Select combobox managed by a new `material-slot` Stimulus controller (`app/javascript/controllers/material_slot_controller.js`). This controller is distinct from `material_combobox_controller.js`. The controller must initialise Tom Select **without** a `dropdownParent` option — the dropdown is anchored to `.ts-wrapper` (Tom Select's default) so that it scrolls with the form and repositions correctly inside the `overflow-y-auto` main container. Setting `dropdownParent: 'body'` caused the dropdown to detach from its trigger and misalign during scroll; it was removed as a bug fix (see commit `fa545f7`).

7. Given a material slot combobox, when a user types characters, then Tom Select filters the pre-loaded price book options client-side in real time. Options are pre-rendered in the underlying `<select>` as before; Tom Select searches them. No server round-trip occurs for filtering.

8. Given a material slot combobox, when a user clears the selection (selects the blank option), then `line_item[<slot>_material_id]` is submitted as an empty string and the slot is saved as `nil` in the database, with no change to existing behaviour.

9. Given a material slot combobox, when no price book materials match the typed text, then Tom Select renders an inline "Add '<typed text>'" option in place of a standard no-results message (this is the entry point for Change 3 — inline find-or-create). The "Add" option text uses the i18n key `line_items.form.material_slot_add_option` with interpolation: `"Add '%{name}'"`.

9a. Given the estimate has no materials in its price book, when the user opens a material slot combobox and types any text, then the "Add '[name]'" option is shown (the find-or-create path is always available). The `material_slot_no_results` key is NOT rendered in this case — the custom "Add" option replaces it entirely.

### Change 3 — Inline Find-or-Create on Material Slot Comboboxes

10. Given a material slot combobox showing an "Add '<name>'" option, when the user selects that option, then an inline create form appears within the Tom Select dropdown (not a modal, not a page navigation). The form contains: (a) a text field pre-filled with the typed name, labelled via `line_items.form.inline_create_name_label`; (b) a cost field (numeric, step 0.01, min 0), labelled via `line_items.form.inline_create_cost_label`; (c) a confirm button labelled via `line_items.form.inline_create_confirm_button`; (d) a cancel link/button labelled via `line_items.form.inline_create_cancel_button`. Cancelling closes the inline form and returns the combobox to its normal state with the typed text cleared.

10a. Given the inline create panel is visible inside the dropdown, when the user clicks into the cost input field, then the dropdown remains open. The panel's `mousedown` event does not propagate to Tom Select's document-level close handler — achieved by calling `event.stopPropagation()` on the panel container.

11. Given the inline create form, when the user clicks Confirm, then the `material-slot` Stimulus controller sends a `fetch` POST request (JSON body) to a new endpoint `POST /estimates/:estimate_id/estimate_materials/inline_create` with params `material[name]`, `material[cost]`, and no page reload occurs.

12. Given the inline create endpoint receives valid params (`material[name]` present, `material[cost]` a non-negative decimal), when it processes the request, then:
    - A new `Material` record is created in the global library with the given name and `default_price` set to the entered cost. `category` defaults to `"hardware"` (the least restrictive valid value) and `unit` defaults to `"EA"` since the inline form does not expose those fields.
    - A new `EstimateMaterial` record is created linking that material to the estimate with `quote_price` equal to the entered cost. `cost_with_tax` is computed by the existing `before_save` callback.
    - The endpoint returns HTTP 201 with a JSON body: `{ "id": <estimate_material.id>, "name": "<material.name>", "display": "<material.name> ($<formatted quote_price>)" }`.
    - The endpoint does not redirect and does not render HTML.

13. Given the inline create endpoint returns HTTP 201, when the `material-slot` controller receives the response, then it programmatically adds a new option to the Tom Select instance with value `<estimate_material.id>` and display text from `response.display`, selects it immediately, and closes the dropdown. The line item form is now ready to save with the new `estimate_material.id` in the slot.

14. Given the inline create endpoint receives invalid params (e.g. blank name or blank cost), when it processes the request, then it returns HTTP 422 with a JSON body `{ "errors": ["<message>", ...] }` — one entry per validation failure. The `material-slot` controller renders these error messages inside the inline create form (below the cost field) without closing the dropdown. The user can correct the inputs and try again.

15. Given the inline create flow creates a new `Material` and `EstimateMaterial`, when the line item form is subsequently saved, then the new `estimate_material.id` is present in the submitted params and the line item saves with the correct slot populated, producing the correct `material_cost_per_unit` in the totals calculator.

16. Given a concurrent duplicate: if the typed material name already exists in the `Material` table (case-insensitive), when the inline create endpoint processes the request, then it creates a new `Material` record regardless (it does not deduplicate by name — names are not unique in the global library). A later deduplication UX is out of scope.

17. Given the inline create endpoint, when the request is received, then it is protected by `require_login` (inherited from `ApplicationController`) and scoped to the estimate via `Estimate.find(params[:estimate_id])`. An unauthenticated request receives HTTP 302 (redirect to login — `require_login` redirects, it does not render 401) and a request with an invalid `estimate_id` receives HTTP 404. The `Estimate.find` call is unscoped — any authenticated user can POST to another user's estimate. This ownership gap is inherited by design (ADR-014, decision 6) and tracked as pre-production tech debt; no code comment is required in the controller.

### General / Cross-Cutting

18. Given all Tom Select instances on the line item form, when the controller disconnects (Turbo navigation), then `tomSelect.destroy()` is called on each instance to prevent memory leaks, following the same pattern as `material_combobox_controller.js`.

19. Given the line item form, when it is submitted after one or more material slots have been set via Tom Select, then the submitted `line_item[<slot>_material_id]` values are identical to what a plain `collection_select` would have submitted — Tom Select writes back to the original `<select>` element and Rails strong params accept the values unchanged.

20. Given all new user-facing strings (placeholders, no-results messages, inline form labels, button text), when they are rendered, then every string is sourced from `config/locales/en.yml` under `line_items.form` — no hardcoded English strings appear in views or controller files.

---

## Technical Scope

### Data / Models

No schema changes. No model changes. The `Material` validation requires `category` to be `"sheet_good"` or `"hardware"` — the inline create endpoint must supply `"hardware"` as the default. The `Material` validation requires `default_price >= 0` — the endpoint must validate the cost field before attempting to save.

### API / Logic

**New endpoint: `POST /estimates/:estimate_id/estimate_materials/inline_create`**

- Route: add `member` or `collection` route in `config/routes.rb`. Prefer a collection route: `post :inline_create, on: :collection` under the `estimate_materials` resource.
- Action location: add `inline_create` action to `EstimateMaterialsController`.
- Auth: inherited `require_login` before action already covers it.
- Scope: `@estimate = Estimate.find(params[:estimate_id])` (existing `set_estimate` before action covers it). **Security note:** `Estimate.find` here is unscoped — any authenticated user can POST to another user's estimate. This ownership gap is inherited by design (ADR-014, decision 6) and tracked as pre-production tech debt. Do not attempt to fix it in SPEC-019; it has a dedicated remediation track. No inline code comment is required.
- Params: `params.require(:material).permit(:name, :cost)` — note `cost` maps to `default_price` on `Material` and `quote_price` on `EstimateMaterial`. `unit` is not permitted via params; the controller sets it as a hardcoded default (see transaction pattern below).
- Transaction: wrap `Material#save` and `EstimateMaterial#save` in a single `ActiveRecord::Base.transaction` block. Collect errors into variables declared before the block so they are accessible after a rollback. Use the following pattern:

```ruby
material_errors = []
em_errors = []

ActiveRecord::Base.transaction do
  material = Material.new(inline_create_params.merge(category: "hardware", unit: "EA", default_price: 0))
  unless material.save
    material_errors = material.errors.full_messages
    raise ActiveRecord::Rollback
  end

  em = @estimate.estimate_materials.build(material: material, quote_price: inline_create_params[:cost])
  unless em.save
    em_errors = em.errors.full_messages
    raise ActiveRecord::Rollback
  end

  render json: { id: em.id, name: material.name }, status: :created and return
end

render json: { errors: material_errors + em_errors }, status: :unprocessable_entity
```

Note: `em.id` not `material.id` — the form params hold `estimate_material.id` values, not `material.id`.

- Response format: always `render json:`, never `render` an HTML template. Set `Content-Type: application/json`.
- On success (HTTP 201): `{ id: em.id, name: material.name, display: "#{material.name} ($#{sprintf('%.2f', em.quote_price)})" }`.
- On validation failure (HTTP 422): `{ errors: material_errors + em_errors }`.
- The existing `new_material_params` private method in `EstimateMaterialsController` is not reused because it permits different fields; define a separate private method `inline_create_params`.

**`config/routes.rb`**: add `post :inline_create, on: :collection` inside the `estimate_materials` nested resource block. The `collection do` block is added alongside the existing `only: [...]` array — the `only:` restriction applies only to the 7 standard CRUD routes and does not prevent collection routes added via `collection do`.

### UI / Frontend

**New Stimulus controller: `app/javascript/controllers/product_combobox_controller.js`**

- Wraps the existing product `<select>` with Tom Select (`create: false`). No `dropdownParent` option — the dropdown is anchored to `.ts-wrapper` so it scrolls with the form correctly inside the `overflow-y-auto` container (see AC#6 rationale).
- Reads placeholder and no-results text from `data-` values on the controller element (set in the view from i18n).
- Does not handle the `fill` behaviour — that remains in `product_selector_controller.js` which listens to the native `change` event, which Tom Select continues to dispatch.
- Destroys Tom Select on `disconnect()`.

**New Stimulus controller: `app/javascript/controllers/material_slot_controller.js`**

- Wraps a material slot `<select>` with Tom Select (`create: false` initially, but with a custom `no_results` render that shows an "Add" option and triggers the inline create panel).
- Reads from `data-` values: `inline-create-url` (the `inline_create` endpoint URL, rendered in the view), `placeholder` text, `add-option-template` text (the "Add '%{name}'" pattern with the name interpolated client-side).
- On "Add" option selected: renders an inline HTML panel inside the Tom Select dropdown with name field, cost field, confirm button, cancel button. Uses standard DOM manipulation (no separate framework). The panel container must call `event.stopPropagation()` on its `mousedown` event to prevent Tom Select's document-level close handler from collapsing the dropdown when the user clicks into the cost input or other panel elements.
- On Confirm: calls `fetch` with `method: "POST"`, `Content-Type: application/json`, body `JSON.stringify({ material: { name, cost } })`, includes CSRF token from `document.querySelector('meta[name="csrf-token"]').content` as `X-CSRF-Token` header.
- On 201 response: parses JSON, calls `this.tomSelect.addOption({ value: data.id, text: data.display })`, calls `this.tomSelect.setValue(data.id)`, calls `this.tomSelect.close()`.
- On 422 response: renders `data.errors` as a list inside the inline panel; does not close the dropdown.
- Destroys Tom Select on `disconnect()`.

**`app/views/line_items/_form.html.erb`**

- Product selector `<select>`: add `data-controller="product-combobox"`, `data-product-combobox-placeholder-value="<i18n>"`, `data-product-combobox-no-results-value="<i18n>"`. Retain existing `data-product-selector-target` and `data-action` attributes.
- Material slot `<select>` elements (all 10 — exterior through banding, plus other from SPEC-018): replace `f.collection_select` with the same `collection_select` but add `data-controller="material-slot"`, `data-material-slot-inline-create-url-value="<%= inline_create_estimate_estimate_materials_path(estimate) %>"`, `data-material-slot-placeholder-value="<i18n>"`, `data-material-slot-add-option-template-value="<i18n>"`.
- No structural layout changes to the form grid.

**`config/locales/en.yml`** — add the following keys under `line_items.form`:

```yaml
product_combobox_placeholder: "— search products —"
product_combobox_no_results: "No products found"
material_slot_placeholder: "— search price book —"
material_slot_add_option: "Add '%{name}'"
inline_create_name_label: "Material name"
inline_create_cost_label: "Cost ($)"
inline_create_confirm_button: "Add to price book"
inline_create_cancel_button: "Cancel"
inline_create_error_heading: "Could not create material:"
```

**`config/importmap.rb`**: no changes needed — Tom Select is already pinned.

### Background Processing

None.

---

## Test Requirements

### Unit Tests

**`spec/models/material_spec.rb`** (existing file — add cases):
- A `Material` with `category: "hardware"` and `default_price: 0` is valid (confirms the inline create default values satisfy model validations).

### Integration Tests (Request Specs)

**`spec/requests/estimate_materials_spec.rb`** (new or existing file — add cases):

Happy path:
- `POST /estimates/:id/estimate_materials/inline_create` with `material[name]: "Test Birch"` and `material[cost]: "42.50"` returns HTTP 201, Content-Type includes `application/json`, response body contains `id` (integer), `name` ("Test Birch"), and `display` matching `/Test Birch \(\$42\.50\)/`.
- After the request, a `Material` record named "Test Birch" with `default_price: 42.50` exists in the database and an `EstimateMaterial` linking it to the estimate with `quote_price: 42.50` exists.

Error cases:
- `POST /estimates/:id/estimate_materials/inline_create` with `material[name]: ""` (blank name) returns HTTP 422 and response body contains `errors` array with at least one entry matching `/Name/i`.
- `POST /estimates/:id/estimate_materials/inline_create` with `material[cost]: ""` (blank cost) returns HTTP 422 and response body contains `errors` array with at least one entry.
- `POST /estimates/:id/estimate_materials/inline_create` without authentication returns HTTP 302 (redirect to login) — `require_login` redirects, it does not render 401. Relies on existing `require_login` behaviour.

### End-to-End Tests (System Specs)

**`spec/system/line_items_spec.rb`** — add three new scenarios:

**Scenario A — Product combobox filters and fills description:**
Given an estimate with at least one product in the catalog, when a user opens the new line item form, types the first few characters of a product name into the product combobox, and selects the matching option, then the description field contains the product name.

**Scenario B — Material slot combobox filters price book:**
Given an estimate with at least two materials in its price book, when a user opens the line item edit form, clicks the exterior slot combobox, and types characters that match only one of the two materials, then only the matching material appears in the dropdown.

**Scenario C — Inline find-or-create full flow:**
Given an estimate with no material named "Acrylic Panel" in its price book, when a user opens the line item new/edit form, types "Acrylic Panel" into the exterior slot combobox, selects the "Add 'Acrylic Panel'" option, fills in cost "28.00", and clicks "Add to price book", then:
- The exterior slot combobox shows "Acrylic Panel ($28.00)" as the selected value.
- The user saves the line item (clicks the submit button). After clicking submit, wait for the page redirect and re-render before asserting database state (line item form submissions redirect on success).
- The saved line item has `exterior_material_id` set to the newly created `EstimateMaterial`'s id.
- A `Material` record named "Acrylic Panel" exists in the database.
- An `EstimateMaterial` linking that material to the estimate with `quote_price: 28.00` exists.
- The line item card on the estimate edit page shows a non-zero material cost (confirming the calculator picked up the new slot value).

**Scenario D — Inline create error handling:**
Given an estimate, when a user types "Cedar Ply" into a material slot combobox, selects "Add 'Cedar Ply'", leaves the cost field blank, and clicks "Add to price book", then an error message appears inside the dropdown without the dropdown closing, and no `Material` record named "Cedar Ply" is created in the database.

---

## Out of Scope

- Converting the Locks slot (it has no material selector — only a qty field; this is unchanged).
- Deduplicating materials by name during inline create — if a material with the same name already exists in the global library, a second record is created. A future deduplication or name-search-before-create UX is not part of this spec.
- Migrating `Product#apply_to` to use the new material slot pattern for `other_material_cost` — deferred per SPEC-018 out of scope.
- Server-side (AJAX) search for the material slot comboboxes — options are pre-loaded client-side from the rendered `<select>`. A server-search variant (for very large price books) is a future enhancement.
- Any changes to the price book index UI or the `estimate_materials` new/edit pages — those continue to use `material_combobox_controller.js` unchanged.
- Styling the Tom Select dropdown to match Tailwind design system — basic functional styling is acceptable; a polish pass is deferred.
- The `product_selector_controller.js` `fill` method — it is preserved exactly as-is. SPEC-019 does not touch its logic.

---

## Open Questions

All questions are resolved. No blocking questions remain.

1. **[CLOSED]** Should the product combobox use server-side search? No — the product list is already fully rendered in the `<select>` as `<optgroup>`s; Tom Select client-side search over the existing options is sufficient and avoids a new endpoint.

2. **[CLOSED]** Should the inline create form be a modal? No — it must appear inline within the Tom Select dropdown using DOM manipulation, as specified in the feature description. No modal library is introduced.

3. **[CLOSED]** What `category` should the inline-created `Material` default to? `"hardware"` — it satisfies the `inclusion` validation and is the less restrictive of the two valid values for a miscellaneous material the estimator is adding on the fly.

4. **[CLOSED]** Does Tom Select dispatch a native `change` event that `product-selector#fill` can hear? Yes — Tom Select dispatches a native `change` event on item add/remove when wrapping a `<select>` element, so the existing `data-action="change->product-selector#fill"` continues to work without modification.

---

## Dependencies

- **SPEC-018** — must be merged first. SPEC-019 converts the `other_material_id` slot added in SPEC-018 to a Tom Select combobox. SPEC-019 assumes the `other_material_id` column, the `other` slot row in the form, and the `material_slot_other` i18n key are all present.
- **SPEC-015** — done. Tom Select is vendored at `vendor/javascript/tom-select.esm.js` and pinned in `config/importmap.rb`. No further setup required.
- **SPEC-016** — done. The `formula-input` Stimulus controller is wired to qty fields; SPEC-019 does not touch qty fields and has no dependency on this beyond not regressing it.
