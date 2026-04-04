# ADR-003: Real-Time Totals — Turbo Frames with Server-Rendered Partials

**Status:** accepted
**Date:** 2026-04-01
**Deciders:** architect-agent

---

## Context

User story US-09 requires that section subtotals and the estimate grand total update without a full page reload when a line item is saved or deleted. US-07 additionally requires that the extended cost (quantity × unit cost) and sell price display in real time as the estimator types — before saving.

The spec suggests Turbo Frames for this purpose. This ADR evaluates whether that is the right tool and what the precise architecture should be, because "Turbo Frames for totals" conflates two distinct real-time concerns that need different solutions.

## Decision

Use a two-layer approach:

**Layer 1 — In-form calculations (before save):** A Stimulus controller reads the quantity, unit cost, and markup fields in the line item form and updates display-only total cells in real time as the user types. This is pure client-side arithmetic, no server round-trip.

**Layer 2 — Persisted totals (after save):** When a line item is saved, updated, or deleted, the server responds with a Turbo Stream that replaces the relevant section subtotal partial and the estimate grand total partial. The server is the source of truth for all persisted math.

Do not use Turbo Frames for the totals display directly — use Turbo Streams in the form response. Do not store totals in the database.

## Rationale

**Why Stimulus for in-form calculations:** Totals while the estimator is typing are purely a UX concern — the estimate hasn't been saved yet so there is no server state to sync. A Stimulus controller with a simple `input` event listener is four lines of JavaScript and has zero latency. Making a server round-trip for `50 * 12.50 = 625.00` would be wasteful and would introduce noticeable lag on every keystroke.

**Why Turbo Streams (not Turbo Frames) for persisted totals:** Turbo Frames replace a single frame by navigating to a URL — the response must be a full page with a matching frame. Turbo Streams are a better fit here because saving a line item needs to update *multiple* regions simultaneously: the line item row itself, the section subtotal, and the estimate grand total. These three regions are not nested frames; they are siblings in the DOM. Turbo Streams can target all three in a single response with three `<turbo-stream action="replace">` tags.

**Why not a JavaScript SPA or reactive framework:** This is a database-backed form application, not a spreadsheet. The complexity ceiling for the estimate editing page is manageable with Hotwire. Adding React or Vue would require a separate build pipeline, introduce framework churn risk, and make the server-rendered print views harder to share logic with. The Hotwire approach keeps all calculation logic in Ruby (where it is testable as unit tests) and only pushes display updates to the browser.

**Why not broadcast Turbo Streams via WebSocket (Action Cable):** Multi-user real-time collaboration (two estimators editing the same estimate simultaneously) is explicitly not required in the MVP. Action Cable/solid_cable adds operational complexity that is not justified by a single-user editing session. A single estimator saves a form, the response updates their browser. That's it.

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Turbo Frames for totals (spec suggestion) | Simple mental model | Can only replace one region per response; grand total and section subtotals are siblings, not nested frames | Wrong tool for multi-region updates |
| Turbo Streams on form response (chosen) | Updates multiple DOM regions in one response; server is authoritative | Slightly more template setup (stream response + partials) | N/A — this is the chosen option |
| JavaScript-calculated totals (all client-side) | No server round-trips ever | Business logic duplicated in JS and Ruby; JS becomes source of truth for prices | Logic duplication is a correctness and audit risk |
| Action Cable live broadcast | Enables multi-user real-time | Heavy infrastructure; not needed; overkill for MVP | Out of scope; adds solid_cable/Redis complexity |
| React/Vue SPA | Rich interactivity | Separate build pipeline; breaks server-rendered print views | Not proportionate to the problem |

## Consequences

### Positive
- All pricing calculations live in Ruby and are testable with Minitest unit tests — no JS test infrastructure needed for the math.
- The Stimulus controller for in-form display is stateless and tiny; it reads DOM values and writes to display spans. Easy to maintain.
- Turbo Stream responses are explicit and readable: each response names exactly which DOM IDs it updates.
- Print views work without any JavaScript involvement because totals are calculated server-side at render time.

### Negative
- The developer must maintain named DOM IDs that the Turbo Stream responses target (e.g., `section_42_subtotal`, `estimate_7_grand_total`). If these IDs drift between the view and the stream partial, updates silently fail. Naming conventions must be documented and enforced via review.
- Two separate mechanisms for "totals" (Stimulus for in-form, Turbo Streams for post-save) may initially confuse a developer who expects one approach. The distinction must be clearly commented.

### Risks
- **Risk:** Line item save response is slow enough that the estimator sees stale totals briefly after submit. Mitigation: PostgreSQL writes are fast for this workload; the section subtotal partial is a simple SUM query. If latency becomes a problem, the Stimulus controller can optimistically update the totals display immediately on submit and let the stream response confirm.
- **Risk:** Turbo Stream targets a DOM ID that no longer exists (e.g., estimator navigated away). Mitigation: Turbo gracefully ignores stream updates for missing IDs. No error handling required.
- **Risk:** The in-form Stimulus calculation diverges from the server calculation (e.g., rounding). Mitigation: In-form display is labeled "estimated" or uses `~` prefix; the canonical values shown after save come from the server.

## Implementation Notes

**Stimulus controller** (`line_item_calculator_controller.js`):
- Targets: `quantityInput`, `unitCostInput`, `markupInput`, `extendedCostDisplay`, `sellPriceDisplay`.
- Action: `input->line-item-calculator#calculate` on all three inputs.
- No fetch calls. Pure arithmetic.

**Turbo Stream response** from `LineItemsController#create`, `#update`, `#destroy`:
- Respond with `format.turbo_stream` that renders a stream template.
- Stream template issues three actions:
  1. Replace the line item row partial (or remove it on destroy).
  2. Replace the section subtotal partial (identified by `section_#{section.id}_subtotal`).
  3. Replace the estimate grand total partial (identified by `estimate_#{estimate.id}_totals`).

**DOM ID conventions:**
```
dom_id(section, :subtotal)    # => "subtotal_estimate_section_42"
dom_id(estimate, :totals)     # => "totals_estimate_7"
```
Use Rails `dom_id` helper consistently to avoid string typos.

**Calculator service:** `EstimateTotalsCalculator.new(estimate).call` returns a struct with `section_subtotals` (hash keyed by section id) and `grand_total_cost`, `grand_total_sell`. Partials call this service; they do not do arithmetic inline.
