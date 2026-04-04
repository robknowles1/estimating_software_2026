# ADR-002: PDF Generation Strategy — Browser Print CSS for MVP

**Status:** accepted
**Date:** 2026-04-01
**Deciders:** architect-agent

---

## Context

The application needs to produce two document outputs per estimate:
1. An internal cost sheet (full detail including unit cost, markup, sell price — estimators only).
2. A client-facing proposal (sell prices only, no internal cost detail, branded header).

The spec asks whether to use browser print CSS or a server-side PDF gem (Grover or Prawn). This decision affects deployment complexity, output fidelity, and future maintainability.

The constraints:
- Rails 8.1 on PostgreSQL, deployed via Kamal (Docker container).
- No background processing required for MVP.
- No email delivery of PDFs required for MVP.
- Propshaft asset pipeline (no Webpacker/Node build step in the app itself).
- Grover requires a Chromium binary in the container. Prawn requires no external binaries but produces lower-fidelity output for HTML-designed layouts.

## Decision

Use browser print CSS for MVP. Provide two dedicated print layout views (`/estimates/:id/cost_sheet` and `/estimates/:id/client_pdf`) that render print-optimized HTML. The estimator opens the view and uses the browser's print-to-PDF function.

Do not add Grover or Prawn to the MVP Gemfile. Revisit server-side PDF generation as a fast-follow if estimators report the browser print flow as unacceptable.

## Rationale

**The practical case for browser print CSS is strong for this stage.** The cost sheet and client proposal are both tabular documents — estimates with line items grouped by section. HTML tables with a print stylesheet produce correct, readable output with near-zero additional code. Modern browsers (Chrome, Edge, Safari) print-to-PDF with reliable fidelity for this kind of layout.

**Grover's deployment cost is real.** Grover uses Puppeteer under the hood and requires a Chromium binary available in the Docker container. The Dockerfile must be modified, the image size grows by ~300–400 MB, and the Kamal deployment config must account for it. On a small, single-server deployment for a 2–5 person shop this is an unnecessary operational burden at MVP. If a headless Chromium is needed later for other reasons (e.g., automated proposal delivery), revisiting becomes easy.

**Prawn is rejected entirely** for this use case. Prawn generates PDFs programmatically with a Ruby DSL. It does not consume HTML/CSS, so any design change requires modifying both the HTML view and the Prawn layout in parallel. For a document that is already being designed as HTML, this is duplicate work with no clear benefit.

**The user workflow is acceptable.** Estimators at a millwork shop are already printing PDFs from Excel. Opening a browser tab and hitting Cmd+P / Ctrl+P is no more friction than Excel's print dialog. The resulting file can be saved or dragged into an email attachment.

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Browser print CSS (chosen) | Zero new dependencies, no container changes, easy to style with existing CSS knowledge | User must manually invoke print; no automated email delivery | N/A — this is the chosen option |
| Grover (Puppeteer/Chromium) | Server generates PDF programmatically; enables future automated email delivery | Adds ~400 MB Chromium to Docker image; adds complexity to Kamal deploy; synchronous PDF generation blocks a request thread | Operational complexity unjustified for MVP; can be added later |
| Prawn | Generates PDFs in pure Ruby, no binaries | Does not consume HTML; requires a parallel Ruby layout DSL; any design change requires two-file edits | Maintenance burden is too high for a document-heavy feature |
| WickedPDF (wkhtmltopdf) | Mature gem, HTML-to-PDF | wkhtmltopdf is effectively unmaintained and has known rendering issues on modern CSS; similar container size problem as Grover | Dependency on an unmaintained project is unacceptable |

## Consequences

### Positive
- No new gems or binaries required.
- Print layouts are standard ERB views with a print CSS media query; any developer familiar with Rails can maintain them.
- Separate routes and layouts for cost sheet vs. client PDF cleanly enforce what is shown to whom (no conditional column hiding).
- Easy to add a "Print" button that opens the print dialog via `window.print()` called from a small Stimulus controller.

### Negative
- Cannot programmatically send PDFs by email from the app without adding a server-side PDF generator later.
- Print output quality depends on the browser and the estimator's print settings (margins, headers/footers). The CSS must use `@page` rules to control this reliably.
- No programmatic page break control beyond CSS `page-break-before`/`page-break-after` properties (which are well-supported but occasionally have browser inconsistencies).

### Risks
- **Risk:** Estimator sends an email with the wrong layout (cost sheet instead of client PDF) because both are accessible. Mitigation: give the two routes distinct, self-describing names and use different page titles; consider making the cost sheet route only render in print mode (i.e., redirect back if `?format=html` without `?print=true`).
- **Risk:** If the shop later wants to email proposals directly from the app, the browser print approach cannot support that. Mitigation: the two print layout views will map directly to what Grover would render, so adding Grover later is an additive change, not a rewrite.

## Implementation Notes

- Create two controller actions: `EstimatesController#cost_sheet` and `EstimatesController#client_pdf`.
- Use a separate minimal layout (`layouts/print.html.erb`) with no navigation chrome, no Turbo, no Stimulus — just a bare HTML document with a stylesheet link.
- The print stylesheet lives at `app/assets/stylesheets/print.css` and is included only in the print layout. It should define `@page { size: letter; margin: 0.75in; }` and `@media print { ... }`.
- The client PDF view must never render `unit_cost`, `markup_percent`, or `extended_cost` columns. This is a server-side concern, not a CSS hide. Do not use `display:none` on sensitive columns in the client PDF view — render a separate template that structurally omits them.
- Add a `before_action :require_login` guard on both actions.
