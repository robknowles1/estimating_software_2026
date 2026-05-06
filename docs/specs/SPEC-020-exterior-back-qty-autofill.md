# Spec: Exterior-to-Back Qty Autofill on Line Item Form

**ID:** SPEC-020
**Status:** done
**Priority:** low
**Created:** 2026-05-06
**Author:** pm-agent

---

## Summary

On the line item form, the `back_qty` field is almost always identical to `exterior_qty`. To save a step, when the user leaves the `exterior_qty` field for the first time, the value is copied into `back_qty` if and only if `back_qty` is currently empty. The copy is one-time and one-directional: after it fires, both fields are fully independent. Subsequent changes to `exterior_qty` never touch `back_qty`. This behaviour is implemented as a minimal Stimulus controller so it stays isolated from the existing `formula-input` controller wired to the same fields.

---

## User Stories

- As an estimator, I want `back_qty` to auto-populate from `exterior_qty` when I tab off the exterior field, so that I do not have to retype the same value in the common case where back and exterior quantities are equal.
- As an estimator, I want the auto-fill to leave `back_qty` alone if I have already typed a value there, so that my intentional entry is never silently overwritten.

---

## Acceptance Criteria

1. Given the line item new or edit form, when the page renders, then the `exterior_qty` text field has `data-controller="qty-mirror"` and `data-action="blur->qty-mirror#copyToBack"` wired to it, and the `back_qty` text field has `data-qty-mirror-target="back"` on it. The `formula-input` controller attributes on both fields are unchanged.

2. Given `back_qty` is empty and the user types a value into `exterior_qty` and then leaves the field (blur), then `back_qty` is immediately populated with the same value as `exterior_qty`.

3. Given `back_qty` already contains a value and the user types a different value into `exterior_qty` and then leaves the field (blur), then `back_qty` is not changed.

4. Given the autofill has already fired once (both fields now have the same value), when the user clears `exterior_qty` and types a new value then leaves the field, then `back_qty` is not updated (it retains the value it had before).

5. Given `exterior_qty` is empty and the user leaves the field (blur), then `back_qty` is not changed — an empty exterior value is not copied.

6. Given the `qty-mirror` Stimulus controller, when it is disconnected (e.g. Turbo navigates away), then it performs no cleanup work — there is no teardown required because the controller holds no external references or timers.

---

## Technical Scope

### Data / Models

No schema changes. No model changes.

### API / Logic

No new endpoints. No changes to existing controllers or business logic.

### UI / Frontend

**New Stimulus controller: `app/javascript/controllers/qty_mirror_controller.js`**

- `targets`: `["back"]` — identifies the `back_qty` field.
- `copyToBack()` action handler:
  - Reads the current value of the source element (the `exterior_qty` field, accessed via `this.element` since the action is on the field itself, or via `event.target`).
  - Reads the current value of `this.backTarget`.
  - If `this.backTarget.value` is non-empty (after trimming), returns immediately — never overwrite.
  - If the source value is empty (after trimming), returns immediately — do not copy a blank.
  - Otherwise, sets `this.backTarget.value` to the source value.
- No state property is needed. The "already touched" guard is the non-empty check on `back_qty` itself (AC#4 — once the first copy fires, `back_qty` is non-empty, so subsequent blurs on `exterior_qty` will be blocked by the non-empty guard).
- No `connect()` logic is needed.
- No `disconnect()` logic is needed.

**`app/views/line_items/_form.html.erb`**

The material slots are rendered by a single `each` loop over a slot array. The exterior and back rows are currently produced inside this shared loop, so they cannot independently receive different `data-` attributes without breaking the loop structure. The required change is to extract the `exterior` and `back` rows from the shared loop and render them explicitly with their additional attributes, leaving the remaining six slots (interior, interior2, drawers, pulls, hinges, slides) in the loop.

Specifically:
- Render the `exterior` row explicitly before the loop. Add `data: { controller: "qty-mirror formula-input", action: "blur->qty-mirror#copyToBack blur->formula-input#evaluate" }` to the `exterior_qty` text field. (Stimulus supports multiple controllers and actions in a single `data-controller` / `data-action` attribute.)
- Render the `back` row explicitly after the exterior row (but before the remaining loop rows). Add `data-qty-mirror-target="back"` to the `back_qty` text field, alongside the existing `formula-input` controller attributes.
- The shared loop then iterates over `[:interior, :interior2, :drawers, :pulls, :hinges, :slides]`.
- The material selector column of both explicit rows is identical to the loop-rendered version — no structural layout changes.

**`config/importmap.rb`**

No changes. Stimulus auto-discovers controllers from `app/javascript/controllers/` via the existing `pin_all_from` directive — no explicit pin is needed for the new controller file.

### Background Processing

None.

---

## Test Requirements

### Unit Tests

None — the controller has no model logic to test in isolation.

### Integration Tests

None — there is no server-side behaviour to cover.

### End-to-End Tests (System Specs)

**`spec/system/line_items_spec.rb`** — add the following scenarios:

**Scenario A — autofill fires when back_qty is empty:**
Given a line item new or edit form, when a user fills `exterior_qty` with "4" and then moves focus away from the field, then `back_qty` displays "4".

**Scenario B — autofill does not overwrite an existing back_qty value:**
Given a line item form where `back_qty` has already been set to "2", when the user changes `exterior_qty` to "6" and moves focus away, then `back_qty` still displays "2".

**Scenario C — autofill does not fire when exterior_qty is empty:**
Given a line item form where both qty fields are empty, when the user focuses and immediately blurs `exterior_qty` without typing, then `back_qty` remains empty.

**Scenario D — autofill fires at most once per form load:**
Given a line item form where both qty fields are empty, when the user types "3" into `exterior_qty` and blurs (back_qty becomes "3"), then the user clears `exterior_qty`, types "5", and blurs again, then `back_qty` still displays "3" (the second blur does not overwrite because back_qty is now non-empty).

---

## Out of Scope

- Autofill in the reverse direction (back-to-exterior): not requested.
- Syncing any other qty field pairs (e.g. interior to interior2): not requested.
- A "link/unlink" toggle that makes the fields stay in sync continuously: the agreed behaviour is a one-time copy on first entry only.
- Persisting or tracking whether the user manually changed `back_qty` after the copy: the non-empty guard is sufficient.
- Any changes to the `formula-input` controller or its behaviour on either field.
- Any changes to the material selector dropdowns in the exterior or back rows.

---

## Open Questions

None. All behaviour has been confirmed with the user prior to writing this spec.

---

## Dependencies

- **SPEC-019** — the line item form must be in its post-SPEC-019 state (Tom Select wired to material selectors, `formula-input` on qty fields). SPEC-020 adds a second controller to the `exterior_qty` field alongside `formula-input`; this is safe because Stimulus supports multiple controllers per element. No code from SPEC-019 needs to change.
