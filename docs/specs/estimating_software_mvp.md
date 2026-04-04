# Spec: Estimating Software MVP

**ID:** SPEC-001
**Status:** draft
**Priority:** high
**Created:** 2026-04-01
**Author:** pm-agent

---

## Summary

This software replaces a manually duplicated Excel template that a millwork/finish-carpentry shop uses to estimate job costs. Today, estimators copy the spreadsheet file for each new job and type everything from scratch. The goal is a web application that centralizes client records, produces structured cost estimates, and outputs both internal cost sheets and client-facing PDF documents — all from a shared, multi-user environment.

This spec covers the Minimum Viable Product (MVP): the smallest releasable version that makes the core workflow faster and more reliable than the Excel template.

---

## Terminology / Jargon Glossary

| Term | Definition |
|---|---|
| Estimate | A document that lists all projected labor and material costs for a job |
| Line item | A single row in an estimate representing one cost (e.g., "Install crown molding, 40 LF") |
| Cost sheet | An internal document showing full cost detail including markup and margins — not shared with clients |
| Client-facing PDF | A summary or proposal document sent to the client, which may hide internal cost details |
| SOV (Schedule of Values) | A formal billing breakdown typically required by General Contractors on commercial projects. **Out of scope for MVP.** |
| GC (General Contractor) | The primary contractor on a construction site who manages subcontractors. Not relevant to MVP scope. |
| Takeoff | The process of measuring quantities from a blueprint or plan (e.g., counting linear feet of trim). Referenced by some estimating tools but not a primary concern here yet. |
| Markup | A percentage added to cost to produce a selling price |
| Assembly | A pre-defined bundle of line items (e.g., "standard door installation" = door + hardware + labor). A potential future feature. |

---

## Overview and Goals

### Problem Statement
The shop currently duplicates an Excel file for every new estimate. This means:
- No central client history or contact records
- No audit trail across estimates
- Multiple estimators cannot collaborate without file conflicts
- Output formatting is entirely manual

### Goals for MVP
1. Replace the Excel copy-and-edit workflow with a structured web app
2. Provide a shared client database all estimators can access
3. Allow multiple users to create and manage estimates without file conflicts
4. Produce a printable internal cost sheet and a client-facing PDF for every estimate

### Non-Goals for MVP
- No complex access control or role-based permissions (authentication only)
- No integration with accounting software
- No blueprint upload or automated quantity takeoff
- No SOV or GC-specific document formats
- No mobile-native application (responsive web is acceptable)

---

## Users and Roles

### Authentication
All users must log in. There is no public access. [DECISION NEEDED: Confirm whether self-registration is allowed or if an admin must invite users.]

### Roles (MVP — single role)
For MVP, all authenticated users have identical capabilities. There is no distinction between admin, estimator, or viewer.

[OPEN QUESTION: Will there ever need to be a read-only role (e.g., for a project manager who should not edit estimates)? Flag for post-MVP.]

---

## Core Entities (Data Model Sketch)

This is a conceptual sketch, not a final schema. Architect should validate relationships and indexing strategy.

### User
| Field | Notes |
|---|---|
| id | Primary key |
| name | Full name |
| email | Unique, used for login |
| password_digest | Encrypted via bcrypt (Rails has_secure_password) |
| created_at / updated_at | Timestamps |

### Client
| Field | Notes |
|---|---|
| id | Primary key |
| company_name | The business name |
| address | Mailing/job site address [OPEN QUESTION: one address or multiple?] |
| notes | Freeform internal notes about the client |
| created_at / updated_at | Timestamps |

### Contact (belongs to Client)
Clients may have multiple contacts (e.g., owner, project manager, accountant).

| Field | Notes |
|---|---|
| id | Primary key |
| client_id | Foreign key to Client |
| first_name | |
| last_name | |
| title | Job title or role (optional) |
| email | Can be blank |
| phone | Can be blank |
| is_primary | Boolean — marks the default contact for correspondence |
| notes | Freeform |

