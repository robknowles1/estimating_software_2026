# ADR-014: SPEC-019 Inline Material Create — Endpoint Design and Stimulus Pattern

**Status:** accepted
**Date:** 2026-04-27
**Deciders:** architect-agent


## Context

SPEC-019 adds Tom Select comboboxes to the line item form for both the product selector and all material slot selectors. The material slot comboboxes include an inline find-or-create flow: when a user types a name that is not in the price book, they can create the `Material` and `EstimateMaterial` records without leaving the form. This requires a new JSON endpoint and a new Stimulus controller that calls it.

Six architectural questions need decisions before development starts.


## Decisions

### 1. JSON Endpoint Placement

**Decision:** Add `inline_create` as a collection action on the existing `EstimateMaterialsController`. Do not create a separate controller.

**Route:**
```ruby
resources :estimate_materials, only: [:index, :new, :create, :edit, :update, :destroy] do
  post :inline_create, on: :collection
end
```

This produces `POST /estimates/:estimate_id/estimate_materials/inline_create` with the named helper `inline_create_estimate_estimate_materials_path`.

**Rationale:** The action creates an `EstimateMaterial` (and incidentally a `Material`). `EstimateMaterialsController` already owns the `set_estimate` before-action that scopes the record correctly. A separate controller would duplicate that scoping and the authentication concern for no benefit. The existing `create` action already handles the same dual-save pattern (Material + EstimateMaterial in a transaction), so the new action lives naturally alongside it.

**CSRF handling:** The fetch request must include the CSRF token as an `X-CSRF-Token` request header. Tom Select's inline create panel is rendered via DOM manipulation in the Stimulus controller — there is no form element to carry a hidden CSRF field automatically. Read the token from `document.querySelector('meta[name="csrf-token"]').content` and include it as a header. Rails `protect_from_forgery with: :exception` validates `X-CSRF-Token` headers for non-GET requests from the same origin. This is the standard Rails pattern for fetch-based JSON submissions from Stimulus controllers (see `material_combobox_controller.js` would use the same approach).

**Auth on unauthenticated requests:** `require_login` in `ApplicationController` currently redirects to the login page (HTTP 302, HTML). For this JSON endpoint the redirect will be followed by `fetch` and the response will be HTML, which the controller will misparse as JSON. The spec acknowledges this by calling the 302 behaviour "existing behaviour." For MVP this is acceptable — an unauthenticated fetch will get a confusing error rather than data exposure. A future hardening step is to detect `request.format.json?` in `require_login` and return 401 JSON instead of redirecting. This is noted as pre-production debt but not blocking.

---

### 2. JSON Response Contract

**Success (HTTP 201):**
```json
{ "id": 42, "name": "Acrylic Panel", "display": "Acrylic Panel ($28.00)" }
```

- `id` is `estimate_material.id` (not `material.id`). The line item form submits `<slot>_material_id` which maps to `estimate_material.id`. Using `material.id` here would be a silent bug.
- `display` is formatted with two decimal places using `sprintf('%.2f', em.quote_price)` — not `number_with_precision` which requires ActionView helpers.
- `name` is included so the Stimulus controller can use it independently if needed (e.g. for accessibility labels) without parsing the `display` string.

**Failure (HTTP 422):**
```json
{ "errors": ["Name can't be blank", "Cost must be greater than or equal to 0"] }
```

- A flat array of strings (full messages). The Stimulus controller renders them as a list; no structure is needed client-side.
- Include errors from both the `Material` record and the `EstimateMaterial` record. The `EstimateMaterial` validation (`quote_price >= 0`, `material_id uniqueness`) should be checked even if `Material` passes.
- If the transaction rolls back due to `EstimateMaterial` failure, collect `em.errors.full_messages` before the rollback and merge them with `material.errors.full_messages`.

**The spec's error collection pattern needs a correction.** The spec says to collect `em_errors` after the transaction block. Within a `raise ActiveRecord::Rollback` path the `em` variable may be nil (if `Material` save failed and `em` was never built), or `em` may exist but have been rolled back to a transient state. The developer must collect `em.errors.full_messages` inside the transaction block, before raising `ActiveRecord::Rollback`, into a local variable that survives the rollback. See Implementation Notes below.

---

### 3. `cost_with_tax` Calculation

**Decision:** No change to the model or the endpoint needed. `cost_with_tax` is computed automatically by the `before_save :compute_cost_with_tax` callback on `EstimateMaterial`. The callback reads `estimate.tax_rate` and `estimate.tax_exempt?` via the already-loaded `estimate` association. Because the `inline_create` action sets `em = @estimate.estimate_materials.build(...)`, the association is in memory and no additional query is needed.

