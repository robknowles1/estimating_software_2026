# ADR-011: EstimateMaterialsController#create Transaction Design and apply_to_estimate Routing

**Status:** accepted
**Date:** 2026-04-13
**Deciders:** architect-agent

Supplements: ADR-010 (accepted 2026-04-13) — this ADR addresses two implementation-level design points left open by ADR-010 and SPEC-014 that are consequential enough to warrant explicit decisions before the developer builds them.

---

## Context

SPEC-014 introduces two controller actions with non-trivial design surface:

1. **`EstimateMaterialsController#create` — dual-path create.** The spec describes two paths through a single controller action: (a) select an existing library material by `material_id` and create an `estimate_materials` row, and (b) submit new-material params that create a `Material` library record AND an `EstimateMaterial` row in one step. Path (b) is a multi-model write. The spec is silent on transaction boundary, error handling when one write succeeds and the other fails, and whether this logic belongs in the controller or a service object.

2. **`MaterialSetsController#apply_to_estimate` — routing and partial-failure semantics.** The spec places this as a member route on `material_sets` with `post :apply_to_estimate`. This route spans two resources (a material set and an estimate). Questions arise about whether POST is the right verb for an idempotent-by-design operation, where the route should live (set-centric vs. estimate-centric), and how to handle the case where some materials from the set already exist on the estimate.

---

## Decision 1: EstimateMaterialsController#create — use an inline transaction with a thin service method, not a standalone service object

**The dual-path create action** handles two fundamentally different inputs. Rather than a standalone `EstimateMaterialCreator` service class, use a private method on the controller that wraps the two-model write in `ActiveRecord::Base.transaction`. The controller remains the orchestrator; the transaction boundary is explicit and co-located with the action that needs it.

**Transaction scope for path (b) — new-material + new-estimate-material:**

```
ActiveRecord::Base.transaction do
  material = Material.new(material_params)
  material.save!               # raises on validation failure
  em = estimate.estimate_materials.build(
    material: material,
    quote_price: material.default_price
  )
  em.save!                     # raises on validation failure
end
```

If `material.save!` fails, no `estimate_materials` row is written. If `em.save!` fails (e.g., the unique index fires because a concurrent request already added this material to the estimate), the `Material` record is rolled back as well. Both writes succeed together or neither does. No orphaned library records.

**Error handling:** rescue `ActiveRecord::RecordInvalid` outside the transaction block. On failure, re-render the `new` template with the `material` and `em` objects populated so the user sees inline validation errors. Do not rescue `ActiveRecord::RecordNotUnique` separately — the uniqueness validation on `EstimateMaterial` (validates `:material_id, uniqueness: { scope: :estimate_id }`) will fire before the DB constraint in normal flow; catch the validation error path, not the exception path.

**Path (a) — existing material_id:** this path is a single-model write (create or find `EstimateMaterial`). No explicit transaction wrapper is needed beyond the implicit transaction Rails wraps around every `save`. Use `find_or_initialize_by(estimate: estimate, material: material)` and check `new_record?` before saving; if it already exists, redirect with an informational notice rather than re-rendering.

---

## Decision 2: apply_to_estimate — keep as a member route on material_sets, use POST, treat partial application as success

### Route placement

The `apply_to_estimate` action is set-initiated: the user picks a set and applies it to an estimate. Placing it on `material_sets` as a member route (`POST /material_sets/:id/apply_to_estimate`) is the right call. The alternative — nesting it under estimates as `POST /estimates/:id/apply_material_set` — reads as estimate-centric, but the initiating object is the set (the user browses sets, then applies one to an estimate). Keeping it on the set controller is semantically cleaner and avoids requiring the developer to add `material_set_id` logic to `EstimatesController`.

The spec's proposed route is correct:

```ruby
resources :material_sets do
  member do
    post :apply_to_estimate
  end
end
```

### HTTP verb

POST is correct. Despite the apply operation being naturally idempotent (applying the same set twice has no additional effect due to the "skip if already exists" logic), the operation creates server-side resources (`estimate_materials` rows) and is not safe to repeat without consequence from the user's perspective (the first application creates rows; a second may be a mistake). POST is the right verb for "perform this action." A PUT/PATCH would imply replacing the target's state, which is not what happens here. Do not use GET (it creates records).

### Partial-failure semantics

"Partial application" here means some materials from the set already exist on the estimate. This is not a failure — it is the designed behaviour. The spec is correct: skip existing rows silently, create the rest, redirect with a summary notice ("X materials added, Y already present — skipped.").