### Estimate
| Field | Notes |
|---|---|
| id | Primary key |
| client_id | Foreign key to Client |
| title | Short name for the job (e.g., "Smith Kitchen Remodel") |
| status | Enum: draft, sent, approved, lost, archived |
| estimate_number | Auto-generated, human-readable (e.g., EST-2026-0042) |
| job_date | Expected project date or range [OPEN QUESTION: single date or start/end range?] |
| created_by_user_id | FK to User who created it |
| notes | Internal notes |
| client_notes | Notes that appear on the client-facing PDF |
| created_at / updated_at | Timestamps |

### EstimateSection
Estimates are divided into sections (equivalent to groupings in the Excel template, e.g., "Cabinetry", "Trim Work", "Labor").

| Field | Notes |
|---|---|
| id | Primary key |
| estimate_id | FK to Estimate |
| name | Section heading |
| position | Integer — controls display order |

### LineItem (belongs to EstimateSection)
Each line item represents one cost entry.

| Field | Notes |
|---|---|
| id | Primary key |
| estimate_section_id | FK to EstimateSection |
| description | Text description of the work or material |
| quantity | Decimal |
| unit | Unit of measure (e.g., LF, SF, EA, HR) |
| unit_cost | Cost per unit (internal) |
| markup_percent | Markup applied to this line item |
| position | Integer — controls display order |
| notes | Internal notes per line item |

Calculated fields (not stored, derived at query/render time):
- `extended_cost` = quantity * unit_cost
- `sell_price` = extended_cost * (1 + markup_percent / 100)

[OPEN QUESTION: Should markup be set per line item, per section, or at the estimate level — or some combination? This directly affects the data model. Needs decision before development begins. **Blocker.**]

### CatalogItem (optional seed data, supports line item entry)
A library of commonly used items that estimators can search and insert as line items. See Line Item Entry section below.

| Field | Notes |
|---|---|
| id | Primary key |
| description | Default description text |
| default_unit | Default unit of measure |
| default_unit_cost | Starting cost (editable at time of insertion) |
| category | Optional grouping for search/filter |

---

## Line Item Entry: Recommended Approach

### Research Summary

Three primary UX patterns exist in estimating and trade software:

**Pattern A — Spreadsheet-style grid**
The interface looks and behaves like Excel: rows, inline-editable cells, tab-to-advance. Examples include Buildertrend's advanced estimate and many legacy tools. Pros: immediately familiar to anyone who has used the Excel template, fast keyboard-driven entry. Cons: harder to build well in a web context, can feel brittle on mobile, difficult to add rich validation or autocomplete without heavy JavaScript.

**Pattern B — Catalog search / item picker**
Estimators search a pre-built item library, select an item, and it is added as a line item with default values that can be overridden. Used by tools like Clear Estimates and parts of Knowify. Pros: enforces consistency, speeds up entry for repeat item types, reduces typos in descriptions. Cons: requires upfront effort to build and maintain the catalog; items not in the catalog require a "custom item" escape hatch.

**Pattern C — Freeform add-a-row with autocomplete**
A simple "Add line item" button opens a form (or inserts a row). As the estimator types a description, autocomplete suggests matching catalog items. They can accept a suggestion or continue typing a custom description. This is a hybrid of A and B. Used by modern tools like Jobber. Pros: low friction for both new and repeat items, catalog is optional/additive rather than required, familiar mental model. Cons: catalog value degrades if nobody maintains it; autocomplete adds some frontend complexity.

### Recommendation

**Implement Pattern C (freeform with autocomplete) for MVP.**

Rationale: The shop is migrating from a freeform Excel template. Forcing them through a catalog search before they can enter a line item will create friction and slow adoption. Pattern C gives them the speed and freedom of the spreadsheet while allowing a catalog to grow organically over time. The catalog starts empty (or pre-seeded from the Excel template) and becomes more useful as estimators use the software.

