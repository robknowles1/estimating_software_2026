# Architecture Decision Records — Index

**Project:** Estimating Software MVP
**Last updated:** 2026-04-13

This directory contains Architecture Decision Records (ADRs) for the estimating software project. Each ADR documents a significant technical decision, the alternatives considered, and the rationale.

---

## ADR Status Legend

| Status | Meaning |
|--------|---------|
| proposed | Under discussion; not yet binding |
| accepted | Decision made; implementation may proceed |
| deprecated | Was accepted but is no longer current |
| superseded | Replaced by a later ADR |

---

## Decision Log

| ADR | Title | Status | Date | Key Decision |
|-----|-------|--------|------|-------------|
| [ADR-011](ADR-011-estimate-materials-controller-and-apply-to-estimate.md) | EstimateMaterialsController#create Transaction Design and apply_to_estimate Routing | accepted | 2026-04-13 | Inline transaction (not service object) for dual-path create; POST member route on material_sets for apply_to_estimate; partial application is success not failure; rescue RecordNotUnique on concurrent duplicate add. |
| [ADR-010](ADR-010-materials-per-estimate-product-catalog.md) | Restore Per-Estimate Materials Price Book; Reframe Product Catalog as Template Only | accepted | 2026-04-13 | Restore materials table and _material_id FKs on line_items; remove _unit_price/_description columns from products and line_items; product catalog provides qty defaults and labor hours only, not prices. Supersedes ADR-009. |
| [ADR-009](ADR-009-product-catalog.md) | Product Catalog — Data Model and Line Item Integration | superseded | 2026-04-11 | Superseded by ADR-010. Flat unit_price approach is domain-incorrect for job-specific material pricing. |
| [ADR-001](ADR-001-markup-level.md) | Markup Level | accepted | 2026-04-01 | Markup stored per line item; section provides a default that stamps new items at creation. No estimate-level markup. |
| [ADR-002](ADR-002-pdf-generation.md) | PDF Generation Strategy | accepted | 2026-04-01 | Browser print CSS for MVP. No Grover, Prawn, or WickedPDF. Two separate print layout views (cost_sheet, client_pdf). |
| [ADR-003](ADR-003-realtime-totals.md) | Real-Time Totals | accepted | 2026-04-01 | Two-layer approach: Stimulus for in-form arithmetic (no server call); Turbo Streams on save to update section subtotal and grand total partials. |
| [ADR-004](ADR-004-authentication.md) | Authentication | accepted | 2026-04-01 | has_secure_password + session-based auth. No Devise, Rodauth, or OAuth. Admin creates users; no self-registration. |
| [ADR-005](ADR-005-line-item-entry-ux.md) | Line Item Entry UX | accepted (pending estimator validation) | 2026-04-01 | Pattern C: freeform description field with catalog autocomplete. Accepted contingent on estimator validation session (OQ-02). |

---

## Supporting Documents

| Document | Purpose |
|----------|---------|
| [data-model-review.md](data-model-review.md) | Complete recommended schema, association map, and gap analysis vs. the spec sketch |
| [build-order.md](build-order.md) | Recommended implementation sequence by phase, with dependency graph and open question blockers |

---

## Key Architecture Principles for This Project

1. **Server is the source of truth for all calculations.** Stimulus may display interim arithmetic, but the persisted values always come from Ruby. No business logic in JavaScript.

2. **Two separate templates for cost sheet vs. client PDF.** The client PDF must structurally omit sensitive columns — not hide them with CSS. This is a security boundary.

3. **Decimal columns for all money and percentages.** Never `float`. Use `decimal(10,2)` for currency and `decimal(5,2)` for percentages throughout.

4. **EstimateTotalsCalculator service object.** All section subtotal and grand total logic lives in `app/services/estimate_totals_calculator.rb`. Not in models, not in views, not in helpers.

5. **acts_as_list for position management.** Both `EstimateSection` and `LineItem` use `acts_as_list` to manage the `position` integer. Do not hand-roll position gap-filling logic.

6. **DOM IDs via Rails `dom_id` helper.** All Turbo Stream targets use `dom_id` consistently. No hand-written string IDs. Document the naming convention when introducing new stream targets.

7. **Print layout is a separate Rails layout.** `layouts/print.html.erb` has no Turbo, no Stimulus, no navigation. It is a minimal HTML document.

---

## Open Questions Resolved by ADRs

| OQ | Resolution | ADR |
|----|-----------|-----|
| OQ-01: Markup level | Per line item with section default | ADR-001 |
| OQ-06: PDF generation | Browser print CSS | ADR-002 |
| OQ-08: Job date | Date range (job_start_date + job_end_date) | data-model-review.md |
| OQ-10: User invite flow | Admin creates accounts; no self-registration | ADR-004 |

## Open Questions Still Requiring Stakeholder Input

| OQ | Question | Urgency |
|----|---------|---------|
| OQ-02 | Validate Pattern C with estimators | HIGH — blocks Phase 5 |
| OQ-03 | Client deletion policy | Medium — blocks Phase 2 shipping |
| OQ-05 | Client PDF: line-item detail or section totals only? | Medium — blocks Phase 6 |
| OQ-09 | Shop branding/logo for client PDF | Medium — blocks Phase 6 |
| OQ-11 | Pre-seed catalog from Excel template? | Low — Phase 5 quality |
| OQ-12 | Estimate number format confirmation | Low — confirm EST-YYYY-NNNN |
