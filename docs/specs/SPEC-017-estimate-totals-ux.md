# Spec: Estimate Totals UX Improvements

**ID:** SPEC-017
**Status:** done
**Priority:** medium
**Created:** 2026-04-27
**Author:** pm-agent

---

## Summary

Four targeted UI improvements to the Estimate Totals panel on the estimate edit page (`estimates/edit`). The changes fix a sticky-positioning overlap bug, add breathing room to the panel, move per-line-item subtotals onto the individual line item cards where they are more discoverable, and collapse the detailed breakdown tables behind a native `<details>` toggle so the headline totals stay prominent without visual noise. No schema changes, no new gems, no new Stimulus controllers.

## User Stories

- As an estimator, I want the totals panel to stay below the line item list instead of floating over it, so that I can read line items and totals without content overlapping.
- As an estimator, I want each line item card to show its own subtotal, so that I can quickly see each item's contribution without scrolling to the totals panel.
- As an estimator, I want the COGS and labor detail tables collapsed by default, so that the headline totals are prominent and I can reveal the detail on demand.

## Acceptance Criteria

1. **Given** the estimate edit page is rendered, **when** the DOM is inspected, **then** the totals container element (the `<div id="estimate_<id>_totals">` element) has no inline `style` attribute containing `sticky` or `fixed` — the element sits in normal document flow with no inline `style` attribute at all.

2. **Given** the estimate edit page is rendered, **when** the totals panel is inspected, **then** the outer container `<div>` of `_estimate_totals.html.erb` has the Tailwind padding class `p-6` (not `p-5`).

3. **Given** a line item exists on the estimate and `@totals` is present, **when** the line item card is rendered via `_line_item.html.erb`, **then** the card displays the `non_burdened_total` for that line item formatted as currency (`number_to_currency`), right-aligned, on the same row as the description text. The value is read from `totals.line_item_results[line_item.id][:non_burdened_total]`. The display is guarded by `if local_assigns[:totals]` (or `if defined?(totals) && totals`) so that the partial renders without error when `totals` is not passed.

4. **Given** the per-line-item subtotals have moved to the line item cards, **when** `_estimate_totals.html.erb` is inspected, **then** lines 99–112 of the original file — the `<% if estimate.line_items.any? %>` block that iterates `estimate.line_items` and renders `non_burdened_total` per item — are fully removed. The totals partial no longer iterates over line items.

5. **Given** the `render "line_items/line_item"` call in `estimates/edit.html.erb` at line 199, **when** the partial is rendered, **then** the call passes `totals: @totals` as an additional local variable: `render "line_items/line_item", line_item: line_item, estimate: @estimate, totals: @totals`.

6. **Given** the estimate edit page is loaded in a browser, **when** the page first renders, **then** the COGS Breakdown heading (text "COGS Breakdown"), the Job-Level Fixed Costs heading, and the Labor Hours Summary heading are **not visible** — the `<details>` element wrapping them does not have the `open` attribute.

7. **Given** the estimate edit page is loaded and the breakdown is collapsed, **when** the user clicks the `<summary>` toggle element, **then** the COGS Breakdown heading becomes visible (the `<details>` element gains the `open` attribute via native browser behaviour).

8. **Given** the breakdown is open, **when** the user clicks the `<summary>` toggle again, **then** the COGS Breakdown heading is hidden again (the `<details>` element loses the `open` attribute).

9. **Given** the collapsible is implemented, **when** the `_estimate_totals.html.erb` markup is inspected, **then** the headline totals block (Non-Burdened Total and Burdened Total) is outside and above the `<details>` element — it is always visible regardless of the `<details>` state.