[DECISION NEEDED: The client (shop owner/estimators) should validate this recommendation before development begins. If they already have a consistent, well-defined set of items they reuse on every job, Pattern B may be preferable and worth the upfront catalog-building effort.]

---

## Key User Stories and Acceptance Criteria

### Authentication

**US-01: Login**
As an estimator, I want to log in with my email and password so that my work is private and attributable to me.

1. Given a registered user, when they submit valid credentials, they are redirected to the dashboard.
2. Given invalid credentials, when the form is submitted, an error message is shown and the user is not logged in.
3. Given an unauthenticated request to any protected route, when the user attempts to access it, they are redirected to the login page.
4. Given a logged-in user, when they click Log Out, their session is destroyed and they are redirected to the login page.

---

### Client Management

**US-02: View client list**
As an estimator, I want to see a list of all clients so that I can quickly find a client when starting a new estimate.

1. Given at least one client exists, when the estimator navigates to the Clients page, they see a list of client company names sorted alphabetically.
2. Given no clients exist, the page shows an empty state with a prompt to add a client.

**US-03: Create a client**
As an estimator, I want to add a new client with their company name and contact details so that I can associate them with estimates.

1. Given the estimator submits a new client form with a company name, the client is saved and they are redirected to the client detail page.
2. Given a missing company name, the form shows a validation error and does not save.
3. Given a saved client, the estimator can add one or more contacts (name, title, email, phone).
4. Given multiple contacts, one can be marked as primary.

**US-04: Edit and delete a client**
As an estimator, I want to update or remove a client record so that our client list stays accurate.

1. Given an existing client, the estimator can update any field and save successfully.
2. Given a client with no estimates, the estimator can delete the client.
3. Given a client with existing estimates, [DECISION NEEDED: block deletion, or allow with warning? Recommend block deletion and require archiving instead to preserve estimate history.]

---

### Estimate Management

**US-05: Create an estimate**
As an estimator, I want to start a new estimate by selecting a client and giving the job a name so that I can begin building the cost breakdown.

1. Given the estimator starts a new estimate, they must select an existing client or be prompted to create one.
2. Given a valid client and title, the estimate is created in "draft" status with an auto-generated estimate number.
3. The estimate number is sequential and human-readable (e.g., EST-2026-0001).

**US-06: Add sections to an estimate**
As an estimator, I want to group line items into named sections so that the estimate is organized and readable.

1. Given a new estimate, the estimator can add a named section (e.g., "Cabinetry").
2. Given multiple sections, they can be reordered by drag-and-drop or up/down controls.
3. Given a section with no line items, the estimator can delete it.
4. Given a section with line items, [DECISION NEEDED: block deletion or cascade-delete line items? Recommend: warn and require confirmation before cascade delete.]

**US-07: Add line items to a section**
As an estimator, I want to add line items to a section by typing a description and entering quantity and cost so that the estimate reflects the actual scope of work.

1. Given a section, the estimator can click "Add line item" to open an entry form/row.
2. Given the estimator types in the description field, matching catalog items are suggested via autocomplete.
3. Given the estimator selects a catalog suggestion, description, unit, and unit cost are pre-filled but remain editable.
4. Given the estimator ignores autocomplete and types a custom description, the line item is saved as-is without requiring a catalog match.
5. Given quantity and unit cost are entered, the extended cost (quantity x unit cost) is calculated and displayed in real time.
6. Given a markup percent is entered, the sell price is calculated and displayed in real time.
7. Given a line item is saved, it appears in the section immediately.
8. Given multiple line items in a section, they can be reordered.

**US-08: Edit and delete line items**
As an estimator, I want to edit or remove line items so that I can correct mistakes or adjust scope.

1. Given an existing line item, the estimator can click to edit any field inline or via a form.
2. Given an edited line item, totals update immediately upon save.
3. Given a line item, the estimator can delete it with a single confirmation.

**US-09: Estimate totals**
As an estimator, I want to see running totals for each section and the full estimate so that I know the bottom line at a glance.

