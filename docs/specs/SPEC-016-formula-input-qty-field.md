# Spec: Excel-Style Formula Evaluation on Line Item Qty Fields

**ID:** SPEC-016
**Status:** done
**Priority:** medium
**Created:** 2026-04-23
**Author:** pm-agent

---

## Summary

Estimators at this millwork shop are accustomed to entering formulas directly into cells in Excel — typing `+6/28` to express "6 pieces over a 28-inch run" rather than pre-calculating the result. The Edit Line Item form's top-level Qty field and each material slot qty field (exterior, interior, interior2, back, drawers, pulls, hinges, slides, locks) are currently plain `type="number"` inputs that reject formula characters. This spec adds a `formula-input` Stimulus controller that evaluates simple arithmetic expressions client-side on blur, replacing the raw formula with its computed decimal result. No server changes are required: the underlying columns already store decimals and the submitted values are always plain decimals after client-side evaluation.

---

## User Stories

- As an estimator, I want to type a formula like `+6/28` or `(12+4)/8` into the Qty field, so that I can express quantities the same way I do in Excel without stopping to calculate them on a separate tool.
- As an estimator, I want the Qty field to silently ignore characters outside arithmetic operators, so that accidental keystrokes do not corrupt the field value.
- As an estimator, I want a plain decimal I type (e.g. `1.5`) to pass through unchanged, so that normal data entry is unaffected.

---

## Acceptance Criteria

1. Given the Edit Line Item form, when the page loads, then the Qty field AND each material slot qty field (exterior, interior, interior2, back, drawers, pulls, hinges, slides, locks) are rendered as `type="text"` with `inputmode="decimal"` and have the formula-input controller wired.

2. Given the Qty field contains a valid arithmetic expression (digits, `+`, `-`, `*`, `/`, `.`, `(`, `)`, and spaces only), when the user leaves the field (blur), then the field value is replaced with the evaluated result rounded to 4 decimal places (e.g. `6/28` becomes `0.2143`).

3. Given the Qty field contains a plain positive decimal (e.g. `1.5`), when the user leaves the field, then the field value is unchanged (it passes through the evaluator and remains `1.5`).

4. Given the Qty field contains a character outside the allowed whitelist (letters, `%`, `=`, `$`, etc.), when the user leaves the field, then the field value is left unchanged and no error is displayed.

5. Given an expression that would produce a result of zero or less (e.g. `-2`, `0`, `5-5`), when the user leaves the field, then the field value is left unchanged (the evaluator rejects non-positive results).

6. Given an expression that causes a JavaScript evaluation error (e.g. `(3+`, `//`), when the user leaves the field, then the field value is left unchanged (the evaluator fails gracefully with no console error reaching the user).

7. Given the Qty field has been evaluated and the form is submitted, then the submitted `line_item[quantity]` parameter is a valid positive decimal accepted by the server's `DECIMAL(10, 4)` column with no validation errors.

8. Given the formula-input controller evaluates the Qty field on blur and writes a resolved decimal back into the field, then it dispatches a native `input` event afterward so any current or future `data-action="input->..."` listeners can respond to the updated value. (`line_item_calculator_controller` exists in the codebase but is not currently wired to the line item form; this AC keeps the integration point ready without requiring it.)

---

## Technical Scope

### Data / Models

No schema changes. The `quantity` column is `DECIMAL(10, 4)` and already accepts any positive decimal up to 4 decimal places. No migration is needed.

### API / Logic

No server-side changes. Formula evaluation is entirely client-side. The submitted form value is always a plain decimal string by the time the browser sends the request.

### UI / Frontend

#### Stimulus controller: `app/javascript/controllers/formula_input_controller.js`

This is a new, single-purpose controller. It has no targets and no values — the element it connects to is the input itself.

Responsibilities:
- Connect to the `<input>` element directly (controller mounted on the input, not on an ancestor).
- On `blur` (via `data-action="blur->formula-input#evaluate"`): read `this.element.value`, run the safety check and evaluation pipeline described below, write the result back if valid, and dispatch a native `input` event so dependent controllers (e.g. `line_item_calculator_controller`) observe the change.

Evaluation pipeline on blur:

1. Trim leading/trailing whitespace from the raw value.
2. If the trimmed value is empty, return without change.
3. Run a whitelist regex: `/^[\d\s\+\-\*\/\.\(\)]+$/`. If the value does not match, return without change.
4. Evaluate using `Function("return " + trimmedValue)()` inside a `try/catch`. If an exception is thrown, return without change.
5. Convert the result to a number with `Number(result)`. If the result is `NaN`, not finite, or `<= 0`, return without change.
6. Round to 4 decimal places: `Math.round(result * 10000) / 10000`. Format as a plain decimal string (avoid scientific notation for very small values — use `toFixed(4)` then strip trailing zeros with a regex or accept 4 decimal places as-is per the column definition).
7. Set `this.element.value` to the formatted result.
8. Dispatch `this.element.dispatchEvent(new Event("input", { bubbles: true }))` so that Stimulus `data-action="input->..."` listeners on ancestor elements receive the updated value.

No new npm or CDN dependencies are introduced. `Function(...)` is the standard JavaScript approach for safe arithmetic-only expression evaluation when the input is whitelist-validated.