No transaction wrapper is needed across the full loop. Each `estimate_materials` row is an independent write. If one row fails due to a validation error other than uniqueness (which should not happen in normal operation since materials from a set are all valid library entries), allow that row to fail silently and include it in a "skipped" count. A full rollback of a partial application is not warranted — the user can inspect the result in the materials tab and correct any anomalies. If any unexpected `ActiveRecord::RecordInvalid` is raised, rescue it, log it, and continue the loop.

The implementation pattern:

```ruby
added = 0
skipped = 0

@material_set.material_set_items.includes(:material).each do |item|
  em = @estimate.estimate_materials.find_or_initialize_by(material: item.material)
  if em.new_record?
    em.quote_price = item.material.default_price
    em.save ? added += 1 : skipped += 1
  else
    skipped += 1
  end
end

redirect_to estimate_estimate_materials_path(@estimate),
            notice: t(".applied", added: added, skipped: skipped)
```

### Estimate lookup and authorization

The `estimate_id` is passed as a param. Load it through `Estimate.find(params[:estimate_id])`. If the estimate does not exist, `find` raises `ActiveRecord::RecordNotFound` which Rails will render as a 404. No explicit authorization beyond the `require_login` filter inherited from `ApplicationController` is required for this phase — any authenticated user can apply a set to any estimate (RBAC is out of scope per ADR-010).

---

## Rationale

### Why not a service object for the dual-path create?

A service object (e.g., `EstimateMaterialCreator.call(estimate:, params:)`) adds a file, a call convention, and an indirection layer for two model saves. The rule from this project's architecture principles is: prefer boring, proven solutions. A controller private method with an explicit `transaction` block is readable, testable via request specs, and contains all the logic in the place where a developer will look for it. The complexity threshold for extracting a service object has not been crossed — there is no fan-out (no emails, no background jobs, no third-party calls), no reuse across controllers, and no complex branching beyond the two paths already expressed by the controller action.

If a future spec adds a background job triggered on material creation, or a webhook, extract to a service at that point. Not now.

### Why keep the transaction scope narrow (only path (b))?

Path (a) (existing `material_id`) is a single-model write. Wrapping it in a transaction it does not need adds noise without adding safety. The two paths have different risk profiles; they should have different implementations.

### Why POST and not PATCH for apply_to_estimate?

PATCH implies partial update of an existing resource's state. The estimate's materials collection is not a resource being partially replaced — new rows are being created. POST on a member action ("apply this set") maps to the actual semantics: a command that triggers resource creation. This aligns with how Rails member actions are conventionally used for non-CRUD commands.

### Why no full rollback on partial apply?

A transactional all-or-nothing apply would require wrapping the entire loop, and if it failed, the user would see no materials added at all and an opaque error. The "skip existing" design makes each item write independent by intent. Treating each write independently and reporting a summary is more honest and more useful to the estimator than a binary pass/fail.

---

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Service object for dual-path create | Testable in isolation; reusable | Adds indirection for two model saves; not called from anywhere else | Complexity threshold not reached; controller private method + transaction is sufficient |
| Rescue `ActiveRecord::RecordNotUnique` instead of model validation | Handles concurrent duplicate inserts at the DB level | Two rescue paths; most duplication arrives through UX not concurrency; validation fires first in normal flow | Not the primary failure mode; adds exception-path complexity without benefit |
| Place `apply_to_estimate` on `EstimatesController` | Estimate-centric routing | Initiating object is the set, not the estimate; would require adding set logic to an already-in-scope controller | Semantically wrong initiator; set-centric routing is cleaner |
| Use PATCH for `apply_to_estimate` | Reflects idempotent intent | PATCH implies updating an existing resource, not creating new ones | Creates `estimate_materials` rows; POST is correct |
| Wrap `apply_to_estimate` loop in a single transaction | All-or-nothing safety | Binary failure on any single row error; skipped rows are not errors; user loses all progress on failure | Each row write is independent by design; partial application is valid and expected |

---

## Consequences

### Positive

- The dual-path create is predictable: either both writes succeed or neither does. No orphaned `Material` library records.
- `apply_to_estimate` always leaves the estimate in a valid state — each item either gets added or is skipped, never leaves a partial row.
- The routing is consistent with how the user initiates the action (from the set, not from the estimate) and follows standard Rails member action conventions.
- Error handling paths are simple enough that they do not require dedicated test fixtures beyond what the integration spec already exercises.

### Negative