1. Given line items with costs, each section shows a subtotal of extended costs and sell prices.
2. Given all sections, the estimate shows a grand total of costs and sell prices.
3. Given any line item or markup change, totals update without a full page reload.

**US-10: Estimate status**
As an estimator, I want to update the status of an estimate (draft, sent, approved, lost, archived) so that I can track where each job stands.

1. Given an estimate, the estimator can change its status from a dropdown or button set.
2. Given the estimate list view, estimates are filterable by status.

---

### Output / Documents

**US-11: Internal cost sheet**
As an estimator, I want to print or export an internal cost sheet that shows all cost details including markup so that I can use it for internal review and job costing.

1. Given a complete estimate, the estimator can generate a printable internal cost sheet.
2. The cost sheet includes: estimate number, client name, job title, date, all sections with line items (description, quantity, unit, unit cost, markup, extended cost, sell price), section subtotals, and grand totals.
3. The output is either print-ready HTML (browser print dialog) or a downloadable PDF. [DECISION NEEDED: PDF generation library vs. browser print. Recommend browser print via CSS print stylesheet for MVP to avoid adding a PDF generation dependency. Revisit for the client-facing PDF which may need more polish.]

**US-12: Client-facing PDF**
As an estimator, I want to generate a client-facing document that shows the proposed price without exposing our internal costs so that I can send a professional proposal to the client.

1. Given a complete estimate, the estimator can generate a client-facing document.
2. The client document includes: company branding area [OPEN QUESTION: does the shop have a logo and standard header they want to use?], client name and contact, estimate number, job title, date, a summary of work by section (description and sell price, no internal cost or markup visible), and grand total sell price.
3. The document is exportable as a PDF or printable via the browser.
4. [OPEN QUESTION: Does the client-facing document show line-item detail, or only section totals? This is a significant scoping decision. Recommend: show line-item descriptions but only the sell price column, hiding unit cost and markup.]

---

### Estimate List / Dashboard

**US-13: Dashboard / estimate list**
As an estimator, I want to see all estimates on a dashboard so that I can find and resume any job quickly.

1. Given the estimator logs in, they land on the estimates dashboard.
2. The dashboard lists estimates with: estimate number, client name, job title, status, and last-modified date.
3. The list is sortable by date and filterable by status.
4. A search field filters by client name or job title.

---

## Out of Scope for MVP

The following items came up during discovery and are explicitly excluded from the MVP to keep scope manageable. They should be tracked as future specs.

| Item | Notes |
|---|---|
| Role-based access control | All authenticated users have equal access for now |
| SOV (Schedule of Values) | Formal billing breakdown required by General Contractors. Not needed by this shop at this time. |
| GC-specific documents | Any document format required by a General Contractor |
| Blueprint / plan upload | No takeoff or quantity extraction from drawings |
| Accounting software integration | No QuickBooks, Xero, or similar |
| Change orders | Versioned amendments to an approved estimate |
| Purchase orders | Ordering materials against an estimate |
| Time tracking | Logging actual labor against an estimate |
| Mobile native app | Web app with responsive design is acceptable |
| Email delivery | Sending PDFs directly from the app (can be added later) |
| Multi-company / multi-tenant | Single shop, single tenant |
| Customer portal | Clients do not log in to view or approve estimates |

---

## Open Questions and Decisions Log

Ordered by blocking priority. Items marked **BLOCKER** must be resolved before the relevant feature can be built.