#### View change: `app/views/line_items/_form.html.erb`

The top-level Qty field plus each material slot qty field rendered by the slot loop (line 98) and the `locks_qty` field (line 124) are converted from `f.number_field` (currently `step: "0.0001", min: 0`) to `f.text_field` with the same formula-input wiring. For example, each `f.number_field :"#{slot}_qty"` and `f.number_field :locks_qty` is replaced with the equivalent `f.text_field` form:

```erb
<%= f.text_field :quantity,
    class: input_cls,
    inputmode: "decimal",
    autocomplete: "off",
    data: { controller: "formula-input", action: "blur->formula-input#evaluate" } %>
```

```erb
<%= f.text_field :"#{slot}_qty",
    class: input_cls,
    inputmode: "decimal",
    autocomplete: "off",
    data: { controller: "formula-input", action: "blur->formula-input#evaluate" } %>
```

```erb
<%= f.text_field :locks_qty,
    class: input_cls,
    inputmode: "decimal",
    autocomplete: "off",
    data: { controller: "formula-input", action: "blur->formula-input#evaluate" } %>
```

The wiring is identical per field. The `step` and `min` attributes are removed from the rendered HTML because `type="text"` does not respect them and they would generate browser warnings. Server-side validation on each qty column (must be >= 0; `quantity` must be > 0) is unchanged and continues to enforce the minimum.

No other fields in the form are changed by this spec.

#### i18n

No new i18n keys are required. The formula-input controller produces no user-visible strings — it either silently evaluates or silently leaves the field unchanged.

### Background Processing

None.

---

## Test Requirements

### Unit Tests

No Ruby unit tests required — no model or service logic changes.

### Integration Tests

No new request specs required. The existing `POST /estimates/:id/line_items` request spec with a valid `quantity` decimal continues to cover the server-side path. No new server behavior is introduced.

### End-to-End Tests

**`spec/system/line_items_spec.rb` — new examples under a `"formula input on Qty fields"` describe block:**

- Given a line item edit form, when the user fills the Qty field with `6/28` and tabs away, then the field value becomes `0.2143`.
- Given a line item edit form, when the user fills the Qty field with `(12+4)/8` and tabs away, then the field value becomes `2`.
- Given a line item edit form, when the user fills the Qty field with `2` (plain integer) and tabs away, then the field value remains `2` (or `2.0` — either is acceptable).
- Given a line item edit form, when the user fills the Qty field with `abc` and tabs away, then the field value remains `abc` (whitelist rejection — field unchanged).
- Given a line item edit form, when the user fills the Qty field with a valid formula and submits the form, then the line item is saved with the evaluated decimal and no validation error is shown.
- Given a line item edit form, when the user fills the Exterior slot qty field (`exterior_qty`) with `6/28` and tabs away, then the field value becomes `0.2143` (proves slot wiring).
- Given a line item edit form, when the user fills the Locks qty field (`locks_qty`) with `(12+4)/8` and tabs away, then the field value becomes `2` (proves locks wiring).

The controller logic is identical across fields, so coverage of one slot (`exterior_qty`) plus `locks_qty` is sufficient to prove all slot wiring without duplicating nine specs. System specs use Selenium with headless Chrome as per project conventions. Use `find_field` and `send_keys :tab` (or `blur` via JS execution) to trigger the blur event.

---

## Out of Scope

- Formula evaluation on labor hour fields, equipment fields, or `other_material_cost` — only positive-quantity inputs in the materials section are in scope.
- Formula evaluation on any other form in the application (estimate job-cost fields, material pricing, etc.).
- Displaying the original formula after evaluation (e.g. showing `6/28` as a tooltip). The field always shows the resolved decimal after blur.
- Server-side formula parsing or storage of the raw formula expression.
- Unit tests for the JavaScript controller — the project does not run a JS test suite; coverage is via system specs.
- Error messaging or visual feedback when a formula is invalid — silent no-op is the agreed behaviour.
- Support for mathematical functions beyond the four arithmetic operators (`+`, `-`, `*`, `/`) and parentheses (e.g. no `sqrt`, `PI`, `^` exponentiation).

---

## Open Questions

| OQ | Question | Blocks progress? |
|----|---------|-----------------|
| OQ-A | The `line_item_calculator_controller` reads the Qty field to produce a live price preview. The spec assumes dispatching a native `input` event after evaluation is sufficient to trigger recalculation. The developer should verify that `line_item_calculator_controller` wires its recalculation via `data-action="input->..."` on the Qty field (or an ancestor), or adjust accordingly. | No — developer resolves at implementation time |
| OQ-B | `toFixed(4)` always emits four decimal places (e.g. `2.0000`). Stripping trailing zeros (giving `2`) is cosmetically nicer but requires a regex step. Developer decides which format to use; both are valid for the `DECIMAL(10,4)` column. | No — **Resolved**: trailing zeros are stripped via `parseFloat(rounded.toFixed(4)).toString()`, so `(12+4)/8` produces `"2"` not `"2.0000"`. |

---

## Dependencies

- SPEC-010 (Estimating Foundation) and SPEC-011 (Line Item Grid) — done; the `line_items` table, `quantity` column, and `_form.html.erb` partial must exist as implemented.
- No other in-flight specs are affected. This change touches one field in one partial and adds one new JS controller file.