- Concurrent duplicate requests on path (a) (two users simultaneously adding the same material to the same estimate) could race past the `new_record?` check and hit the DB unique constraint. This is a `RecordNotUnique` exception rather than a validation error. The mitigation is to add a rescue for `ActiveRecord::RecordNotUnique` on path (a) specifically and treat it as the "already exists" redirect path. This is a minor addition to the controller but must not be omitted.
- The `apply_to_estimate` summary notice requires two i18n keys (`added` and `skipped` interpolation) — a small but required addition to `config/locales/en.yml`.

### Risks

| Risk | Mitigation |
|------|-----------|
| `Material.save!` succeeds but `em.save!` fails on path (b); `Material` is left in library | Transaction wraps both writes; rollback removes the `Material` row |
| Concurrent duplicate add on path (a) hits DB unique constraint before validation fires | Rescue `ActiveRecord::RecordNotUnique` on path (a) and redirect with the "already present" notice |
| `apply_to_estimate` with a large set takes too long in one request | At this data volume (dozens of materials per set, not thousands), synchronous is appropriate; no background job needed |
| `estimate_id` param on `apply_to_estimate` refers to a non-existent estimate | `Estimate.find` raises `RecordNotFound`; Rails renders 404; no additional guard needed |

---

## Implementation Notes

### Controller action structure for EstimateMaterialsController#create

```ruby
def create
  if params[:material_id].present?
    create_from_existing_material
  else
    create_with_new_material
  end
end

private

def create_from_existing_material
  material = Material.active.find(params[:material_id])
  em = @estimate.estimate_materials.find_or_initialize_by(material: material)
  if em.new_record?
    em.quote_price = material.default_price
    em.save!
    redirect_to estimate_estimate_materials_path(@estimate), notice: t(".created")
  else
    redirect_to estimate_estimate_materials_path(@estimate), notice: t(".already_present")
  end
rescue ActiveRecord::RecordNotUnique
  # concurrent duplicate insert; treat as already-present
  redirect_to estimate_estimate_materials_path(@estimate), notice: t(".already_present")
end

def create_with_new_material
  @material = Material.new(new_material_params)
  @em = @estimate.estimate_materials.build

  ActiveRecord::Base.transaction do
    @material.save!
    @em.material = @material
    @em.quote_price = @material.default_price
    @em.save!
  end

  redirect_to estimate_estimate_materials_path(@estimate), notice: t(".created")
rescue ActiveRecord::RecordInvalid
  render :new, status: :unprocessable_entity
end
```

The `@estimate` is loaded in a `before_action :set_estimate`. The `new` template must handle both `@material` and `@em` being nil (for the initial render) or populated with errors (for the re-render after failure on path (b)). Use a `params[:mode]` or tab parameter to distinguish the two sub-views within the `new` template.

### Routes to add to config/routes.rb

```ruby
resources :materials

resources :material_sets do
  resources :material_set_items, only: [:create, :destroy]
  member do
    post :apply_to_estimate
  end
end

# Inside the existing resources :estimates block:
resources :estimate_materials, only: [:index, :new, :create, :edit, :update, :destroy]
```

### i18n keys required

```yaml
# config/locales/en.yml additions

materials:
  create:
    notice: "Material added to library."
  destroy:
    notice: "Material archived."
    alert: "This material is in use on one or more estimates and cannot be archived."

estimate_materials:
  create:
    created: "Material added to estimate."
    already_present: "That material is already in this estimate's price book."

material_sets:
  apply_to_estimate:
    applied: "%{added} material(s) added; %{skipped} already present and skipped."
    estimate_not_found: "Estimate not found."
```

### Strong params reminder

`EstimateMaterialsController` must permit `quote_price` and `role` (for edit/update). It must NOT permit any `_unit_price` or `_description` params — those columns no longer exist and should not appear in permitted params. Include a comment in the strong params method to make this explicit, since prior controllers permitted those params.

### Test coverage checklist for the developer

Request specs must cover:

- Path (a): `material_id` present → creates row, redirects
- Path (a): `material_id` already on estimate → no duplicate, informational redirect
- Path (b): both writes succeed → `Material` and `EstimateMaterial` created, redirect
- Path (b): `Material` invalid → neither record created, re-renders new with errors
- Path (b): `EstimateMaterial` invalid (e.g., uniqueness — another request beat this one) → `Material` rolled back, re-renders new
- `apply_to_estimate`: all new → all added, correct count in notice
- `apply_to_estimate`: some existing → existing skipped, correct counts in notice
- `apply_to_estimate`: invalid `estimate_id` → 404