| # | Question | Status | Blocker? | Notes |
|---|---|---|---|---|
| OQ-01 | Where is markup applied — per line item, per section, or at the estimate level? | OPEN | YES | Affects data model. Recommend: per line item with a section-level default that pre-fills new items. |
| OQ-02 | Validate the line item entry recommendation (Pattern C: freeform + autocomplete) with the estimators | OPEN | YES | If they prefer a catalog-first workflow, the UX and catalog data model change significantly. |
| OQ-03 | Client deletion: block if estimates exist, or allow with a warning? | OPEN | No | Recommend block deletion to preserve estimate history. |
| OQ-04 | Section deletion: cascade delete line items, or block? | OPEN | No | Recommend warn + confirm before cascade. |
| OQ-05 | Client-facing PDF: line-item detail with sell price only, or section totals only? | OPEN | No | Recommend line-item detail. Ask the estimators what they currently send clients. |
| OQ-06 | PDF generation: browser print stylesheet (simpler) vs. server-side PDF gem (e.g., Grover, Prawn)? | OPEN | No | Recommend browser print for MVP. |
| OQ-07 | Client address: single address or multiple (billing vs. job site)? | OPEN | No | Recommend single address for MVP with a notes field for exceptions. |
| OQ-08 | Estimate job date: single date or date range (start/end)? | OPEN | No | Recommend date range. |
| OQ-09 | Does the shop have a logo/branding for the client-facing PDF header? | OPEN | No | Needed before final PDF layout can be designed. |
| OQ-10 | User invitation flow: admin-invites or self-registration? | OPEN | No | Recommend admin-invites to prevent unauthorized access. |
| OQ-11 | Should the catalog be pre-seeded from the existing Excel template? | OPEN | No | Would accelerate adoption. Requires the Excel file to be analyzed and converted to seed data. |
| OQ-12 | Estimate number format: is EST-YYYY-NNNN acceptable, or does the shop use a different convention? | OPEN | No | Confirm with shop owner. |

---

## Technical Scope Notes

(For the architect and developer — not product decisions.)

### Stack
- Ruby on Rails 8.1 (confirmed from Gemfile)
- PostgreSQL (development and production)
- Hotwire (Turbo + Stimulus) — already in Gemfile; recommended for real-time totals and inline editing without full-page reloads
- Propshaft asset pipeline

### Data / Models
- New models required: User, Client, Contact, Estimate, EstimateSection, LineItem, CatalogItem
- Associations: Client has_many Contacts; Estimate belongs_to Client; Estimate has_many EstimateSections; EstimateSection has_many LineItems

### API / Logic
- All interactions are standard Rails MVC (no separate API needed for MVP)
- Totals calculation should live in a service object or model concern, not in the view
- Estimate number auto-generation should be handled at the model layer with a database-level lock to prevent duplicates under concurrent saves

### UI / Frontend
- Turbo Frames for inline line item editing and real-time total updates
- Stimulus controller for autocomplete on line item description field
- CSS print stylesheet for internal cost sheet output
- No external JavaScript framework required

### Authentication
- Rails has_secure_password (bcrypt gem is currently commented out in Gemfile — must be uncommented)
- Session-based authentication (no JWT, no OAuth for MVP)

### Background Processing
- None required for MVP

---

## Test Requirements

### Unit Tests
- LineItem: extended_cost and sell_price calculations
- Estimate: grand total and section subtotal aggregation
- EstimateSection: position/ordering logic
- Client: validation (company_name required)
- User: authentication (correct password accepts, wrong rejects)
- Estimate: estimate number auto-generation and uniqueness

### Integration Tests
- POST /estimates creates estimate and redirects to edit view
- POST /clients creates client with contact(s)
- PATCH /line_items updates cost and returns updated totals in response
- DELETE /clients with associated estimates returns error or blocked response
- GET /estimates/:id/cost_sheet renders printable layout

### End-to-End Tests
- Full estimate creation flow: log in, select client, add sections, add line items, view totals, generate cost sheet
- Client creation with multiple contacts
- Estimate status change flow

---

## Dependencies

- No other specs exist yet. This is SPEC-001.
- bcrypt gem must be added before authentication work begins (currently commented out in Gemfile)
- Excel template should be reviewed to identify common line item descriptions for catalog seed data

---

## Assumptions