10. **Given** the `<summary>` element is rendered, **when** the page is inspected, **then** the summary text uses i18n keys: collapsed state displays `t(".show_breakdown")` ("Show breakdown") and a right-pointing chevron SVG icon; expanded state displays `t(".hide_breakdown")` ("Hide breakdown") and a down-pointing chevron SVG icon. These two keys must be added to `config/locales/en.yml` under `line_items.estimate_totals`.

    Implementation note: use a CSS-only technique — add a Tailwind `open:` variant class on the two `<span>` children inside `<summary>` so that one span is visible when `<details>` is closed and hidden when open, and vice versa. No JavaScript or Stimulus controller required. Example structure:
    ```erb
    <summary class="...">
      <span class="open:hidden"><%= t(".show_breakdown") %> <!-- chevron right --></span>
      <span class="hidden open:inline-flex"><%= t(".hide_breakdown") %> <!-- chevron down --></span>
    </summary>
    ```
    Also add the `list-none` Tailwind class to the `<summary>` element to suppress the browser's native disclosure triangle, since a custom chevron SVG is being used.

    Tailwind's `open:` variant generates a `details[open] .class` selector — apply it to descendant elements inside `<details>` (the `<span>` children of `<summary>` in this case, as shown above). This project uses Tailwind v4 with `@import "tailwindcss"`, where the `open:` variant is a first-class built-in; no custom CSS fallback is needed. Verify it works in the browser; if for any reason it does not fire, fall back to `details[open] .class-name` rules in `app/assets/tailwind/application.css`.

## Technical Scope

### Data / Models
None. No schema changes.

### API / Logic
None. No controller changes.

### UI / Frontend

**File: `app/views/line_items/_estimate_totals.html.erb`**

- Line 1: Replace `p-5` with `p-6` and remove the `style="position: sticky; bottom: 0;"` inline style entirely, so the final opening tag reads: `<div id="..." class="bg-white rounded-xl border border-slate-200 shadow-sm p-6 mt-4">`
- Lines 15–97: Wrap the entire `<div class="grid grid-cols-2 gap-4 ...">` block (the COGS Breakdown, Job Costs, and Labor Hours tables) in a `<details>` element with no `open` attribute. Place a `<summary>` element as the first child of `<details>`. The `<summary>` must display the chevron + label toggle described in AC-10.
- Lines 99–112: Delete the entire `<% if estimate.line_items.any? %>` block.

> **Edge case note:** The totals partial is always rendered with a valid `totals` object — the `estimates#edit` controller assigns `@totals` unconditionally before rendering. However, if `@estimate` has no line items, `EstimateTotalsCalculator` still returns a valid `Result` with an empty `line_item_results` hash and zero-value totals. The `<details>` section will render without error. No nil guard is needed on `totals` itself in this partial.

**File: `app/views/line_items/_line_item.html.erb`**

- In the right-hand `<div class="flex items-center gap-2 flex-shrink-0">` (lines 12–18), add a currency display for the line item subtotal before the Edit/Delete links. Guard the display block with `if local_assigns[:totals]`. Suggested markup:
  ```erb
  <% if local_assigns[:totals] %>
    <% result = totals.line_item_results[line_item.id] %>
    <% if result %>
      <span class="text-sm font-semibold text-slate-700"><%= number_to_currency(result[:non_burdened_total]) %></span>
    <% end %>
  <% end %>
  ```
  The subtotal should appear right-aligned and visually prominent (larger or bolder than the edit/delete link text).

**File: `app/views/estimates/edit.html.erb`**

- Line 199: Update the `render` call from:
  ```erb
  <%= render "line_items/line_item", line_item: line_item, estimate: @estimate %>
  ```
  to:
  ```erb
  <%= render "line_items/line_item", line_item: line_item, estimate: @estimate, totals: @totals %>
  ```

**File: `config/locales/en.yml`**

- Under `en.line_items.estimate_totals`, add:
  ```yaml
  show_breakdown: "Show breakdown"
  hide_breakdown: "Hide breakdown"
  ```

**File: `app/assets/tailwind/application.css`**

