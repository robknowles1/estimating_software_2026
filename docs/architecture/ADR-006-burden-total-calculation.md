# ADR-006: Burden Total Calculation

**Status:** accepted
**Date:** 2026-04-05
**Author:** pm-agent (documented from owner recording analysis)
**Relevant specs:** SPEC-006 (Phase 4), SPEC-007 (Phase 5), SPEC-008 (Phase 6)

---

## Context

The estimating spreadsheet produces two financial totals for every cabinet type (section):

- **Non-burdened total** — the actual cost to build the cabinet: raw material cost + shop labor at cost. This is the internal cost figure used to evaluate margin.
- **Burdened total** — the sell price to the contractor: non-burdened total plus markup for overhead, profit, PM supervision, and prorated travel/delivery costs.

The burden factors are configured at the **estimate level** (job-level settings), not per cabinet type. This means the burdened total per cabinet changes if the estimator changes, for example, the profit/overhead percentage or the miles to the jobsite.

This ADR documents the formula, the components that feed it, and the implementation decisions that follow from it.

---

## Decision

### Non-Burdened Total Per Section (Cabinet Type)

```
non_burdened = material_cost + labor_cost
```

Where:

```
material_cost = SUM over all material line items of:
  component_quantity × section_quantity × estimate_material.price_per_unit

labor_cost = SUM over all labor line items of:
  hours_per_unit × section_quantity × LaborRate.rate_for(labor_category)
```

- `section_quantity` = the number of cabinets of this type (stored on `EstimateSection#quantity`).
- `component_quantity` = sheets, linear feet, or unit count per cabinet (stored on `LineItem#component_quantity`).
- `hours_per_unit` = labor hours per cabinet per category (stored on `LineItem#hours_per_unit`).
- `estimate_material.price_per_unit` = the per-estimate slot price (stored on `EstimateMaterial#price_per_unit`).
- `LaborRate.rate_for(category)` = the company-wide hourly rate for that labor category (stored in `LaborRate` table).

All arithmetic uses `BigDecimal` throughout to avoid floating-point drift.

### Burden Factors (Estimate Level)

The following job-level settings on the `Estimate` model drive the burden calculation:

| Field | Type | Description |
|---|---|---|
| `profit_overhead_percent` | decimal | Combined profit and overhead markup, applied as a percentage of non-burdened total |
| `pm_supervision_percent` | decimal | Project management and supervision markup, applied as a percentage of non-burdened total |
| `miles_to_jobsite` | decimal | One-way miles; used to calculate travel cost |
| `installer_crew_size` | integer | Number of installers; multiplies travel cost for install crew |
| `delivery_crew_size` | integer | Number of delivery crew members; multiplies travel cost for delivery crew |
| `on_site_time_hrs` | decimal | Hours on-site; used to calculate on-site time cost (if applicable) |

### Travel Cost Calculation

A mileage rate constant (configurable in `app/models/concerns/burden_constants.rb` or `config/initializers/burden_constants.rb`) drives the travel calculation:

```
MILEAGE_RATE = BigDecimal("0.67")   # IRS standard mileage rate; update as needed
ROUND_TRIP_FACTOR = 2               # one-way miles × 2 for round trip

install_travel_cost  = miles_to_jobsite × ROUND_TRIP_FACTOR × installer_crew_size × MILEAGE_RATE
delivery_travel_cost = miles_to_jobsite × ROUND_TRIP_FACTOR × delivery_crew_size × MILEAGE_RATE
total_travel_cost    = install_travel_cost + delivery_travel_cost
```

Travel cost is a **flat dollar amount per estimate** — not per cabinet. To spread it proportionally across sections, it is prorated by each section's share of the non-burdened total:

```
section_travel_share = total_travel_cost × (section_non_burdened / grand_total_non_burdened)
```

If `grand_total_non_burdened = 0`, `section_travel_share = 0` (guard against division by zero).

### Burdened Total Per Section

```
burden_multiplier = (1 + profit_overhead_percent / 100) × (1 + pm_supervision_percent / 100)

burdened_total = (non_burdened × burden_multiplier) + section_travel_share
```

This matches the spreadsheet pattern: percentages are applied multiplicatively (not additively) to avoid double-counting of the percentage base.

### Burdened Unit Price (for Room Breakdown)

