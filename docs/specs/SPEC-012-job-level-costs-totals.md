# Spec: Job-Level Costs and Final Totals

**ID:** SPEC-012
**Status:** ready
**Priority:** high
**Created:** 2026-04-10
**Author:** pm-agent

---

## Summary

This phase completes the numeric surface of the estimate by wiring in all job-level cost fields (travel, delivery, per diem, hotel, airfare) and exposing the estimate settings that control burden calculations (crew sizes, miles, PM/supervision %, profit/overhead %, tax rate, tax exempt flag, countertop quote). The `EstimateTotalsCalculator` is extended to incorporate these values and produce a final burdened total and COGS breakdown matching the spreadsheet's "totals" area. After this phase, a fully numeric estimate is achievable: all fields from the original Excel template are enterable, and the grand totals match a hand-calculated reference estimate.

## User Stories

- As an estimator, I want to enter job travel, delivery, per diem, hotel, and airfare quantities for a job so that those fixed costs are included in the estimate total.
- As an estimator, I want to set delivery and per diem rates per estimate so that I can override the defaults when a job has unusual logistics.
- As an estimator, I want to configure crew sizes, mileage, on-site time, and percentage markups in one place so that all totals reflect the real job parameters.
- As an estimator, I want to enter a countertop quote as a separate line so that it appears in the final totals and COGS breakdown without inflating the cabinetry line item costs.
- As an estimator, I want to see a final burdened total with a COGS breakdown so that I can present a complete job cost to the shop owner.
- As an estimator, I want the final totals panel to always be visible as I scroll through line items so that I can see the bottom line at any time.

## Acceptance Criteria

1. Given an estimate settings form, when an estimator enters `install_travel_qty`, `delivery_qty`, `delivery_rate`, `per_diem_qty`, `per_diem_rate`, `hotel_qty`, and `airfare_qty` and saves, the values are persisted on the estimate record.
2. Given an estimate settings form, when an estimator enters `installer_crew_size`, `delivery_crew_size`, `miles_to_jobsite`, `on_site_time_hrs`, `pm_supervision_percent`, `profit_overhead_percent`, `tax_rate`, `tax_exempt`, and `countertop_quote` and saves, the values are persisted. Note: `equipment_cost` is explicitly deferred to a future spec — it must not appear in this form and is not wired into any calculation in this phase (see Out of Scope).
3. Given default values for a new estimate, `delivery_rate` defaults to 400.00, `per_diem_rate` defaults to 65.00, `installer_crew_size` defaults to 2, `delivery_crew_size` defaults to 2, `pm_supervision_percent` defaults to 4.00, and `profit_overhead_percent` defaults to 10.00.
4. Given saved job-level cost fields, the calculator computes job-level fixed costs as:
   - Install travel cost = `install_travel_qty * installer_crew_size * mileage_rate * 2` (round trip, federal mileage rate from `Rails.application.config.burden_constants[:mileage_rate]`).
   - Delivery cost = `delivery_qty * delivery_rate`.
   - Per diem cost = `per_diem_qty * per_diem_rate * installer_crew_size`.
   - Hotel cost = `hotel_qty * installer_crew_size * hotel_rate`, where `hotel_rate = $150.00/night` (configured in `config/initializers/burden_constants.rb`).
   - Airfare cost = `airfare_qty * installer_crew_size * airfare_rate`, where `airfare_rate = $400.00/person/ticket` (configured in `config/initializers/burden_constants.rb`).