- The shop is a single-location, single-company operation (no multi-tenancy required)
- The developer has reviewed the Excel template file (`Estimating Template - 3.21.26.xltx`) in the repo root and can extract section structure and common line item patterns from it
- "Robust client CRUD" means full create/edit/delete of both the client record and its contacts, not CRM-level features like activity logs or deal pipelines
- The primary output format is print-ready HTML or PDF; no Excel export is required for MVP

---

## Technical Guidance

*Added by architect-agent, 2026-04-01. See `docs/architecture/` for full ADRs and data model review.*

### Decisions Made

- **Markup:** Stored per line item (`markup_percent decimal(5,2) not null`). `EstimateSection` carries `default_markup_percent` to pre-fill new items; value is stamped at creation and does not inherit dynamically. See ADR-001.
- **PDF output:** Browser print CSS only for MVP. Two separate controller actions and templates (`cost_sheet`, `client_pdf`) using a minimal `layouts/print.html.erb`. No Grover, Prawn, or WickedPDF. See ADR-002.
- **Real-time totals:** Two-layer approach. Stimulus controller handles in-form arithmetic (no server call). Turbo Streams on line item save/update/destroy update the section subtotal partial and estimate grand total partial. Totals are never stored in the database. See ADR-003.
- **Authentication:** `has_secure_password` + session-based auth. No Devise or OAuth. Any logged-in user can create other users; no self-registration. See ADR-004.
- **Line item entry:** Pattern C (freeform with catalog autocomplete). Accepted conditionally pending estimator validation session (OQ-02). See ADR-005.

### Schema Changes vs. Spec Sketch

- `job_date` on Estimate replaced with `job_start_date date` and `job_end_date date` (both nullable).
- `status` on Estimate is a string enum (not integer), default `'draft'`.
- `default_markup_percent decimal(5,2) not null default 0.0` added to `estimate_sections`.
- `catalog_item_id integer null` (FK) added to `line_items`.
- `cost_type string null` added to `line_items` (forward compatibility for cost-category reporting; no UI for MVP).
- `quantity` on `line_items` is `decimal(10,4)` (4 decimal places for fractional millwork quantities).
- Partial unique index on `contacts(client_id) WHERE is_primary = true` is required.
- Composite indexes required on `(estimate_id, position)` for sections and `(estimate_section_id, position)` for line items.

### Required Gems (beyond current Gemfile)

- Uncomment `gem "bcrypt", "~> 3.1.7"` — **Day 1 blocker for auth.**
- Add `gem "acts_as_list"` — manages `position` integers for sections and line items.

### Key Service Object

`app/services/estimate_totals_calculator.rb` — all section subtotal and grand total arithmetic lives here. Used by partials and print views. Never put totals math in view helpers or AR callbacks.

### Security Notes

- The client-facing PDF template must structurally omit internal cost columns. Do not use CSS `display:none` on sensitive data — render a separate template.
- The catalog item search endpoint (`GET /catalog_items/search`) must be protected by `require_login`.
- Ensure `config.force_ssl = true` in production. Kamal must be configured for TLS.

### Build Order

See `docs/architecture/build-order.md`. Short sequence: Auth → Clients/Contacts → Estimates/Sections → Line Items + Totals → Catalog/Autocomplete → Print Views → Polish.

### Risks Flagged

1. **bcrypt not in Gemfile** — will cause a runtime error if auth is built without uncommenting it first.
2. **Estimate number generation race condition** — use a database transaction with a lock in the `before_validation` callback. See data-model-review.md.
3. **Excel template has richer cost categories than the spec model** — the COGS structure (Materials/Shop Labor/Install/Engineering/Countertops/Sub) is flattened into a single `unit_cost` + `markup_percent` per line item. This is intentional for MVP but means cost-category reporting is not possible without a future schema change. The `cost_type` nullable column preserves the path.
4. **OQ-02 (Pattern C UX) is conditionally accepted** — must be validated with estimators before the autocomplete Stimulus controller is built in Phase 5. The data model is UX-agnostic.
