# Spec: Proposal / Bid Letter Wizard

**ID:** SPEC-026
**Status:** in-progress
**Priority:** high
**Created:** 2026-05-27
**Author:** spec-agent

---

## Summary

Estimators currently hand-type a Word document for every bid. This spec replaces that workflow with a multi-step wizard that assembles a polished proposal letter and exports it as a PDF. The wizard collects opening details, specifications, room-by-room inclusions with optional photos, design clarifications, alternates, and exclusions, then renders a formatted PDF for download or email delivery. Two modes are supported: Commercial (full structure) and Residential (simplified room-by-room summary with payment terms).

---

## User Stories

- As an estimator, I want to open a wizard from an estimate and fill in proposal details across several focused steps, so that I can stop hand-typing bid letters in Word.
- As an estimator, I want the wizard to remember my progress between sessions, so that I can pause and resume without losing work.
- As an estimator, I want standard design clarifications and exclusions pre-populated so that I only need to add or remove items rather than type them from scratch.
- As an estimator, I want room inclusions pulled from the CSV import (SPEC-025) so that I do not have to re-enter room names.
- As an estimator, I want to attach one or more photos to each room inclusion, so that the proposal can show the client what is planned for each space.
- As an estimator, I want to download the finished proposal as a PDF, so that I can send it to the client in a professional format.
- As an estimator, I want to email the proposal PDF directly from the app, so that I do not have to save and attach it manually.
- As an estimator, I want alternates auto-detected from the estimate, so that I do not have to re-enter pricing that is already in the system.

---

## Definitions

| Term | Definition |
|------|------------|
| Proposal | The wizard-managed document that produces the final bid letter PDF; belongs to one estimate |
| Wizard step | One of the seven sequential screens that collect proposal content |
| Commercial mode | Full seven-step proposal structure targeting commercial/institutional clients |
| Residential mode | Simplified proposal: materials/labour description, room-by-room pricing summary, payment terms, alternates, ideas section |
| Room inclusion | A section of the proposal describing work in one named room, optionally with bullet points and one or more photos |
| Design clarification | A standard or custom statement explaining how work is bid (e.g., door style, drawer construction) |
| Exclusion | A standard or custom item explicitly not included in the bid |
| Alternate | A priced option outside the base bid total, typically identified by a prefix code or label in the estimate |
| Plan date | The date printed on the architectural drawings the bid is based on |
| Addendum | A numbered change issued against the original plans; the proposal lists all addenda used |
| Amount in words | The bid total written out in full English (e.g., "One Hundred Twenty-Three Thousand Dollars") |

---

## Non Goals

- Google Drive save / sync (future).
- Self-service client portal or client-facing link.
- Digital signature collection.
- Proposal revision history or version numbering (the wizard overwrites in place).
- Change-order workflow.
- Invoicing or payment processing.
- Multi-language output.
- Custom PDF themes / branding per client (single company letterhead only in v1).
- Batch proposal generation across multiple estimates.
- Import of proposal content from an existing Word document.
- In-app PDF preview via an embedded viewer (download-only in v1).

---

## Interfaces

**Entry point:** "Create Proposal" button on the estimate show/edit page. Only one proposal per estimate is allowed; if one already exists the button becomes "Edit Proposal."

**Wizard routes (all authenticated, nested under `/estimates/:estimate_id`):**

| Method | Path | Action |
|--------|------|--------|
| GET/POST | `/estimates/:estimate_id/proposals/new` | Create proposal and redirect to step 1 |
| GET | `/estimates/:estimate_id/proposals/:id` | Redirect to current incomplete step |
| GET | `/estimates/:estimate_id/proposals/:id/steps/opening` | Step 1 |
| PATCH | `/estimates/:estimate_id/proposals/:id/steps/opening` | Save step 1, advance |
| GET | `/estimates/:estimate_id/proposals/:id/steps/specifications` | Step 2 |
| PATCH | `/estimates/:estimate_id/proposals/:id/steps/specifications` | Save step 2, advance |
| GET | `/estimates/:estimate_id/proposals/:id/steps/inclusions` | Step 3 |
| PATCH | `/estimates/:estimate_id/proposals/:id/steps/inclusions` | Save step 3, advance |
| GET | `/estimates/:estimate_id/proposals/:id/steps/clarifications` | Step 4 |
| PATCH | `/estimates/:estimate_id/proposals/:id/steps/clarifications` | Save step 4, advance |
| GET | `/estimates/:estimate_id/proposals/:id/steps/alternates` | Step 5 |
| PATCH | `/estimates/:estimate_id/proposals/:id/steps/alternates` | Save step 5, advance |
| GET | `/estimates/:estimate_id/proposals/:id/steps/exclusions` | Step 6 |
| PATCH | `/estimates/:estimate_id/proposals/:id/steps/exclusions` | Save step 6, advance |
| GET | `/estimates/:estimate_id/proposals/:id/steps/review` | Step 7 — review and export |
| GET | `/estimates/:estimate_id/proposals/:id/pdf` | Download PDF |
| POST | `/estimates/:estimate_id/proposals/:id/email` | Send proposal email |

**Outputs:**
- PDF file download (inline `Content-Disposition: attachment`).
- ActionMailer email with PDF attached.

---

## Rules

R1: Each estimate may have at most one proposal record. A second attempt to create a proposal for the same estimate redirects to the existing proposal's current step instead of creating a duplicate.

R2: The proposal mode (`commercial` / `residential`) is selected on the opening step and may be changed on any subsequent visit to step 1 at any time. Mode is never locked — the estimator may switch modes and re-download the PDF as many times as needed.

R3: Wizard progress is persisted after each step save. Navigating away and returning resumes from the earliest incomplete step.

R4: The wizard tracks per-step progress via `current_step`. A step is considered saved once the estimator submits it. Steps with no required fields (e.g., specifications if toggled off) are considered saved when submitted. The proposal `status` field (`draft` / `sent`) is separate from per-step progress and is never used to gate editing.

