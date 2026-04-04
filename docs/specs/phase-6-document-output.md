# Spec: Phase 6 — Document Output (Cost Sheet and Client PDF)

**ID:** SPEC-008
**Status:** draft
**Priority:** medium
**Created:** 2026-04-04
**Author:** pm-agent

---

## Summary

This phase adds the two printed documents that are the end product of every estimate: an internal cost sheet (full detail, not shared with clients) and a client-facing proposal (sell prices only, no internal costs or markup). Both are rendered as print-ready HTML using a minimal print layout and CSS print stylesheet. No third-party PDF generation library is used (per ADR-002 — browser print is sufficient for MVP). The client document uses a structurally separate template that never renders internal cost columns — CSS hide/show must not be used as a security shortcut.

## User Stories

- As an estimator, I want to print an internal cost sheet that shows all cost details so that I can review job costing and margins internally.
- As an estimator, I want to generate a client-facing proposal that shows the scope and price without exposing our internal costs or markup so that I can send a professional document to the client.

## Acceptance Criteria

1. Given a saved estimate, when an estimator clicks "Print Cost Sheet," a new browser tab opens with a print-ready page and the browser print dialog triggers automatically.
2. The internal cost sheet includes: estimate number, client company name, job title, job date range, section names, and for each line item: description, quantity, unit, unit cost, markup percent, extended cost, and sell price. Section subtotals and a grand total of both extended cost and sell price are shown.
3. The internal cost sheet does not include navigation, Turbo Drive, or any application chrome — only the printed document content.
4. Given a saved estimate, when an estimator clicks "Print Client PDF," a new browser tab opens with a print-ready client proposal and the browser print dialog triggers automatically.
5. The client proposal includes: a branding header area (company name/logo placeholder), client company name and primary contact name, estimate number, job title, job date range, client_notes from the estimate, section names, and for each line item: description and sell price only.
6. The client proposal structurally omits unit_cost, markup_percent, extended_cost, and any internal cost columns. These fields must not appear in the template at all — they may not be hidden with CSS.
7. The client proposal shows a grand total of sell prices. It does not show extended costs or a cost/markup breakdown.
8. Given an estimate with `client_notes` populated, those notes appear in the client proposal in a visually distinct area (e.g., below the header, above the line items).
9. Given an estimate with no line items in a section, that section is omitted from both output documents.
10. Both output documents are printable via the browser's native print dialog and render without application navigation or interactive elements.

## Technical Scope

### Data / Models

- No new models or migrations.
- `EstimateTotalsCalculator` from Phase 4 is used to supply totals to both print views.

### API / Logic

- Two new actions on `EstimatesController`:
  - `GET /estimates/:id/cost_sheet` → renders with `layouts/print.html.erb`, full detail template.
  - `GET /estimates/:id/client_pdf` → renders with `layouts/print.html.erb`, client-safe template.
- Both actions require login.
- Both actions use `EstimateTotalsCalculator` to supply section subtotals and grand total.
- Add named routes: `cost_sheet_estimate_path` and `client_pdf_estimate_path`.

### UI / Frontend

- New layout: `app/views/layouts/print.html.erb`
  - Minimal HTML structure: no nav, no Turbo Drive (`<meta name="turbo-visit-control" content="reload">` or omit Turbo entirely), no JavaScript except the optional auto-print snippet.
  - Links `app/assets/stylesheets/print.css`.

- `app/assets/stylesheets/print.css`
  - `@page` rule: set margins (e.g., 0.75in all sides), paper size A4 or Letter.
  - Hide any non-print elements.
  - Table styles: clear borders, readable font sizes, column widths.
  - Page break rules for sections.

- Cost sheet template: `app/views/estimates/cost_sheet.html.erb`
  - Header: estimate number, client name, title, job date range.
  - For each section: section name, table of line items with all columns (description, qty, unit, unit_cost, markup%, extended_cost, sell_price), section subtotal row.
  - Footer: grand total extended_cost and sell_price.

- Client proposal template: `app/views/estimates/client_pdf.html.erb`
  - Header: branding area (placeholder for shop logo — a `<div class="branding">` with the shop name as text until OQ-09 is resolved), client company name and primary contact name, estimate number, title, date.
  - `client_notes` block if present.
  - For each non-empty section: section name, table of line items with only description and sell_price columns.
  - Footer: grand total sell_price.
  - No unit_cost, markup_percent, or extended_cost anywhere in this file.

- Optional Stimulus controller (lightweight): `auto_print_controller.js` — on `connect()`, calls `window.print()`. Applied via `data-controller="auto-print"` on the print layout body.

- "Print Cost Sheet" and "Print Client PDF" buttons on the estimate show/edit page. Both open in a new tab (`target: "_blank"`).

### Background Processing
- None.

## Test Requirements

### Unit Tests

- None new — `EstimateTotalsCalculator` is already covered by Phase 4 tests.

### Integration Tests

- `GET /estimates/:id/cost_sheet` without login: redirects to login.
- `GET /estimates/:id/cost_sheet` with login: returns 200, response body includes estimate number, line item descriptions, unit_cost values, markup_percent values.
- `GET /estimates/:id/client_pdf` with login: returns 200, response body includes estimate number and sell_price values.
- `GET /estimates/:id/client_pdf` with login: response body does NOT include `unit_cost` values, `markup_percent` values, or the string "markup" in any data-bearing context.
- `GET /estimates/:id/cost_sheet` for an estimate that belongs to another user: returns 200 (all authenticated users can view all estimates for MVP).

### End-to-End Tests

- Open an estimate, click "Print Cost Sheet," confirm the new tab renders the full cost detail and triggers the print dialog.
- Click "Print Client PDF," confirm the new tab renders without any cost or markup columns.

## Out of Scope

- Server-side PDF generation (Grover, Prawn, WickedPDF) — deferred per ADR-002.
- Email delivery of the client PDF directly from the app (post-MVP).
- Cover page or multi-page layout beyond basic print CSS.
- Dynamic logo upload (OQ-09 — a static placeholder is sufficient until resolved).

## Open Questions

- **OQ-05:** Does the client-facing document show line-item descriptions with sell price, or only section totals? This spec assumes line-item detail with sell price only (per the recommendation in SPEC-001). Confirm with the shop owner before Phase 6 ships. If section-totals-only is preferred, the client_pdf template changes but the controller does not.
- **OQ-09:** Does the shop have a logo for the client-facing PDF header? A text placeholder is used until this is confirmed. No blocker — the placeholder is acceptable for initial delivery.

## Dependencies

- SPEC-006 (Phase 4 — Line Items and Totals) must be complete. Both print views depend on `EstimateTotalsCalculator` and the line item data model.
- OQ-05 and OQ-09 should be confirmed with the shop owner before this phase is marked done, but are not blockers for beginning development.
