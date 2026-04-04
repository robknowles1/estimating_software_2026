# ADR-001: Markup Level — Per Line Item with Section Default Inheritance

**Status:** accepted
**Date:** 2026-04-01
**Deciders:** architect-agent

---

## Context

Every line item in an estimate needs a markup percentage applied to its cost to produce a sell price. The question is where that markup value lives in the data model. Three structural options exist: stored once on the estimate (global), stored per section, or stored per line item. The spec recommends per-line-item with a section-level default that pre-fills new items.

An important signal from the Excel template: the existing spreadsheet separates costs into distinct COGS categories — Materials (100), Engineering (200), Shop Labor (300), Install Labor (400), Sub-Install (500), Countertops (600), Sub-Other (700). These categories carry different margins in practice. A crown molding material line and an installation labor line would typically have different markups even within the same estimate section.

## Decision

Store `markup_percent` on `LineItem`. Add a `default_markup_percent` column to `EstimateSection`. When a new line item is created within a section, the section's `default_markup_percent` pre-fills the line item's `markup_percent` field; the estimator can override it.

Do not store markup at the `Estimate` level for MVP. Do not make line item markup a function of section markup at read time (no inheritance cascade — the value is stamped on the row at creation).

## Rationale

The per-line-item approach wins on correctness. Different cost types (labor vs. material vs. subcontract) carry structurally different margins in millwork shops, and those cost types often appear in the same section of an estimate. Locking a single markup to a whole section would force estimators to split sections artificially or accept incorrect margins.

The section default is a UX convenience, not a data constraint. It reduces repetitive entry for sections where most items share a markup, while leaving the door open for exceptions. The value is stamped on the row at insert time — it does not dynamically inherit from the section. This means that changing a section default later does not silently reprice existing line items, which is the correct behavior for an estimating tool where historical figures need to be stable.

Estimate-level markup is not added because it creates ambiguity: does it override line items, average them, or only apply to items with no markup set? That ambiguity is not worth carrying into MVP.

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Markup at estimate level only | Simplest schema, one value to set | All items get same margin regardless of cost type | Materials and labor carry different margins; this would force incorrect pricing |
| Markup at section level only (no per-line override) | Cleaner UI for simple jobs | Cannot mix labor and material in the same section with different margins | Too restrictive for real millwork estimates |
| Per-line-item with no section default | Maximum flexibility | Every new item requires a manual markup entry; high friction | UX regression over the Excel template |
| Three-level cascade (estimate → section → line item) | Maximum configurability | Complex inheritance rules; hard to audit what markup is actually applied | Premature complexity; audit risk outweighs flexibility gain |

## Consequences

### Positive
- Correct margins are always explicit and stable on the row.
- No hidden recalculation risk when section defaults are edited later.
- The Excel template's distinct labor/material cost types can be mapped to line items with different markups without schema changes.
- Straightforward to calculate: `sell_price = quantity * unit_cost * (1 + markup_percent / 100.0)`.

### Negative
- If an estimator wants to change markup on all 30 line items in a section, they must either edit each one or we provide a bulk-update UI. A bulk-update action (e.g., "apply this markup to all items in section") is a reasonable post-MVP addition.
- `default_markup_percent` on `EstimateSection` adds a column that requires explanation in the UI.

### Risks
- **Risk:** Estimator creates many items, then realizes all markups are wrong because the section default was not set. Mitigation: display the section's default markup prominently above the "Add line item" button; validate that markup_percent is not null or zero before the estimate can be marked as "sent".
- **Risk:** `markup_percent` null on a line item silently produces a zero-margin item. Mitigation: database-level NOT NULL with a default of 0, plus a model validation warning (not hard block) when markup is 0.

## Implementation Notes

Schema additions beyond the spec sketch:

```
estimate_sections
  default_markup_percent  decimal(5,2)  not null  default 0.0

line_items
  markup_percent          decimal(5,2)  not null  default 0.0
```

Use `decimal` not `float` for all monetary and percentage columns to avoid floating-point drift in totals. Rails maps `decimal` to `NUMERIC` in PostgreSQL.

The `LineItem` model should expose `extended_cost` and `sell_price` as computed methods, never stored columns:

```ruby
def extended_cost = quantity * unit_cost
def sell_price    = extended_cost * (1 + markup_percent / 100.0)
```

Section and estimate totals should be aggregated in a plain Ruby service object (e.g., `EstimateTotalsCalculator`) that accepts an estimate and returns a structured result, rather than being embedded in view helpers or AR callbacks. This makes the logic independently testable and keeps the model thin.