R5: The "opening" step must capture: client contact (select from the estimate's client's contacts, defaulting to the primary contact), job name (defaults to `estimate.title`), plan date, addendum list (free text), total amount (auto-populated from the estimate's calculated total; editable), and mode selection (commercial or residential).

R6: The total amount displayed and used in the PDF is pulled from `EstimateTotalsCalculator.new(estimate).call.burdened_total` (the client-facing sell price after markup, PM supervision, and job-level costs) at proposal creation time and stored on the proposal record as `total_amount`. It is editable by the estimator to allow manual overrides (e.g., rounding, negotiated price). Changes to the estimate after the proposal is created do not automatically update the stored amount. Note: `burdened_total` is distinct from `grand_non_burdened_total` (which excludes the profit/overhead multiplier and job-level costs).

Three "Refresh from estimate" controls are available to re-sync proposal data with the current estimate state:

- **Refresh total amount** (opening step): recalculates `total_amount` from `EstimateTotalsCalculator.new(estimate).call.burdened_total` and replaces the stored value. No destructive side-effects.
- **Sync rooms from estimate** (inclusions step): destroys all existing `ProposalInclusion` records and recreates them from `estimate.line_items.where.not(room: [nil, ""]).pluck(:room).uniq` (blank/empty room strings are skipped). Bullet points and photos attached to existing inclusions are permanently lost. Requires a confirmation prompt before executing: "This will replace all room inclusions and remove any bullet points and photos. Continue?"
- **Re-detect alternates** (alternates step): destroys all existing `ProposalAlternate` records and recreates them by re-running `AlternateDetectorService` against current line items. Any cost overrides the estimator entered are lost. Requires a confirmation prompt: "This will replace all alternates and reset any cost overrides. Continue?"

R7: The specifications step is conditional on mode. In commercial mode: a toggle ("Include specifications section") controls whether the section appears in the PDF; when toggled on, the estimator enters one or more specification numbers and titles (e.g., `064023 - Interior Architectural Woodwork`). In residential mode: this step is skipped entirely.

R8: Room inclusions (step 3) are pre-populated from distinct room name strings on the estimate's line items. `BuildService` queries `estimate.line_items.where.not(room: [nil, ""]).pluck(:room).uniq` to get the list of room name strings (blank/empty room strings are skipped, since `room_name` is presence-validated) and creates one `ProposalInclusion` per unique name. There is no separate `rooms` table — SPEC-025 stores room as a plain string column on `line_items`. The estimator may add bullet points to each room and optionally attach one or more photos per room. New rooms may be added manually. Rooms may be removed from the proposal without affecting the underlying line item records.

R9: Each room inclusion's photos are stored via ActiveStorage (`has_many_attached :photos`). Photo upload is optional, and a room may have multiple photos. Rooms with photos render each photo (or a photo gallery) in the PDF; rooms without photos render no image block. Allowed types are JPEG and PNG only (rationale: Prawn embeds JPEG/PNG only; WebP would pass a generic image check but fail at PDF render). There is no byte-size limit on uploads — instead a resized variant (longest edge ~2000px) is generated and used for PDF embedding so large originals cannot break or slow PDF generation. The upload UI (delivered in PR 3) must surface the accepted formats to the estimator via the file input's `accept="image/jpeg,image/png"` attribute and a visible "JPEG or PNG" hint.

R10: Design clarifications (step 4) are pre-populated with the standard list on first creation (see Definitions — standard clarifications). The estimator may add custom clarifications and remove any pre-populated or custom item. Order is preserved as entered.

R11: Standard design clarifications pre-populated on proposal creation:
- "All cabinet doors bid as slab and cabinet interiors bid as white melamine"
- "Drawers bid as slab fronts with 3/4" white melamine drawers and soft close undermount drawer slides"

R12: Alternates (step 5) are auto-detected from the estimate's line items. A line item is treated as an alternate if its `description` begins with a recognizable alternate prefix (e.g., `ALT`, `Alternate`, `Alt.`; case-insensitive, prefix detection is configurable via a constant on the `Proposal` model). Each detected alternate is presented with its description and its calculated cost (drawn from the line item). The estimator confirms or adjusts the displayed pricing. Alternate costs are excluded from the base bid total displayed in the proposal.

R13: Exclusions (step 6) are pre-populated with the standard list on first creation. The estimator may add custom exclusions and remove any item.

R14: Standard exclusions pre-populated on proposal creation:
- Man doors
- Install of owner supplied furnishings
- Demolition
- Sinks
- In-wall blocking
- Holiday/after-hours/overtime work
- AWI Certification
- FSC certified material
- LEED certification
- Bonding
- Permits/fees
- Protection of completed work
- Traffic control for deliveries

R15: Step 7 (review) renders a read-only preview of the assembled proposal text and provides three actions: "Download PDF," "Send Email," and "Mark as Sent." The email action requires a recipient address; the proposal contact's email is pre-filled if present. Sending an email automatically sets `proposal.status` to `sent`. "Mark as Sent" allows the estimator to record that the proposal has been delivered by other means (e.g., handed over in person) without sending an email. Downloading a PDF does not change the status. All three actions are available regardless of current status — a `sent` proposal remains fully editable.

R16: The PDF is generated on demand (not cached). Each download regenerates the PDF from current proposal data. PDF generation uses the `prawn` gem (new dependency; no binary runtime required).

R17: The commercial PDF header follows this template:
```
[Company letterhead / address block]
[Date]

Dear [contact first name],

Thank you for the opportunity to bid the [job name]. This proposal is based on
plans dated [plan date] and addenda [addendum list]. The total for the items
listed below is $[amount] ([AMOUNT IN WORDS]).
```

R18: The amount in words (R17) is generated in Ruby using a helper (`ProposalHelper#amount_in_words`) that converts the numeric total to English words. Implement using the `humanize` gem (`gem 'humanize', '~> 2.0'`). Add to Gemfile. The helper calls `amount.to_i.humanize.capitalize` for the dollar portion and formats cents as `/100`. This helper is tested independently.

R19: The residential PDF replaces the specification section with a narrative description of materials and labour, presents a room-by-room pricing table drawn from inclusions, and appends a payment terms section. Payment terms text is free-form and entered on the residential version of the opening step (additional field).

R20: All user-facing strings use Rails i18n lazy lookup (`t(".key")` in views, `t(".notice")` in controllers). All keys live in `config/locales/en.yml`. No hardcoded strings in views or controllers.

R21: All proposal routes require authentication. Unauthenticated requests redirect to the login page. No proposal data is exposed to unauthenticated requests.

R22: A proposal belongs to an estimate and therefore to a client. Any authenticated user may create or edit proposals (no per-user ownership restriction in v1, consistent with the existing estimate auth model noted in the auth gap memo).

R23: Deleting an estimate cascades to delete its proposal (and all child records: inclusions, clarifications, exclusions, alternates).

R24: The wizard step navigation renders a step indicator (e.g., numbered breadcrumbs) showing which steps are complete, the current step, and upcoming steps. Completed steps are clickable for back-navigation. Future steps are not directly reachable until prior steps are saved. In residential mode, the Specifications step is hidden from the step indicator entirely — it is not shown as greyed-out or disabled. The remaining steps are numbered 1–6.

R25: `proposal.status` has two values: `draft` (initial state) and `sent` (informational — proposal has been delivered to the client). Status transitions to `sent` automatically when the estimator sends an email via the review step, or manually when they click "Mark as Sent." Status never gates editing — all wizard steps remain fully editable regardless of status. Downloading a PDF does not change status.

---

## Edge Cases

E1: The estimate has no contacts on the client — the contact selector on the opening step shows an empty list with a notice and a link to add a contact before proceeding.

E2: The estimate's grand total is zero — the total amount field is pre-filled with `0.00` and the estimator must manually enter the correct amount before the PDF is useful. No error is raised; this is a valid (if unusual) state.

E3: No rooms exist from SPEC-025 — the inclusions step opens with an empty list and an "Add room" control. The step may be saved with no rooms (producing a proposal with no inclusions section in the PDF).

E4: The estimate has no alternate line items — the alternates step displays a message ("No alternates detected in this estimate") and may be saved immediately. No alternates section appears in the PDF.

E5: A room inclusion photo is uploaded in an unsupported format (e.g., WebP or GIF) — the upload is rejected with a validation error on the inclusion record and the step cannot be saved until the file is removed or replaced. There is no byte-size limit; large originals are accepted and downscaled via a resized variant for PDF embedding.

E6: A room inclusion photo is not a JPEG or PNG image — rejected with a validation error naming the allowed types (JPEG, PNG). WebP is explicitly rejected because Prawn cannot embed it.

E7: The estimator navigates directly to a future step URL — they are redirected to the earliest incomplete step with a flash notice explaining that earlier steps must be completed first.

E8: PDF generation fails (e.g., Prawn raises) — the controller rescues the error, logs it, and redirects to the review step with an error flash. No partial PDF is served.

E9: The email action is submitted without a recipient address — a validation error is shown on the review step form without sending the email.

E10: A proposal already exists for the estimate and the estimator clicks "Create Proposal" again — they are redirected to the existing proposal's current step with a flash notice: `t(".proposal_already_exists")`.

---

## Acceptance Criteria

AC-1: Given an authenticated estimator on the estimate show page, when they click "Create Proposal," then a new proposal record is created in `draft` status, mode defaults to `commercial`, and the estimator is redirected to step 1 (opening) where mode can be changed. `Covers: R1, R2, R5`

AC-2: Given a proposal already exists for the estimate, when the estimator clicks "Create Proposal" (or "Edit Proposal") on the estimate page, then they are redirected to the existing proposal's current step and no duplicate proposal is created. `Covers: R1, E10`

AC-3: Given the estimator is on the opening step, when they select a client contact, enter a job name, plan date, addendum list, total amount, and mode, and click "Save and continue," then those values are persisted on the proposal and the estimator is advanced to step 2. `Covers: R5, R6`

AC-4: Given the estimate has a primary contact, when the opening step is first loaded, then the contact selector defaults to the primary contact and the job name field defaults to `estimate.title`. `Covers: R5`

AC-5: Given the opening step is submitted with no client contact selected, when the form is submitted, then a validation error is shown and the step is not advanced. `Covers: R5`

AC-6: Given commercial mode and the estimator enables the specifications toggle, when they enter at least one specification number and title and save, then the specifications are persisted and the step is marked complete. `Covers: R7`

AC-7: Given commercial mode and the specifications toggle is off, when the step is saved, then no specification records are stored and the step is marked complete. `Covers: R7`

AC-8: Given residential mode, when the wizard advances past the opening step, then the specifications step is skipped and the estimator goes directly to step 3 (inclusions). `Covers: R7`

AC-9: Given rooms exist from SPEC-025, when the inclusions step is first loaded, then each room is pre-populated as a room inclusion row with the room name displayed and bullet-point and photo fields empty. The photo input advertises the accepted formats via `accept="image/jpeg,image/png"` and a visible "JPEG or PNG" hint. `Covers: R8, R9`

AC-10: Given the inclusions step, when the estimator adds bullet points to a room inclusion and saves, then the bullet points are persisted on the `proposal_inclusions` record. `Covers: R8`

AC-11: Given the inclusions step, when the estimator uploads one or more valid image files (JPEG or PNG, any size) to a room inclusion and saves, then each photo is stored via ActiveStorage and attached to the `proposal_inclusion` record (`has_many_attached :photos`), and a resized variant (~2000px longest edge) is available for PDF embedding. `Covers: R9`

AC-12: Given the estimator uploads a file that is not a JPEG or PNG image (e.g., WebP, GIF, or a PDF), when the form is submitted, then a validation error is shown, the file is not stored, and the step is not advanced. There is no byte-size limit. `Covers: E5, E6`

AC-13: Given the clarifications step is first loaded on a new proposal, when the page renders, then the two standard design clarifications are pre-populated as editable rows. `Covers: R10, R11`

AC-14: Given the clarifications step, when the estimator removes a pre-populated clarification and saves, then that clarification is absent from the persisted `proposal_clarifications` records. `Covers: R10`

AC-15: Given the clarifications step, when the estimator adds a custom clarification text and saves, then it is persisted and appears in the PDF. `Covers: R10`

AC-16: Given the estimate has line items whose descriptions start with `ALT`, `Alternate`, or `Alt.` (case-insensitive), when the alternates step is loaded, then those line items are listed as alternates with their description and calculated cost. `Covers: R12`

AC-17: Given the alternates step, when the estimator edits the displayed cost of an alternate and saves, then the overridden cost is stored on the `proposal_alternates` record and used in the PDF (not the line item's calculated cost). `Covers: R12`

AC-18: Given the estimate has no alternate line items, when the alternates step loads, then a message is shown indicating no alternates were detected and the step may be saved immediately. `Covers: E4`

AC-19: Given the exclusions step is first loaded on a new proposal, when the page renders, then all thirteen standard exclusions are pre-populated as editable rows. `Covers: R13, R14`

AC-20: Given the exclusions step, when the estimator removes one standard exclusion and adds one custom exclusion and saves, then the persisted `proposal_exclusions` records reflect exactly that list. `Covers: R13`

AC-21: Given all steps are saved, when the estimator reaches the review step, then a read-only summary of all entered content is displayed along with "Download PDF" and "Send Email" buttons. `Covers: R15`

AC-22: Given the review step, when the estimator clicks "Download PDF," then a PDF file is generated using Prawn and served as a file download with `Content-Type: application/pdf`. `Covers: R16`

AC-23: Given commercial mode, when the PDF is generated, then the header contains the company address block, date, contact first name, job name, plan date, addendum list, total amount in numeric format, and total amount in English words. `Covers: R17, R18`

AC-24: Given residential mode, when the PDF is generated, then the header section is replaced with a materials/labour narrative, a room-by-room pricing table is included, and a payment terms section appears at the end. `Covers: R19`

AC-25: Given the review step, when the estimator clicks "Send Email," enters a recipient address, and submits, then an ActionMailer email is sent with the PDF attached and a flash notice confirms delivery. `Covers: R15`

AC-26: Given the "Send Email" form is submitted without a recipient address, when the form is processed, then a validation error is shown and no email is sent. `Covers: E9`

AC-27: Given any proposal (draft or sent), when the estimator downloads the PDF, then the PDF is regenerated from current proposal data (not a cached copy). `Covers: R16`

AC-28: Given the wizard step indicator, when the estimator is on step 3, then steps 1 and 2 (if complete) appear as clickable links, step 3 is highlighted as current, and steps 4-7 are non-interactive. `Covers: R24`

AC-29: Given the estimator clicks a completed step in the step indicator, when they arrive at that step, then its previously saved values are pre-filled in the form. `Covers: R3, R24`

AC-30: Given the estimator navigates directly to a future step URL (e.g., step 5 while step 3 is incomplete), when the request is processed, then they are redirected to the earliest incomplete step with a flash notice. `Covers: E7`

AC-31: Given an unauthenticated request to any proposal route, when the request is made, then the response redirects to the login page and no proposal data is exposed. `Covers: R21`

AC-32: Given an estimate is deleted, when the deletion cascades, then the proposal and all child records (inclusions, clarifications, exclusions, alternates, ActiveStorage attachments) are also deleted. `Covers: R23`

AC-34: Given the review step, when the estimator clicks "Send Email" and the email is delivered, then `proposal.status` transitions to `sent`. Given the review step, when the estimator clicks "Mark as Sent," then `proposal.status` transitions to `sent`. In both cases the proposal remains fully editable — all wizard steps are accessible and mode may still be changed. `Covers: R25`

AC-35: Given a `sent` proposal, when the estimator navigates to any wizard step and edits content, then the changes are saved and a fresh PDF download reflects the updated content. `Covers: R2, R25`

AC-36: Given the inclusions step, when the estimator clicks "Sync rooms from estimate" and confirms the prompt, then all existing `ProposalInclusion` records are replaced with inclusions seeded from the current estimate line item rooms. `Covers: R6`

AC-37: Given the alternates step, when the estimator clicks "Re-detect alternates" and confirms the prompt, then all existing `ProposalAlternate` records are replaced with alternates detected from current line items. `Covers: R6`

AC-38: Given the opening step, when the estimator clicks "Refresh total from estimate," then `proposal.total_amount` is updated to the current `EstimateTotalsCalculator` burdened total. `Covers: R6`

---

## Technical Scope

### Data / Models

#### New table: `proposals`

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| estimate_id | bigint | FK → estimates, not null, unique (one proposal per estimate) |
| mode | string | `commercial` or `residential`, not null, default `commercial` |
| status | string | `draft` or `sent`, not null, default `draft` |
| contact_id | bigint | FK → contacts, nullable (selected on opening step) |
| job_name | string | nullable; defaults to estimate.title at creation |
| plan_date | date | nullable |
| addendum_list | text | nullable |
| total_amount | decimal(12,2) | nullable; copied from estimate total at creation |
| include_specifications | boolean | default false |
| payment_terms | text | nullable; residential mode only |
| current_step | string | last saved step name; used for resume-on-return |
| created_at | datetime | |
| updated_at | datetime | |

Migration: `create_table :proposals`.
Add unique index on `estimate_id`.
Add FK `proposals.estimate_id → estimates` with `on_delete: :cascade`.
Add FK `proposals.contact_id → contacts` with `on_delete: :nullify`.

**`Proposal` model:**
- `belongs_to :estimate`
- `belongs_to :contact, optional: true`
- `has_many :proposal_inclusions, dependent: :destroy`
- `has_many :proposal_clarifications, dependent: :destroy`
- `has_many :proposal_exclusions, dependent: :destroy`
- `has_many :proposal_alternates, dependent: :destroy`
- `has_many :proposal_specifications, dependent: :destroy`
- `enum :mode, { commercial: "commercial", residential: "residential" }`
- `enum :status, { draft: "draft", sent: "sent" }`
- `validates :estimate_id, uniqueness: true`
- `validates :mode, presence: true`
- `ALTERNATE_PREFIXES = /\A(alt\.?|alternate)\b/i` — constant used by the alternate detection service.

#### New table: `proposal_inclusions`

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| proposal_id | bigint | FK → proposals, not null |
| room_name | string | not null |
| bullet_points | text | nullable; newline-delimited or JSON array |
| position | integer | display order |
| created_at | datetime | |
| updated_at | datetime | |

Migration: Add FK `proposal_inclusions.proposal_id → proposals` with `on_delete: :cascade`.

**`ProposalInclusion` model:**
- `belongs_to :proposal`
- `has_many_attached :photos` (ActiveStorage) — multiple photos per room.
- A named variant `:pdf` (`resize_to_limit: [2000, 2000]`) is defined on the attachment; PR 4's Prawn PDF embeds this resized variant rather than the original blob. The original blob is kept as-is (bounding stored size is deferred — see pre-production tech debt).
- `validates :room_name, presence: true`
- Photo content type validation: allow only `image/jpeg` and `image/png` (Prawn embeds JPEG/PNG only; WebP/GIF rejected). Validation iterates over every attached photo, guarded by `if: -> { photos.attached? }`.
- No byte-size validation — large originals are accepted and downscaled via the `:pdf` variant.
- `acts_as_list scope: :proposal` (consistent with `LineItem` ordering pattern).
- The upload UI (PR 3) must expose accepted formats via `accept="image/jpeg,image/png"` and a visible "JPEG or PNG" hint.

#### New table: `proposal_clarifications`

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| proposal_id | bigint | FK → proposals, not null |
| body | text | not null |
| position | integer | display order |
| created_at | datetime | |
| updated_at | datetime | |

Migration: Add FK `proposal_clarifications.proposal_id → proposals` with `on_delete: :cascade`.

**`ProposalClarification` model:**
- `belongs_to :proposal`
- `validates :body, presence: true`
- `acts_as_list scope: :proposal`

#### New table: `proposal_exclusions`

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| proposal_id | bigint | FK → proposals, not null |
| body | text | not null |
| position | integer | display order |
| created_at | datetime | |
| updated_at | datetime | |

Migration: Add FK `proposal_exclusions.proposal_id → proposals` with `on_delete: :cascade`.

**`ProposalExclusion` model:**
- `belongs_to :proposal`
- `validates :body, presence: true`
- `acts_as_list scope: :proposal`

#### New table: `proposal_alternates`

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| proposal_id | bigint | FK → proposals, not null |
| line_item_id | bigint | FK → line_items, nullable (nullify on line item delete) |
| description | string | not null; copied from line item at detection time |
| display_cost | decimal(12,2) | not null; populated by `BuildService` from `EstimateTotalsCalculator.new(estimate).call` per alternate line item; estimator-overridable on the alternates step; never nil at PDF render time |
| position | integer | display order |
| created_at | datetime | |
| updated_at | datetime | |

Migration: Add FK `proposal_alternates.proposal_id → proposals` with `on_delete: :cascade`. Add FK `proposal_alternates.line_item_id → line_items` with `on_delete: :nullify`.

**`ProposalAlternate` model:**
- `belongs_to :proposal`
- `belongs_to :line_item, optional: true`
- `validates :description, presence: true`
- `validates :display_cost, presence: true`
- `acts_as_list scope: :proposal`

#### New table: `proposal_specifications`

| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| proposal_id | bigint | FK → proposals, not null |
| spec_number | string | not null; e.g. `064023` |
| spec_title | string | not null; e.g. `Interior Architectural Woodwork` |
| position | integer | display order |
| created_at | datetime | |
| updated_at | datetime | |

Migration: Add FK `proposal_specifications.proposal_id → proposals` with `on_delete: :cascade`.

**`ProposalSpecification` model:**
- `belongs_to :proposal`
- `validates :spec_number, :spec_title, presence: true`
- `acts_as_list scope: :proposal`

#### New gem dependencies

Add `gem "prawn"` and `gem "prawn-table"` to the `Gemfile`. No binary runtime is required (pure Ruby). Note this as a new dependency in the implementation PR.

Add `gem "humanize", "~> 2.0"` to the `Gemfile` for the `amount_in_words` helper (R18).

#### ActiveStorage install — required migration task (PR 1 / data layer)

The `active_storage_blobs`, `active_storage_attachments`, and `active_storage_variant_records` tables do not yet exist in `schema.rb`. Before implementing photo upload on `ProposalInclusion`, the developer **must** run `bin/rails active_storage:install` and commit the three generated migrations (`active_storage_blobs`, `active_storage_attachments`, `active_storage_variant_records`) in the feature branch. This is a required first task in the data layer PR — do not implement `has_many_attached :photos` without it. The `active_storage_variant_records` table is also required to support the `:pdf` resized variant.

AC-33: Before implementing photo upload, `bin/rails active_storage:install` has been run, the three generated migrations have been committed to the feature branch, and `db:migrate` succeeds without error. `Covers: R9`

### Services

All services follow the architecture rules: one public entry point (`.call`), constructor injection, transaction safety, typed returns.

#### `Proposals::BuildService`

File: `app/services/proposals/build_service.rb`

Constructor: `initialize(estimate:)`

`.call` — creates a new `Proposal` record and seeds child records:
1. Sets `job_name` from `estimate.title`, `total_amount` initialised from `EstimateTotalsCalculator.new(estimate).call.burdened_total` (the client-facing sell price after markup, PM supervision, and job-level costs), `mode: :commercial`, `status: :draft`, `current_step: "opening"`.
2. Creates `ProposalClarification` records for R11 standard clarifications.
3. Creates `ProposalExclusion` records for R14 standard exclusions.
4. Detects alternate line items using `ALTERNATE_PREFIXES` and creates `ProposalAlternate` records, setting `display_cost` on a gross/burdened basis (OQ-E resolved): `line_item_results[line_item.id][:non_burdened_total] * burden_multiplier`, rounded to 2 decimals. This is consistent with `total_amount` using `burdened_total`. Job-level fixed costs are not attributable to a single alternate line and are therefore excluded.
5. Queries `estimate.line_items.where.not(room: [nil, ""]).pluck(:room).uniq` to get distinct room name strings (SPEC-025 stores room as a plain string column on `line_items`; there is no `rooms` table). Blank/empty room strings are skipped, since `room_name` is presence-validated and a blank string would create an invalid `ProposalInclusion`. For each unique room name, creates one `ProposalInclusion` with `room_name` set to the string and `bullet_points` blank. If no line items have a non-blank `room`, the inclusions list starts empty.
6. Wraps all inserts in a transaction.
7. Returns the saved `Proposal` or raises `ActiveRecord::RecordInvalid`.

#### `Proposals::PdfRenderService`

File: `app/services/proposals/pdf_render_service.rb`

Constructor: `initialize(proposal:)`

`.call` — builds and returns a `Prawn::Document` binary string:
1. Loads proposal with all associations preloaded.
2. Branches on `proposal.mode` to select the commercial or residential layout.
3. Commercial layout: letterhead block, date, salutation, opening paragraph (R17), specifications section (if `include_specifications`), inclusions (room by room, embedding each room's photos — via the `:pdf` resized variant — when present), clarifications list, alternates table, exclusions list.
4. Residential layout: description block, room-by-room pricing table, alternates table, payment terms.
5. Uses `ProposalHelper#amount_in_words` to convert `total_amount` to English words (R18).
6. Returns the PDF binary string to the caller; does not write to disk.

#### `Proposals::EmailDeliveryService`

File: `app/services/proposals/email_delivery_service.rb`

Constructor: `initialize(proposal:, recipient_email:)`

`.call` — validates `recipient_email` format using `URI::MailTo::EMAIL_REGEXP`; raises `ArgumentError` if the address is blank, fails the regexp, or contains `\n`, `\r`, or `;` characters (email header injection guard). Validation occurs before any mailer call. On valid email: calls `PdfRenderService.new(proposal: @proposal).call` to get the PDF binary, then calls `ProposalMailer.proposal_email(proposal: @proposal, recipient_email: @recipient_email, pdf_binary: pdf).deliver_now`. Returns a result struct `{ success: Boolean, error: String? }`.

#### `Proposals::AlternateDetectorService`

File: `app/services/proposals/alternate_detector_service.rb`

Constructor: `initialize(estimate:)`

`.call` — queries `estimate.line_items` where `description ILIKE 'ALT%' OR description ILIKE 'Alternate%' OR description ILIKE 'Alt.%'` (or filters in Ruby using `Proposal::ALTERNATE_PREFIXES`). Returns an array of matching `LineItem` records.

### Controllers / Routes

#### Route structure

```ruby
resources :estimates do
  resource :proposal, only: [:new, :create, :show] do
    resources :steps, only: [:show, :update], controller: "proposals/steps"
    get  :pdf,   on: :member
    post :email, on: :member
  end
end
```

Alternatively, use named step routes (explicit, no `wicked` gem required):

```ruby
resources :estimates do
  resource :proposal, only: [:new, :create, :show] do
    scope module: :proposals do
      get  "steps/:step", to: "steps#show", as: :step
      patch "steps/:step", to: "steps#update"
    end
    get  :pdf,   on: :member
    post :email, on: :member
  end
end
```

The `:step` segment accepts: `opening`, `specifications`, `inclusions`, `clarifications`, `alternates`, `exclusions`, `review`.

#### `ProposalsController`

File: `app/controllers/proposals_controller.rb`

Actions (alphabetical per architecture rules):
- `create` — calls `Proposals::BuildService.new(estimate: @estimate).call`. If proposal already exists, redirects to the existing proposal's current step (AC-2). On success, redirects to opening step.
- `new` — redirects to `create` immediately (no intermediate form; creation is instantaneous).
- `show` — redirects to the proposal's `current_step` route.
- `pdf` — calls `Proposals::PdfRenderService.new(proposal: @proposal).call`. Sends result with `send_data`, `content_type: "application/pdf"`, `disposition: :attachment`, filename: `"proposal-#{@estimate.estimate_number}.pdf"`. Rescues `StandardError`, redirects to review step with error flash (E8).
- `email` — instantiates `Proposals::EmailDeliveryService`. On success, redirects to review step with flash notice. On validation failure (missing email), re-renders review step with error.

#### `Proposals::StepsController`

File: `app/controllers/proposals/steps_controller.rb`

Actions:
- `show` — loads the proposal and renders the view for the requested step. If the step is ahead of `current_step` and prior steps are incomplete, redirects to the earliest incomplete step (E7).
- `update` — validates and saves the step's fields. On success, advances `current_step` and redirects to next step. On failure, re-renders the step with errors.

Step order constant: `STEPS = %w[opening specifications inclusions clarifications alternates exclusions review].freeze`

Step skip logic: if `proposal.residential?` and step == `"specifications"`, skip forward to `"inclusions"`.

#### `ProposalMailer`

File: `app/mailers/proposal_mailer.rb`

One action: `proposal_email(proposal:, recipient_email:, pdf_binary:)` — attaches the binary as `proposal.pdf` with MIME type `application/pdf`, sets subject from i18n key, sends to `recipient_email`.

### Views

All views live under `app/views/proposals/` and `app/views/proposals/steps/`. Use the authenticated `application.html.erb` layout.

A shared `_step_indicator.html.erb` partial renders the step breadcrumb and is included in all step layouts (AC-28, R24).

Each step has a dedicated partial: `_opening.html.erb`, `_specifications.html.erb`, `_inclusions.html.erb`, `_clarifications.html.erb`, `_alternates.html.erb`, `_exclusions.html.erb`, `_review.html.erb`.

Dynamic list rows (clarifications, exclusions, inclusions) use Stimulus controllers to support add/remove without a page reload. Use Turbo Frames for the add-row interaction.

Photo upload: use a standard Rails `file_field` (multiple) on the inclusion form, with `accept="image/jpeg,image/png"` and a visible "JPEG or PNG" hint so the estimator sees the accepted formats at upload time. Stimulus controller previews the selected images before save.

### i18n

All keys under `proposals.*` in `config/locales/en.yml`. Key examples:

```yaml
proposals:
  create:
    notice: "Proposal created."
    already_exists: "A proposal already exists for this estimate."
  steps:
    opening:
      title: "Opening"
      contact_label: "Client contact"
      job_name_label: "Job name"
      plan_date_label: "Plan date"
      addendum_list_label: "Addenda"
      total_amount_label: "Total amount"
      mode_label: "Proposal type"
      payment_terms_label: "Payment terms"
    specifications:
      title: "Specifications"
      include_toggle_label: "Include specifications section"
    inclusions:
      title: "Specific Inclusions"
      add_room: "Add room"
      remove: "Remove"
    clarifications:
      title: "Design Clarifications"
      add_item: "Add clarification"
    alternates:
      title: "Alternates"
      no_alternates: "No alternates detected in this estimate."
    exclusions:
      title: "Exclusions"
      add_item: "Add exclusion"
    review:
      title: "Review and Export"
      download_pdf: "Download PDF"
      send_email: "Send Email"
      email_label: "Recipient email address"
      email_notice: "Proposal sent to %{email}."
      email_error: "Failed to send email."
      pdf_error: "PDF generation failed. Please try again."
  step_indicator:
    step: "Step %{number}"
  future_step_notice: "Please complete earlier steps before skipping ahead."
```

### Background Processing

None in v1. PDF generation and email delivery are synchronous. At realistic proposal sizes this is acceptable. If PDF generation proves slow (e.g., many large photos), a background job wrapper can be added without changing the service interface.

---

## Test Requirements

### Unit Tests

**`Proposal` model (`spec/models/proposal_spec.rb`):**
- A proposal with valid attributes is valid.
- Two proposals for the same estimate are invalid (uniqueness on `estimate_id`).
- `mode` must be `commercial` or `residential`.
- A proposal without an `estimate_id` is invalid.

**`ProposalInclusion` model (`spec/models/proposal_inclusion_spec.rb`):**
- A valid JPEG attachment is valid.
- A valid PNG attachment is valid.
- Multiple photos can be attached to one inclusion.
- A non-image file attachment (e.g., PDF) is invalid.
- A WebP attachment is invalid (Prawn cannot embed WebP).
- A GIF attachment is invalid.
- When several photos are attached and any one is not JPEG/PNG, the record is invalid.
- `room_name` is required.

**`Proposals::BuildService` (`spec/services/proposals/build_service_spec.rb`):**
- Creates a proposal with `mode: commercial` and `status: draft` by default.
- Seeds two standard design clarifications (R11).
- Seeds thirteen standard exclusions (R14).
- Given an estimate with alternate line items (descriptions starting with `ALT`, `Alternate`, `Alt.`), creates corresponding `ProposalAlternate` records.
- Given an estimate with no alternate line items, creates no `ProposalAlternate` records.
- If SPEC-025 rooms are present, creates `ProposalInclusion` records for each room.
- Sets `job_name` from `estimate.title` and `total_amount` from estimate grand total.
- Wraps creation in a transaction; if any child insert fails, no records are persisted.

**`Proposals::AlternateDetectorService` (`spec/services/proposals/alternate_detector_service_spec.rb`):**
- Returns line items whose description begins with `ALT` (case-insensitive).
- Returns line items whose description begins with `Alternate`.
- Returns line items whose description begins with `Alt.`.
- Does not return line items whose description contains `ALT` as a non-prefix substring (e.g., `"Base Cabinet ALT Finish"`).
- Returns an empty array when the estimate has no matching line items.

**`Proposals::PdfRenderService` (`spec/services/proposals/pdf_render_service_spec.rb`):**
- Returns a non-empty binary string.
- The returned binary begins with `%PDF` (valid PDF header).
- Commercial mode: does not raise for a fully populated proposal.
- Residential mode: does not raise for a fully populated proposal.
- A proposal with no inclusions does not raise.
- A proposal with no clarifications does not raise.

**`ProposalHelper#amount_in_words` (`spec/helpers/proposal_helper_spec.rb`):**
- `123_000.00` → `"One Hundred Twenty-Three Thousand Dollars"`
- `1_000.50` → `"One Thousand Dollars and 50/100"` (or equivalent format — document the chosen format in the spec comment).
- `0.00` → `"Zero Dollars"`.

### Request / Integration Tests

**`ProposalsController` (`spec/requests/proposals_spec.rb`):**
- `POST /estimates/:id/proposals` (authenticated) — creates a proposal, redirects to opening step.
- `POST /estimates/:id/proposals` when a proposal already exists — redirects to existing proposal's current step; no duplicate created.
- `POST /estimates/:id/proposals` (unauthenticated) — redirects to login.
- `GET /estimates/:id/proposals/:id/pdf` (authenticated, all steps complete) — returns 200 with `Content-Type: application/pdf`.
- `GET /estimates/:id/proposals/:id/pdf` (unauthenticated) — redirects to login.
- `POST /estimates/:id/proposals/:id/email` with a valid email — sends one email; redirects to review step.
- `POST /estimates/:id/proposals/:id/email` with a blank email — returns 422 and does not send email.

**`Proposals::StepsController` (`spec/requests/proposals/steps_spec.rb`):**
- `PATCH /estimates/:id/proposals/:id/steps/opening` with valid params — saves and redirects to specifications step (commercial) or inclusions step (residential).
- `PATCH /estimates/:id/proposals/:id/steps/opening` with missing contact — returns 422.
- `GET /estimates/:id/proposals/:id/steps/alternates` when step 3 (inclusions) is incomplete — redirects to inclusions step.
- `PATCH /estimates/:id/proposals/:id/steps/clarifications` — saves clarifications and advances.

### System / End-to-End Tests

File: `spec/system/proposal_wizard_spec.rb`

Test 1 — Happy path, commercial:
1. Estimator is on an estimate page. Clicks "Create Proposal."
2. Opening step: selects a contact, job name, plan date, addendum list, total amount. Clicks "Save and continue."
3. Specifications step: toggles on "Include specifications section." Enters `064023 - Interior Architectural Woodwork`. Saves.
4. Inclusions step: sees two pre-populated rooms. Adds a bullet point to the first room. Saves.
5. Clarifications step: standard clarifications pre-populated. Adds a custom clarification. Saves.
6. Alternates step: one alternate detected. Accepts the price. Saves.
7. Exclusions step: standard exclusions pre-populated. Removes one. Saves.
8. Review step: sees "Download PDF" button. Clicks it. Browser downloads a file with `Content-Type: application/pdf`.

Test 2 — Residential mode:
1. Estimator creates a proposal, selects residential mode on opening step.
2. Specifications step is skipped; estimator lands directly on inclusions.
3. PDF download succeeds without raising.

Test 3 — Resume after navigation away:
1. Estimator completes opening step and navigates to the estimate page.
2. Clicks "Edit Proposal." Is taken to specifications step (the next incomplete step).
3. Previously entered opening data is preserved.

Test 4 — Future step redirect:
1. Estimator creates a proposal (opening step complete; steps 2-7 incomplete).
2. Estimator manually navigates to the exclusions step URL.
3. Is redirected to the specifications step with a flash notice.

Test 5 — Duplicate proposal guard:
1. Estimate already has a proposal.
2. Estimator clicks "Create Proposal" on the estimate page.
3. Is redirected to the existing proposal's current step; no new proposal record is created.

---

## Acceptance Tests

AT1
Given an authenticated estimator on the estimate show page and no proposal exists
When they click "Create Proposal"
Then a `Proposal` record is created with `mode: commercial` and `status: draft` and the browser redirects to the opening step URL
Covers: R1, R2, AC-1

AT2
Given a proposal already exists for the estimate
When an authenticated estimator requests `POST /estimates/:estimate_id/proposals`
Then no additional proposal is created and the response redirects to the existing proposal's current step
Covers: R1, E10, AC-2

AT3
Given the opening step with the estimate's primary contact pre-selected
When the estimator submits the opening form with all required fields filled
Then the proposal record is updated with the submitted values and `current_step` advances to `specifications`
Covers: R3, R5, R6, AC-3, AC-4

AT4
Given the opening step
When the form is submitted without selecting a contact
Then the response is 422 and a validation error is shown on the contact field
Covers: R5, AC-5

AT5
Given commercial mode and the specifications step
When the estimator enables the include toggle and enters one specification and saves
Then a `ProposalSpecification` record is created and `current_step` advances to `inclusions`
Covers: R7, AC-6

AT6
Given residential mode
When the proposal's opening step is saved
Then navigating to `/steps/specifications` redirects the estimator to `/steps/inclusions`
Covers: R7, AC-8

AT7
Given rooms exist from SPEC-025 on the estimate
When the inclusions step is first loaded
Then each room appears as a pre-populated inclusion row
Covers: R8, AC-9

AT8
Given the inclusions step with a room inclusion row
When the estimator attaches a non-JPEG/PNG file (e.g., a WebP image) and submits
Then a validation error is shown, no file is stored, and `current_step` is not advanced
Covers: R9, E5, E6, AC-12

AT9
Given the clarifications step on a new proposal
When the page renders
Then exactly two pre-populated clarification rows matching R11 are visible
Covers: R10, R11, AC-13

AT10
Given an estimate with a line item whose description starts with "ALT-1 Painted Finish"
When the alternates step loads
Then that line item appears as an alternate row with its description and cost
Covers: R12, AC-16

AT11
Given the alternates step with a detected alternate
When the estimator edits the display cost and saves
Then `proposal_alternates.display_cost` stores the edited value
Covers: R12, AC-17

AT12
Given the exclusions step on a new proposal
When the page renders
Then thirteen pre-populated exclusion rows matching R14 are visible
Covers: R13, R14, AC-19

AT13
Given all seven steps are complete
When the estimator visits the review step and clicks "Download PDF"
Then the response has `Content-Type: application/pdf` and a non-empty body starting with `%PDF`
Covers: R16, AC-22

AT14
Given commercial mode and a complete proposal
When the PDF is generated
Then the PDF binary contains the contact's first name, the job name, the plan date, and the total amount in numeric and English word forms
Covers: R17, R18, AC-23

AT15
Given the review step
When the estimator submits the email form without entering a recipient address
Then the response is 422 and no email is delivered
Covers: E9, AC-26

AT16
Given the estimator is on step 2 and steps 3-7 are incomplete
When the estimator navigates directly to the step 6 URL
Then the response redirects to step 2 with a flash notice
Covers: E7, AC-30

AT17
Given an unauthenticated request to any proposal route
When the request is processed
Then the response redirects to the login page
Covers: R21, AC-31

---

## Implementation Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-27 | Use Prawn for PDF generation (no `wicked_pdf` / wkhtmltopdf binary) | Prawn is pure Ruby; no binary dependency on the server simplifies CI and Docker image. `wicked_pdf` requires a wkhtmltopdf binary which adds ~100 MB to the container image and complicates the CI Tailwind build step. |
| 2026-05-27 | No `wicked` wizard gem — use explicit step routing | The wicked gem adds indirection. Explicit step routes (`GET /steps/:step`) are clearer, easier to test, and give direct control over skip logic without gem DSL. |
| 2026-05-27 | Proposal child records use `acts_as_list` for ordering | Consistent with `line_items` ordering pattern already in the project. Avoids bespoke position logic. |
| 2026-05-27 | Alternate prefix detection uses a Ruby constant regex, not DB query | At estimate sizes in scope (hundreds of line items), filtering in Ruby after a single query is fast enough. A DB-level filter would require a case-insensitive pattern index that adds schema complexity with minimal gain. |
| 2026-05-27 | One proposal per estimate (unique constraint) | Simplifies the UX ("Edit Proposal" vs "Create Proposal"), avoids version confusion, and matches the estimator workflow described by Blake. Versioning is post-MVP. |

---

## Open Questions

| OQ | Question | Status |
|----|----------|--------|
| OQ-A | Does the PDF need a company letterhead image (logo)? If so, how will it be stored (config file, database, ActiveStorage)? | **Open.** Assume text-only letterhead for v1; add image logo as a follow-up. |
| OQ-B | What is the exact company address block to embed in the PDF header? | **Open.** Developer should confirm with Blake / TrimArt before implementing the PDF layout. Use a placeholder constant (`Company::ADDRESS`) in the service, set via Rails credentials or environment variable. |
| OQ-C | Does SPEC-025 (room tracking from CSV import) exist and what is the room model structure? | **Resolved.** SPEC-025 is not yet written but the confirmed data model is: `room` is a plain string column on `line_items` (no separate `rooms` table). `BuildService` seeds inclusions via `estimate.line_items.where.not(room: [nil, ""]).pluck(:room).uniq` (blank/empty room strings are skipped). R8 and `BuildService` step 5 have been updated accordingly. |
| OQ-D | Should `payment_terms` (residential mode) have a default value pre-populated? | **Open.** Confirm with Blake. `BuildService` (PR 2) does NOT seed `payment_terms` — it is entered on the residential opening step. If a default is still desired later, add to `BuildService` seed logic similar to clarifications/exclusions. |
| OQ-E | Should alternate costs shown in the proposal be net (before markup) or gross (after profit/overhead)? | **Resolved.** Gross/burdened: `display_cost = line item non_burdened_total × burden_multiplier` (rounded to 2 decimals). Consistent with `total_amount` using `burdened_total`; job-level fixed costs are excluded because they are not attributable to a single alternate line. Implemented in `Proposals::BuildService` (PR 2). |

---

## Dependencies

- SPEC-021 (CSV Import for Estimate Line Items) — done. Alternate line items arrive via CSV import.
- SPEC-022 (Material Alias Auto-Population) — done. No direct dependency but confirms line item description patterns used for alternate detection.
- SPEC-025 (Room Tracking / CSV Import Rooms) — **not yet written.** Room data is a plain string column `room` on `line_items` (confirmed). `BuildService` seeds inclusions from `estimate.line_items.where.not(room: [nil, ""]).pluck(:room).uniq` (blank/empty room strings are skipped). SPEC-025 must add the `room` column to `line_items` before the inclusions seeding step will produce any rows. The feature can be developed in parallel: if the column does not yet exist, `BuildService` will produce an empty inclusions list (the `where.not(room: [nil, ""])` query will return zero rows), which is a safe degraded state.

---

## Out of Scope

- Google Drive integration.
- In-app PDF viewer / preview (download-only in v1).
- Proposal version history or revision tracking.
- Custom branding per client.
- Client-facing portal or shareable proposal link.
- Digital signatures.
- Change-order workflow.
- Batch proposal export.
- Proposal templates reusable across estimates.
- Email template customization per client.
- Localization of the PDF output (English only).

---

## Change Log

| Date | Change | Affected IDs | Rationale |
|------|--------|-------------|-----------|
| 2026-05-27 | Initial spec authored | All | New feature from Blake user feedback session |
| 2026-05-27 | R2: mode unlocked on step 1 until `complete`; R25 added (status transition on finalise); AC-1, AC-34 updated | R2, R25, AC-1, AC-34 | R2/R5 contradiction resolved — mode should be editable on revisit until proposal is complete |
| 2026-05-27 | R6, BuildService step 1: replace generic "grand total" with `EstimateTotalsCalculator.new(estimate).call.burdened_total` | R6, BuildService | Actual calculator method confirmed by reading `app/services/estimate_totals_calculator.rb` |
| 2026-05-27 | R8, BuildService step 5, OQ-C, Dependencies: replace `estimate.rooms` association with `line_items.pluck(:room).uniq` string query | R8, OQ-C, Dependencies | No `rooms` table exists; SPEC-025 stores room as plain string column on `line_items` |
| 2026-05-27 | Child table FKs: added `on_delete: :cascade` to `proposal_inclusions`, `proposal_clarifications`, `proposal_exclusions`, `proposal_alternates`, `proposal_specifications` | Data / Models | DB-level cascade required; `dependent: :destroy` alone is insufficient for DB safety |
| 2026-05-27 | `display_cost` on `proposal_alternates`: changed from nullable to NOT NULL; populated by `BuildService` | Data / Models, AC-17 | Always pre-populated so never nil at PDF render time |
| 2026-05-27 | ActiveStorage install made an explicit required migration task; AC-33 added | Technical Scope, AC-33 | `active_storage_*` tables absent from `schema.rb`; developer must run `active_storage:install` |
| 2026-05-27 | R18: `humanize` gem named and usage specified | R18 | Concrete gem required to implement `amount_in_words` helper |
| 2026-05-27 | R24: residential mode hides Specifications step from step indicator (steps numbered 1–6) | R24 | Step indicator behaviour for skipped steps must be explicit |
| 2026-05-27 | `EmailDeliveryService`: added email header injection validation (`URI::MailTo::EMAIL_REGEXP`, reject `\n`, `\r`, `;`) | EmailDeliveryService | Security hardening — prevent header injection via recipient field |
| 2026-06-02 | Status renamed `complete` → `sent`; locking removed; R2, R4, R6, R15, R25, AC-34–38 revised; three "Refresh from estimate" controls added (total amount, rooms sync, alternates sync) | R2, R4, R6, R15, R25, AC-34–38, Data/Models | Brainstorm session: proposal must remain editable after delivery so estimator can adjust for client feedback (e.g., remove a room, recalculate total) without re-entering all wizard content |
| 2026-06-04 | PR 49 review — photo validation: JPEG/PNG only (Prawn limitation), removed byte-size cap in favour of a resized `:pdf` variant (~2000px longest edge), multiple photos per room (`has_many_attached :photos`), upload UI must show accepted formats (`accept` + visible hint); R8, R9, E5, E6, AC-9, AC-11, AC-12, AT8, Test Requirements updated | R9, Data/Models, R8, E5, E6, AC-9, AC-11, AC-12, AT8 | Product-owner review on PR #49: Prawn only embeds JPEG/PNG so WebP must be rejected; hard 8 MB cap replaced with auto-resize for PDF embedding; rooms can have multiple photos |
| 2026-06-04 | PR 2 (services): `Proposals::BuildService` + `Proposals::AlternateDetectorService` implemented; OQ-E resolved (alternate cost = gross/burdened, `non_burdened_total × burden_multiplier`); OQ-D noted as not seeded by BuildService | Services, OQ-E, OQ-D | Service layer for the proposal wizard; alternate cost basis confirmed gross/burdened consistent with `total_amount` |