5. Given the calculator result, `burdened_total = (grand_non_burdened_total * burden_multiplier) + sum(job_level_fixed_costs)`, where `burden_multiplier = (1 + profit_overhead_percent / 100) * (1 + pm_supervision_percent / 100)`.
6. Given the calculator result, the COGS breakdown presents the following named totals:
   - 100 Materials: sum of all line item material subtotals.
   - 200 Engineering: `grand_non_burdened_total * (pm_supervision_percent / 100)`.
   - 300 Shop Labor: sum of detail, mill, assembly, customs, and finish labor subtotals across all line items.
   - 400 Install: sum of install labor subtotals across all line items + install travel cost + per diem cost + hotel cost + airfare cost.
   - 500 Sub Install: zero (reserved for future use; display as $0.00).
   - 600 Countertops: `countertop_quote`.
   - 700 Sub Other: zero (reserved; display as $0.00).

   **COGS reconciliation note:** The seven COGS categories represent the job's **cost structure** — what the job actually costs to deliver. The `burdened_total` is the **selling price** — costs multiplied by the burden multiplier, plus job-level fixed costs. These two figures are intentionally different and must NOT be expected to sum to the same number. The developer and test writer must not write a test asserting that `cogs_breakdown.values.sum == burdened_total`.

   The COGS categories should sum approximately to `grand_non_burdened_total + job_level_fixed_costs + countertop_quote` — that is, all costs before the profit/overhead markup is applied. This is the useful COGS figure. The gap between this sum and `burdened_total` is the profit/overhead markup, which is intentional and expected. Tests verifying the COGS breakdown should assert that each individual category matches its formula (AC-6 above), not that the aggregate equals `burdened_total`.
7. Given the estimate show page, the final totals panel is displayed in a sticky or fixed-position area visible while the estimator scrolls through line items. It shows: grand non-burdened total, burdened total, and COGS breakdown.
8. Given an estimate with `tax_exempt: true`, job-level fixed costs are not affected (tax exemption applies only to material `cost_with_tax` — it does not alter the burden calculation or job-level costs).
9. Given the estimate settings panel, a change to `tax_rate` triggers the existing recalculation of all material `cost_with_tax` values (from SPEC-010) — the settings form save must invoke the same callback path.
10. Given a hand-calculated reference estimate (test fixture with known inputs and known expected outputs), the calculator result matches the expected values to two decimal places for all named totals.

## Technical Scope

### Data / Models

All columns (`install_travel_qty`, `delivery_qty`, `delivery_rate`, `per_diem_qty`, `per_diem_rate`, `hotel_qty`, `airfare_qty`, `countertop_quote`) were added to `estimates` in the SPEC-010 migration. No new migrations are required in this phase. The `equipment_cost` column also exists in the schema from SPEC-010 but is explicitly out of scope for this phase (see Out of Scope).

#### `Estimate` model updates
- Add validations: `pm_supervision_percent` and `profit_overhead_percent` numericality `>= 0`; `tax_rate` numericality `>= 0`; `installer_crew_size` numericality `> 0` integer; `delivery_crew_size` numericality `> 0` integer.
- Strong params in `EstimatesController` must permit all job-level cost fields and settings fields.

#### `EstimateTotalsCalculator` extension

Extend the calculator from SPEC-011 to add:

1. Job-level fixed cost calculation (AC-4). All rates are read from `Rails.application.config.burden_constants` (set in `config/initializers/burden_constants.rb`): mileage rate `$0.67/mile`, hotel rate `$150.00/night`, airfare rate `$400.00/person/ticket`.
2. Burden multiplier application and `burdened_total` computation (AC-5).
3. COGS breakdown (AC-6) — seven named line items.
4. Man-hours summary: total hours per labor category across all line items; `man_days_install = install_hrs_total / 8.0`.

The calculator's return value object is extended with: `job_level_costs` (hash of named fixed costs), `burdened_total`, `cogs_breakdown` (hash keyed by COGS category name or code), `labor_hours_summary`, `man_days_install`.

### API / Logic

- `EstimatesController#update`: already handles estimate saves. Strong params must now include all job-level cost fields and settings fields. The existing `after_save :recalculate_material_costs` callback handles the tax_rate/tax_exempt case automatically.
- No new controller needed. The estimate settings form is part of the estimate edit/show flow.

### UI / Frontend

- Estimate settings panel: a collapsible panel or slide-over within the estimate layout (not a separate page). Contains two fieldset groups:
  - "Job Costs": `install_travel_qty`, `delivery_qty`, `delivery_rate`, `per_diem_qty`, `per_diem_rate`, `hotel_qty`, `airfare_qty`, `countertop_quote`. Do not include `equipment_cost` — it is deferred (see Out of Scope).
  - "Job Settings": `installer_crew_size`, `delivery_crew_size`, `miles_to_jobsite`, `on_site_time_hrs`, `pm_supervision_percent`, `profit_overhead_percent`, `tax_rate`, `tax_exempt` (checkbox).
  - Single "Save Settings" button. On save, the totals panel updates via Turbo Stream.