**Confirmation:** The spec's claim that "cost_with_tax is computed by the existing before_save callback" is correct. The endpoint does not need to calculate tax explicitly.

**One edge case to verify:** `compute_cost_with_tax` calls `estimate.tax_rate.to_d`. If `tax_rate` is nil (e.g. on a legacy or malformed estimate), `nil.to_d` returns `0.0` in Ruby, so the callback degrades gracefully to treating the estimate as zero-taxed. This is already the existing behaviour on all other `EstimateMaterial` saves and is not a new risk for this endpoint.

---

### 4. Tom Select `create` Option Pattern

**Decision:** Do not use Tom Select's built-in `create` callback for the inline create flow. Use a custom `no_results` render with an "Add" option item instead.

**Rationale:** Tom Select's `create` callback (the `create: true / create: function(input, callback)` option) is designed for a different UX: the user presses Enter or clicks "Add item" and the item is immediately added to the select without a secondary confirmation step. For this spec the secondary cost input is required before the material can be created, so a `create` callback that synchronously or asynchronously adds the option is the wrong shape.

The correct pattern is:

1. Configure Tom Select with `create: false`.
2. Use the `render.no_results` hook (already used in `material_combobox_controller.js`) to return a custom DOM element containing an "Add 'X'" clickable row.
3. When that row is clicked, inject an inline panel into the Tom Select dropdown DOM (`this.tomSelect.dropdown_content` or the dropdown container element) containing the name field (pre-filled), cost field, confirm button, and cancel button.
4. Prevent Tom Select from closing the dropdown while the panel is visible by calling `this.tomSelect.open()` inside the click handler and preventing blur events from propagating if needed.

**Keeping the dropdown open is the most fragile part of this implementation.** Tom Select closes its dropdown on blur and on certain keyboard events. The developer will need to call `event.preventDefault()` on blur events that originate from inside the inline panel, or use `tomSelect.settings.shouldLoad` / event interception to keep it open. Testing with keyboard navigation is important. System spec Scenario D (error case without closing) will catch regressions here.

**Alternative considered and rejected:** Rendering the inline panel outside the Tom Select dropdown (e.g. below the select element as a standard Rails partial) would be simpler to keep open but does not meet the spec's requirement that it appear "within the Tom Select dropdown."

---

### 5. Material `category` Column

**Decision:** Default `"hardware"` silently. Do not expose a category picker in the inline create form.

**Rationale:** The `Material` model validates `category` with an `inclusion` check — it must be `"sheet_good"` or `"hardware"`. Adding a category picker to the inline form increases friction for a workflow that is already secondary (the user is in the middle of filling a line item). The spec's closed question #3 confirms `"hardware"` as the correct default: sheet goods are sized panels with dimensions, while hardware covers screws, hinges, pulls, and general miscellaneous materials — exactly what an estimator would add on the fly without having pre-catalogued it. The `unit` field defaults to `"EA"` for the same reason.

**Consequence:** An estimator who creates a new sheet good material via inline create will get `category: "hardware"` and will need to edit the material in the price book later to correct it. This is a known and accepted tradeoff for MVP. A future improvement could auto-detect category from the slot context (e.g. exterior/interior slots default to `sheet_good`; pulls/hinges/slides default to `hardware`).

---

### 6. Security: Estimate Ownership Scoping

**Decision:** Scope all reads and writes in `inline_create` through `@estimate`, which is set by the `set_estimate` before-action using `Estimate.find(params[:estimate_id])`. Do not add any additional scoping for MVP.

**Gap acknowledged (pre-existing):** `set_estimate` uses `Estimate.find(params[:estimate_id])` — not `current_user.estimates.find(...)`. This means any authenticated user can call `inline_create` on any estimate ID and create a `Material` and `EstimateMaterial` on it. This is the same ownership gap documented in the project memory under "Deferred: Estimate Ownership Auth Gap." It is pre-existing across all estimate and estimate_material actions, and its resolution is deferred to a separate security pass before multi-user production deploy. SPEC-019 does not introduce a new gap; it inherits the existing one.

**What the spec's AC-17 says:** "scoped to the estimate via `Estimate.find(params[:estimate_id])`" — this is accurate and matches the existing controller pattern. The developer should implement exactly this and no more for SPEC-019.


## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Separate `InlineMaterialCreatesController` | Single responsibility; clean | Duplicates `set_estimate`, auth concern; another file to maintain | Adds complexity for no benefit over adding one action to existing controller |
| Use Tom Select `create: function(input, callback)` | Built-in UX for "add new" | Fires immediately; no room for secondary cost input; callback pattern fights the async fetch requirement | Wrong shape for the required two-step UX (name + cost) |
| Expose `category` picker in inline form | More accurate data | Increases friction; users adding hardware on the fly don't know or care about category | MVP tradeoff; category can be corrected in price book later |
| Return `material.id` instead of `estimate_material.id` in JSON | Simpler to explain | Line item form submits `<slot>_material_id` which is `estimate_material.id`; would silently fail to save | Functionally incorrect |
| Return 401 JSON for unauthenticated requests | Cleaner error handling in Stimulus | Requires changing `require_login` to be format-aware | Pre-production debt; not blocking for MVP |


## Consequences

### Positive
- No new controller, no new route namespace — minimal surface area.
- `cost_with_tax` is computed correctly for free via the existing callback.
- `id` field in the JSON response correctly identifies the `estimate_material`, preventing a silent mis-save.
- Inline panel approach (no `create` callback) gives full control over the two-step UX.

### Negative
- Keeping the Tom Select dropdown open during the inline create panel interaction requires careful event handling and will be the most brittle part of the implementation.
- Unauthenticated fetch requests receive an HTML redirect body, not a JSON 401 — logged as pre-production debt.
- Inline-created materials always get `category: "hardware"` regardless of slot context.

### Risks
- **Dropdown focus management:** Tom Select may close its dropdown when focus moves to the inline cost input. Mitigation: use `event.stopPropagation()` / `event.preventDefault()` on blur events within the panel, and call `tomSelect.open()` if needed after panel interactions. System spec Scenario D must exercise this path.
- **Transaction error collection:** If `em.errors` are collected after `raise ActiveRecord::Rollback`, `em` may be nil or its error state may be unreliable. Mitigation: see Implementation Notes.
- **Race condition on duplicate material:** Two users simultaneously adding the same material name will produce two `Material` records. This is explicitly accepted by the spec (AC-16). The `EstimateMaterial` uniqueness constraint (`material_id + estimate_id`) still applies — if two users add the same material to the same estimate concurrently, the second will get a 422.


## Implementation Notes

### Error collection inside the transaction

```ruby
def inline_create
  material = Material.new(name: inline_create_params[:name],
                          default_price: inline_create_params[:cost],
                          category: "hardware",
                          unit: "EA")
  em = nil
  em_errors = []
  saved = false

  ActiveRecord::Base.transaction do
    if material.save
      em = @estimate.estimate_materials.build(material: material,
                                              quote_price: inline_create_params[:cost])
      if em.save
        saved = true
      else
        em_errors = em.errors.full_messages
        raise ActiveRecord::Rollback
      end
    end
  end

  if saved
    render json: {
      id: em.id,
      name: material.name,
      display: "#{material.name} ($#{sprintf('%.2f', em.quote_price)})"
    }, status: :created
  else
    all_errors = material.errors.full_messages + em_errors
    render json: { errors: all_errors }, status: :unprocessable_entity
  end
end

private

def inline_create_params
  params.require(:material).permit(:name, :cost)
end
```

`em_errors` must be a local variable defined outside the transaction block and populated inside it before `raise ActiveRecord::Rollback`. This survives the rollback.

### Route addition

```ruby
resources :estimate_materials, only: [:index, :new, :create, :edit, :update, :destroy] do
  collection do
    post :inline_create
  end
end
```

### Stimulus: keeping the dropdown open

After injecting the inline panel into the dropdown, intercept `mousedown` events on the panel to prevent Tom Select from interpreting clicks as "clicked outside":

```javascript
panel.addEventListener("mousedown", (e) => e.stopPropagation())
```

Tom Select closes its dropdown on `mousedown` outside the control/dropdown. Stopping propagation on the panel's container prevents that. Test with both mouse and keyboard navigation.

### Named route in view

The view passes the inline create URL to the Stimulus controller via a data value:

```erb
data-material-slot-inline-create-url-value="<%= inline_create_estimate_estimate_materials_path(estimate) %>"
```

`inline_create_estimate_estimate_materials_path` is the Rails-generated helper name from the collection route. Verify this with `bin/rails routes | grep inline`.

### SPEC-018 dependency

The form currently lists 8 standard material slots (exterior through slides), banding, and locks. SPEC-018 adds the `other` slot (`other_material_id`). SPEC-019 must be merged after SPEC-018. The developer must add the `other` slot to the material slots loop and verify it is included in the Tom Select enhancement.