- No changes expected. A `details[open] .class-name` fallback may be added here only if the `open:` Tailwind variant does not work as expected during implementation.

### Background Processing
None.

## Test Requirements

### Unit Tests
None required — this is a view-only change.

### Integration Tests
None required.

### End-to-End Tests

Add to `spec/system/estimates_spec.rb` (or create `spec/system/estimate_totals_spec.rb` if the existing file exceeds ~200 lines). All specs require: a signed-in user, a persisted estimate with at least one line item, and a visit to the estimate edit page.

**Test 1 — No sticky style (verifies AC-1)**
```
Given the estimate edit page is loaded
Then the totals container element does not have a `style` attribute
  (assert: page has no CSS selector matching `[id^="estimate_"][id$="_totals"][style*="sticky"]`
   and no CSS selector matching `[id^="estimate_"][id$="_totals"][style*="fixed"]`)
```

**Test 2 — Per-line-item subtotal on card (verifies AC-3)**
Given a signed-in user and an estimate that has at least one line item with a deterministic `non_burdened_total` (set up via FactoryBot with known material/labor values, or rely on the existing estimate/line_item factories and compute the expected value from `EstimateTotalsCalculator.new(estimate).call`), when the estimate edit page is loaded, then within the line item card element (`find("##{dom_id(line_item)}")` or `within "#line_item_#{line_item.id}"`) the formatted currency string for that line item's `non_burdened_total` is visible. Use `number_to_currency(totals.line_item_results[line_item.id][:non_burdened_total])` to produce the expected string in the spec setup.

**Test 3 — Breakdown collapsed on load (verifies AC-6)**
```
Given the estimate edit page is loaded
Then the text "COGS Breakdown" is not visible on the page
  (assert: page does not have visible text "COGS Breakdown")
```

**Test 4 — Clicking summary expands breakdown (verifies AC-7)**
```
Given the estimate edit page is loaded and the breakdown is collapsed
When the user clicks the summary toggle (find the <summary> element within the totals panel)
Then the text "COGS Breakdown" becomes visible
  (assert: page has visible text "COGS Breakdown")
```

**Test 5 — Clicking summary again collapses breakdown (verifies AC-8)**
```
Given the breakdown has been expanded per Test 4
When the user clicks the summary toggle again
Then the text "COGS Breakdown" is no longer visible
  (assert: page does not have visible text "COGS Breakdown")
```

**Test 6 — Headline totals always visible (verifies AC-9)**
Given the estimate edit page is loaded and the breakdown `<details>` is collapsed (default state), then the Burdened Total currency string is visible on the page without any user interaction. (Assert: `expect(page).to have_text(number_to_currency(totals.burdened_total))` — the headline total is outside the `<details>` element and must be visible regardless of collapsed/expanded state.)

All system specs must use `driven_by(:selenium_chrome_headless)` and the `DatabaseCleaner` truncation strategy already configured in `spec/rails_helper.rb`.

## Out of Scope

- Persisting the collapsed/expanded state across page loads or sessions.
- Any animation or transition on the `<details>` open/close.
- Moving Job Costs or Labor Hours tables to any location other than inside the same `<details>` element.
- Changes to the Turbo Frame behaviour of the totals panel.
- Any changes to the `_estimate_totals` partial as rendered in contexts other than `estimates/edit`.
- Adding a subtotal to the line item form (new/edit) views — only the card in `_line_item.html.erb` is affected.
- The `<details>` element will revert to its collapsed state after a Turbo Stream replace of the totals panel (triggered when the Job Costs form is submitted). This is accepted behaviour for this iteration.

## Open Questions

None blocking. Implementation may need to verify whether Tailwind's `open:` variant is available in the standalone CLI build in use — if not, the CSS fallback described in AC-10 and the Technical Scope section applies.

## Dependencies

- SPEC-010 through SPEC-016 (all done) — the totals calculator, line item model, and estimate layout are all in place.
- No external system dependencies.