- The settings panel is accessible from the estimate header at all times (persistent button, consistent with the materials price book button established in SPEC-010).
- Final totals panel: sticky element (CSS `position: sticky; bottom: 0` or `top: <header height>`) visible while scrolling the line items list. Displays:
  - Grand non-burdened total.
  - Burdened total (prominent, larger text).
  - COGS breakdown table: seven rows with code (100–700), label, and dollar amount.
  - Man hours per category and man days (install).
- Turbo Stream target for the totals panel: `estimate_<id>_totals` (same target id established in SPEC-011). On settings save, the controller re-renders this partial.
- All monetary values formatted with `number_to_currency`. All i18n strings in `config/locales/en.yml`.

### Background Processing
- None.

## Test Requirements

### Unit Tests

- `EstimateTotalsCalculator`: given known install_travel_qty, installer_crew_size, and mileage rate, computes correct install travel cost.
- `EstimateTotalsCalculator`: given known delivery_qty and delivery_rate, computes correct delivery cost.
- `EstimateTotalsCalculator`: given known per_diem_qty, per_diem_rate, and installer_crew_size, computes correct per diem cost.
- `EstimateTotalsCalculator`: `burdened_total` equals `grand_non_burdened * burden_multiplier + sum(job_level_fixed_costs)` to BigDecimal precision.
- `EstimateTotalsCalculator`: COGS category 300 includes detail, mill, assembly, customs, and finish labor only — not install labor.
- `EstimateTotalsCalculator`: COGS category 400 includes install labor subtotal plus install travel, per diem, hotel, airfare costs.
- `EstimateTotalsCalculator`: COGS category 600 equals countertop_quote.
- `EstimateTotalsCalculator`: COGS categories sum to approximately `grand_non_burdened_total + job_level_fixed_costs + countertop_quote` (total costs before profit/overhead markup), NOT to `burdened_total`. Write a test asserting this sum, not equality to `burdened_total`.
- `EstimateTotalsCalculator`: reference estimate fixture — all named totals match expected values to two decimal places.
- `Estimate`: validates numericality of pm_supervision_percent, profit_overhead_percent, tax_rate >= 0.

### Integration Tests

- `PATCH /estimates/:id` with valid job-level cost params: persists values, responds with updated totals partial.
- `PATCH /estimates/:id` with updated `pm_supervision_percent`: recalculates burdened_total in the response.
- `PATCH /estimates/:id` with updated `tax_rate`: triggers material cost_with_tax recalculation (existing SPEC-010 behavior) and reflects in totals.
- `GET /estimates/:id`: renders sticky totals panel with COGS breakdown (verify key text is present).

### End-to-End Tests

- Create a full reference estimate: set material prices, add three product rows with materials and labor, enter job-level costs and settings. Confirm: burdened total and COGS breakdown match a pre-calculated expected output.
- Change `pm_supervision_percent` in the settings panel, save. Confirm: burdened total updates in the sticky totals panel without a full page reload.
- Mark estimate `tax_exempt: true`, save. Confirm: material `cost_with_tax` values equal `quote_price` in the price book, and the change propagates to line item material subtotals in the totals panel.

## Out of Scope

- PDF/print output of the final totals (SPEC-013).
- Soft-delete on estimates (SPEC-014 / Phase 7 polish).
- Labor category management UI — the labor_rates table is seeded but not user-editable in this phase.
- `equipment_cost` field on estimate (a job-level freeform equipment cost distinct from per-line-item equipment). The column exists in the schema from SPEC-010 but is explicitly deferred: it must not appear in the settings form, must not be included in any COGS category, and must not be passed to or used by the calculator in this phase. Its treatment (which COGS bucket it belongs to, whether it is burdened separately) is unresolved and will be specified in a future spec.
- Change order or estimate versioning (post-MVP).
- COGS categories 500 (Sub Install) and 700 (Sub Other) inputs — display as $0.00 in this phase; inputs deferred post-MVP.