```
burdened_unit_price = burdened_total / section_quantity
```

Guard: if `section_quantity = 0`, return `BigDecimal("0")`.

### Alternates and Buy-Outs

Alternate items (`line_item_category = 'alternate'`) and buy-out items (`line_item_category = 'buy_out'`) are **excluded** from the burden calculation. They use a simple sell price formula:

```
sell_price = extended_cost × (1 + markup_percent / 100)
```

For buy-out items, `markup_percent` is the P/O markup (typically a lower rate than the full burden). For alternate items, `markup_percent` defaults to the same rate as buy-outs unless overridden.

The rationale: alternates and buy-outs are not fabricated in the shop — they do not consume shop overhead or PM supervision at the same rate. The contractor is quoted a flat P/O markup on these items.

---

## Implementation Notes

### EstimateTotalsCalculator

The burden calculation lives entirely in `EstimateTotalsCalculator` (see SPEC-006). The calculator must receive the estimate with all associations preloaded:

```ruby
estimate = Estimate
  .includes(estimate_sections: { line_items: :estimate_material })
  .find(id)

result = EstimateTotalsCalculator.new(estimate).call
```

The result struct (defined in SPEC-006) includes:

```ruby
Result = Data.define(
  :section_subtotals,          # { section_id => { non_burdened: X, burdened: Y } }
  :alternate_total,            # { non_burdened: X, sell: Y }
  :buy_out_total,              # { cost: X, sell: Y }
  :grand_total_non_burdened,
  :grand_total_burdened
)
```

### Two-Pass Calculation

Because travel cost proration requires `grand_total_non_burdened` before section-level burdened totals can be computed, the calculator uses a two-pass approach:

1. Pass 1: compute `non_burdened` per section and accumulate `grand_total_non_burdened`.
2. Pass 2: compute `burdened` per section using `section_travel_share = total_travel_cost × (section_non_burdened / grand_total_non_burdened)`.

This is simple iteration over an already-loaded collection — no additional queries.

### Where NOT to Put the Burden Logic

- Not in `LineItem` model methods — line items do not know the estimate's burden factors.
- Not in view helpers — business logic must be testable in isolation.
- Not in AR callbacks — totals are never stored; they are always computed on demand.
- Not in the controller — the controller calls the calculator once and passes the result to views.

### Mileage Rate Configuration

The mileage rate will need to change over time (IRS publishes annual updates). Store it in a constant accessible to the calculator. A simple option is a `YAML` config file loaded into `Rails.application.config`. Do not hardcode it inside the calculator class.

### Rounding

All intermediate calculations use `BigDecimal` with no rounding. Round only at display time using `number_to_currency` (which defaults to 2 decimal places). Do not round at intermediate steps — rounding errors compound in per-room breakdowns.

---

## Alternatives Considered

### Flat Markup Percent Per Cabinet (Rejected)

The original spec used a simple `markup_percent` per line item. This does not model the real spreadsheet correctly. The spreadsheet applies burden factors at the estimate level (profit/overhead and PM supervision are set once per job, not per cabinet line). The per-line-item markup model is retained only for alternates and buy-outs.

### Store Burdened Totals in the Database (Rejected)

Per ADR-003, no totals are stored. The burden multiplier depends on job-level settings that can be edited at any time. Caching burdened totals would require invalidation on changes to any job setting or any line item, which adds complexity without meaningful performance benefit for typical estimate sizes (< 200 line items).

### Additive vs. Multiplicative Burden Percentages (Decided: Multiplicative)

`(1 + profit%) × (1 + pm%)` vs. `(1 + profit% + pm%)`. The spreadsheet uses multiplicative application (matching compound markup conventions in construction estimating). This is what is implemented here.

---

## Consequences

- `EstimateTotalsCalculator` requires two passes over sections (pass 1 for non-burdened totals, pass 2 for burdened). This is O(n) with a small constant — no performance concern.
- The mileage rate constant must be kept up to date by the shop owner (or an admin setting, post-MVP).
- Changing any job-level setting on an estimate invalidates the displayed burdened totals for all sections — but since totals are never stored, the next page load or Turbo Stream update always reflects the latest settings.
- The burdened_unit_price is only meaningful when `section_quantity > 0`. Guards must exist wherever this value is displayed.