## Open Questions

- **OQ-G — RESOLVED:** Hotel rate is confirmed at **$150.00/night** and airfare rate at **$400.00/person/ticket**. Both are added to `config/initializers/burden_constants.rb` as `hotel_rate` and `airfare_rate` keys. These are easy-to-change constants; the shop owner may adjust them before first production use without a code change being required anywhere else.
- **OQ-H — RESOLVED:** The install travel formula is `install_travel_qty * installer_crew_size * mileage_rate * 2` where `install_travel_qty` represents the number of trips (not days). The round-trip factor (`* 2`) reflects a full return journey per trip. This formula matches ADR-008 and is now locked for this phase.
- **OQ-I — RESOLVED (deferred):** `equipment_cost` is explicitly deferred to a future spec. It is removed from this phase's scope entirely. See Out of Scope.
- **OQ-J (non-blocking):** The COGS breakdown in AC-6 allocates Engineering (200) as `grand_non_burdened_total * (pm_supervision_percent / 100)`. This is one interpretation of PM/Supervision cost. Confirm this matches the shop owner's intended COGS methodology before this phase ships. If the interpretation is wrong, only the calculator service and the COGS display partial need updating — no schema change.

## Dependencies

- SPEC-010 must be complete. All new estimate columns (`install_travel_qty`, `delivery_rate`, etc.) are in the database. The `after_save :recalculate_material_costs` callback is active.
- SPEC-011 must be complete. The base `EstimateTotalsCalculator` (flat line item version) must exist. This phase extends it; it does not replace it.

---

## Technical Guidance

**Reviewed by:** architect-agent (via ADR-008)
**Relevant ADRs:** ADR-008 (Calculator section; Decision 3 — no stored calculated fields; OQ-C, OQ-D, OQ-E from ADR-008)

---

### Rate configuration

The file `config/initializers/burden_constants.rb` already exists and currently defines:

```ruby
Rails.application.config.burden_constants = {
  mileage_rate: BigDecimal("0.67"),
  round_trip_factor: 2
}.freeze
```

Extend this file (do not create a new initializer) to add the confirmed hotel and airfare rates:

```ruby
Rails.application.config.burden_constants = {
  mileage_rate:      BigDecimal("0.67"),   # Federal rate; update annually
  round_trip_factor: 2,
  hotel_rate:        BigDecimal("150.00"), # Per person per night
  airfare_rate:      BigDecimal("400.00")  # Per person per ticket
}.freeze
```

The calculator reads these values from `Rails.application.config.burden_constants`. Do not hardcode them inline. This allows the values to be changed in one place and makes them easy to override in test contexts via `stub_const` or by temporarily reassigning `Rails.application.config.burden_constants` in a `around` block.

---

### Reference estimate fixture for AC-10

Before writing the calculator extension, create a test fixture (a FactoryBot-built estimate with known field values and a hardcoded expected output hash). The fixture is the source of truth for the end-to-end and unit tests. Build it from the actual Excel template if possible — use a real estimate the shop has done and verify the expected totals match the spreadsheet output. If a real estimate is not available, construct a synthetic one with round numbers and document the expected math in the spec test file.

---

### Sticky totals panel — CSS approach

Use `position: sticky; bottom: 0` on the totals panel element within the scrollable content area. Do not use `position: fixed` — fixed positioning takes the element out of normal flow and causes width/overlap issues with the estimate layout. If the estimate layout uses a flex column container, sticky will work correctly. Test across the common viewport sizes the shop uses (likely a laptop browser, not mobile).

---

### COGS sum check

The seven COGS categories represent cost structure, not selling price. They should sum approximately to `grand_non_burdened_total + job_level_fixed_costs + countertop_quote` — the total cost to deliver the job before the profit/overhead markup is applied. The gap between this sum and `burdened_total` is exactly the profit/overhead markup, which is the intended margin. Do not write a test asserting `cogs_breakdown.values.sum == burdened_total`. Write a test asserting the expected per-category amounts instead (see Unit Tests above). If a COGS sum assertion is written, it must assert against the pre-markup cost total, not `burdened_total`.
