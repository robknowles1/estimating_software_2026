# Spec: CRM Expansion on Clients

**ID:** SPEC-027
**Status:** done
**Priority:** medium
**Created:** 2026-05-27
**Author:** spec-agent

---

## Goal

Expand the existing Clients section into a lightweight CRM so that the estimator can track GC (general contractor) relationships. Blake (estimator at TrimArt) sends approximately $29M/month in bids and needs to track which estimates were bid to which GCs, maintain per-GC contacts with clear roles, and keep a timestamped log of conversations and follow-ups on each client record.

---

## Non Goals

- File/document attachments per client — ActiveStorage is configured in Rails environments but no `active_storage_*` tables exist in the schema; this is deferred to a future spec.
- Estimate ownership / multi-user access control — tracked separately in memory as a pre-production debt item.
- Client-to-client relationships (referral chains, parent companies).
- Email sending or integration with an email provider.
- CRM pipeline stages or deal-win/loss tracking.
- Search or filtering across client notes (full-text search is out of scope for this spec).
- Exporting client or note data to CSV or PDF.

---

## Definitions

| Term | Definition |
|------|-----------|
| Client | A GC company the estimating shop bids work to; already modelled as the `clients` table. |
| Contact | A named individual at a GC company; already modelled as the `contacts` table. |
| Role | A short label describing how a contact is engaged (e.g., `"estimator"`, `"sales contact"`, `"project manager"`). Free-form string, not an enum. |
| Client Note | A timestamped, append-only log entry recording a conversation, follow-up, or observation about a client. Stored in the new `client_notes` table. |
| Estimates Panel | A read-only section on the client show page listing all estimates ever bid to that GC, drawn from the existing `has_many :estimates` association. |

---

## Interfaces

### Data inputs

| Source | Field | Notes |
|--------|-------|-------|
| Contact form | `role` | New optional free-form text field added to the existing new/edit contact form |
| Client show page | Client Note body | Inline Turbo Stream form; submit appends a new note to the timeline |
| Client show page | Client Note delete | Destroy action removes a note; guarded by a confirm dialog |

### Data outputs

| Surface | Content |
|---------|---------|
| Client show page — contacts table | Existing table gains a "Role" column displaying `contact.role` |
| Client show page — notes timeline | Chronological list of `ClientNote` records (newest first), each showing body text and formatted `created_at` |
| Client show page — estimates panel | Table of all estimates for the client: title, estimate number, status, job start date, total (if calculable from existing data) |

### Routes added

```
POST   /clients/:client_id/client_notes            client_notes#create
DELETE /clients/:client_id/client_notes/:id        client_notes#destroy
```

Nested under `:clients` in `config/routes.rb`:

```ruby
resources :clients do
  resources :contacts, ...  # existing
  resources :client_notes, only: [:create, :destroy]
end
```

---

## Rules

R1: The `contacts` table gains a `role` string column (nullable). A blank role is valid. No length enforcement at the database level; validate presence is not required.

R2: `ContactsController#contact_params` must permit the new `role` field. The contact new and edit forms must include a text input for `role`.

R3: The contacts table on the client show page must display a "Role" column. When `contact.role` is blank, display the shared i18n value `t("common.not_provided")` (consistent with the existing `title`, `email`, and `phone` columns).

R4: A new `client_notes` table stores notes belonging to a client: `client_id` (FK, not null), `body` (text, not null), `created_at`, `updated_at`. No `body` length cap at the database level.

R5: The `ClientNote` model belongs to `Client`. `body` must be present (validates presence). The association on `Client` is `has_many :client_notes, dependent: :destroy`, ordered newest-first by default: `order(created_at: :desc)`.

R6: `ClientNotesController` is nested under clients and exposes only `create` and `destroy` actions. It must inherit `require_login` from the `Authentication` concern (all controllers do). Both actions redirect to `client_path(@client)` on success. The controller is thin: no business logic beyond parameter extraction and record creation/deletion.

R7: On `create`, if `@client_note.save` fails (body blank), re-render the client show page with a 422 status and inline errors visible. The existing notes timeline and all other panels must still render correctly.

R8: On `destroy`, the note is deleted only if it belongs to the scoped client (scoped via `@client.client_notes.find(params[:id])`). A confirm dialog is shown before delete (`data: { turbo_confirm: t(".confirm_delete_note") }`).

R9: On successful note creation, `ClientNotesController#create` redirects to `client_path(@client)`. This is a standard redirect, consistent with all other controllers in this codebase. No Turbo Stream response is required.

R10: Notes are append-only; there is no edit action for `ClientNote`.

R11: The client show page must include an Estimates panel listing all estimates associated with the client (`@client.estimates`). The panel is read-only. Each row displays: estimate number, title, status, and job start date (nil renders as `t("common.not_provided")`). The panel links each estimate number/title to `edit_estimate_path(estimate)` so the estimator can jump directly to an estimate.

R12: The Estimates panel is empty-state-aware: when `@client.estimates.none?`, display a message indicating no estimates have been bid to this client yet (i18n key).

R13: `ClientsController#show` must preload data needed for all panels without N+1 queries: `@contacts` (already loaded), `@client_notes = @client.client_notes` (ordering provided by the association default scope — see `Client` model), and `@estimates = @client.estimates.order(updated_at: :desc)`.

R14: All user-facing strings introduced by this spec must use Rails I18n lazy lookup (`t(".key")` in views, shared keys for reused values). No hardcoded English strings in views or controllers.

---

## Edge Cases

E1: A client with no notes — the notes timeline renders the inline new-note form only, with a prompt indicating no notes yet (i18n key `t(".no_notes")`).

E2: A note body submitted as blank or whitespace-only — the `ClientNote` presence validation rejects it; the form re-renders with an error message; no record is created.

E3: A `destroy` request for a note that does not belong to the scoped client (e.g., manipulated URL) — `@client.client_notes.find(params[:id])` raises `ActiveRecord::RecordNotFound`; Rails renders a 404.

E4: `Client#destroy` is blocked if the client has estimates (existing `dependent: :restrict_with_error`). Client notes are cascade-deleted when a client is deleted (`dependent: :destroy`), so a client with only notes (no estimates) can be deleted cleanly.

E5: A contact's `role` field is updated to blank after previously having a value — the update must succeed (role is optional); the contacts table displays `t("common.not_provided")`.

E6: The Estimates panel on a client with many estimates is not paginated in this spec. Pagination of the estimates panel is out of scope; all estimates are rendered.

---

## Acceptance Criteria

AC-1: The `contacts` table has a `role` string column. The contact new and edit forms include a "Role" text input. Saving a contact with a role value persists it. Saving with a blank role is valid.

AC-2: The contacts table on the client show page includes a "Role" column. When `contact.role` is blank, the cell displays the shared "not provided" value. When `contact.role` is set, the cell displays the role value.

AC-3: A `client_notes` table exists with `client_id` (FK, not null), `body` (text, not null), `created_at`, and `updated_at` columns. `client_id` has a foreign key constraint referencing `clients`.

AC-4: The `ClientNote` model validates presence of `body`. A note with a blank body fails validation and is not saved.

AC-5: The client show page includes a Notes timeline section. An inline form at the top (or bottom) of the section allows the estimator to type a note body and submit. On successful submit, the new note appears in the timeline ordered newest-first.

AC-6: Each note in the timeline displays: the body text and the formatted `created_at` timestamp. A delete button is present on each note, guarded by a confirm dialog.

AC-7: Deleting a note removes it from the timeline and does not affect the client record or any other notes.

AC-8: Submitting a blank note body shows an inline validation error. The timeline and all other client show panels remain visible.

AC-9: The client show page includes an Estimates panel. When estimates exist for the client, each row shows: estimate number, title, status, and job start date. Each row links to the estimate edit page. When no estimates exist, an empty-state message is shown.

AC-10: `ClientsController#show` loads contacts, client notes, and estimates without N+1 queries (verifiable by checking that no more than one query per association is issued).

AC-11: Unauthenticated requests to `POST /clients/:client_id/client_notes` and `DELETE /clients/:client_id/client_notes/:id` redirect to the login page. No records are created or destroyed.

AC-12: All strings rendered in views introduced by this spec use i18n keys. No hardcoded English strings appear in ERB templates.

---

## Acceptance Tests

AT1
Given an authenticated estimator on the contact edit form for a contact with no role set
When the estimator enters "estimator" in the Role field and saves
Then the contact record has `role = "estimator"` persisted
And the contacts table on the client show page displays "estimator" in the Role column
Covers: R1, R2, R3, AC-1, AC-2

AT2
Given a contact with `role = "estimator"`
When the estimator edits the contact and clears the Role field and saves
Then the update succeeds
And the contacts table displays the "not provided" placeholder in the Role column
Covers: R1, R3, E5, AC-2

AT3
Given an authenticated estimator on the client show page for a client with no notes
When the estimator types "Called Blake re: bid deadline" into the note form and submits
Then a new `ClientNote` record is created with that body and a `created_at` timestamp
And the note appears in the notes timeline on the client show page
Covers: R4, R5, R6, R9, AC-5, AC-6

AT4
Given an authenticated estimator on the client show page
When the estimator submits the note form with a blank body
Then the form re-renders with a validation error
And no `ClientNote` record is created
And the contacts table and estimates panel are still visible
Covers: R5, R7, E2, AC-4, AC-8

AT5
Given a client with two notes: note A (created earlier) and note B (created later)
When the estimator views the client show page
Then note B appears above note A in the timeline (newest-first order)
Covers: R5, AC-5

AT6
Given an authenticated estimator viewing a client note in the timeline
When the estimator clicks the delete button and confirms the dialog
Then the `ClientNote` record is destroyed
And the timeline no longer shows that note
And the client record still exists
Covers: R8, R10, AC-7

AT7
Given a client with two estimates: "Big Job" (draft) and "Small Job" (submitted)
When the estimator views the client show page
Then both estimates appear in the Estimates panel
And each row shows the estimate number, title, status, and job start date
And clicking an estimate title navigates to that estimate's edit page
Covers: R11, R13, AC-9

AT8
Given a client with no estimates
When the estimator views the client show page
Then the Estimates panel shows the empty-state message
And no estimate rows are rendered
Covers: R12, AC-9

AT9
Given a URL for a note that belongs to a different client
When an authenticated estimator sends a DELETE request to that URL with the wrong client_id scope
Then the response is 404
And no record is deleted
Covers: E3, R8

AT10
Given an unauthenticated user
When a POST request is sent to `/clients/1/client_notes`
Then the response redirects to the login page
And no `ClientNote` record is created
Covers: R6, AC-11

---

## Technical Scope

### Data / Models

#### Migration 1 — add `role` to `contacts`

```
add_column :contacts, :role, :string
```

No index required. No default. Nullable.

#### Migration 2 — create `client_notes`

```
create_table :client_notes do |t|
  t.references :client, null: false, foreign_key: true
  t.text :body, null: false
  t.timestamps
end
```

Add index on `client_id` (created automatically by `t.references`).

#### `Contact` model update

Permit `role` in `ContactsController#contact_params`. No model-level validation change needed.

#### `ClientNote` model

```ruby
class ClientNote < ApplicationRecord
  belongs_to :client

  validates :body, presence: true
end
```

Default ordering on the association is set in `Client` via the association declaration:
```ruby
has_many :client_notes, -> { order(created_at: :desc) }, dependent: :destroy
```

#### `Client` model update

Add:
```ruby
has_many :client_notes, -> { order(created_at: :desc) }, dependent: :destroy
```

The existing `has_many :estimates, dependent: :restrict_with_error` is unchanged.

### Controllers

#### `ContactsController` update

Add `role` to the permitted params list:
```ruby
params.require(:contact).permit(:first_name, :last_name, :title, :email, :phone, :is_primary, :notes, :role)
```

#### New `ClientNotesController`

Thin controller, nested under clients, `create` and `destroy` only. Actions ordered alphabetically per architecture rules (`create`, `destroy`). Uses i18n `t(".notice")` for flash.

#### `ClientsController#show` update

Load the two new instance variables for the view:
```ruby
def show
  @contacts     = @client.contacts.alphabetical
  @client_notes = @client.client_notes   # association default scope: order(created_at: :desc)
  @estimates    = @client.estimates.order(updated_at: :desc)
end
```

### Views

#### Contact form (`app/views/contacts/_form.html.erb`)

Add a text input for `role` below the existing `title` field. Label uses i18n key `Contact.human_attribute_name(:role)` or `t(".role_label")`.

#### Client show page (`app/views/clients/show.html.erb`)

**Implementation note — avoiding a dual-"Notes" UX trap:**
The `clients` table already has a `notes` text column, and the existing client show page renders it under a "Notes" heading (i18n key `clients.show.notes_heading`). This spec introduces a separate `ClientNote` timeline. To prevent two unlabelled "Notes" sections appearing on the same page:

- The existing `clients.notes` panel label **must be renamed** from `"Notes"` to `"General Notes"`. Update the i18n key `clients.show.notes_heading` value to `"General Notes"` (or introduce the new key `clients.show.general_notes_label` and reference that key in the view instead).
- The new `ClientNote` timeline section must be labelled `"Activity / Notes"` (i18n key `clients.show.notes_timeline_heading`). Do **not** label it simply `"Notes"`.

These two sections are distinct: `clients.notes` is an unstructured free-text field edited via the client edit form; the `ClientNote` timeline is an append-only log managed via inline creation/deletion.

Add three new sections below the existing contacts table:

1. **Role column in contacts table** — add `<th>` for Role header and `<td>` for `contact.role.presence || t("common.not_provided")` in each row.

2. **Notes timeline section** — card with:
   - Inline new-note form (textarea + submit button)
   - Chronological list of `@client_notes`, each displaying body and timestamp
   - Delete button per note with confirm dialog

3. **Estimates panel** — card with:
   - Table listing `@estimates` rows: estimate number (linked to `edit_estimate_path`), title, status badge, job start date
   - Empty state when `@estimates.none?`

### i18n keys to add (`config/locales/en.yml`)

All new keys are nested under `clients.show` or `contacts`:

```
clients:
  show:
    general_notes_label: "General Notes"      # renames existing clients.notes panel (was "Notes")
    notes_timeline_heading: "Activity / Notes" # new ClientNote timeline section — distinct from general_notes_label
    add_note_placeholder: "Type a note..."
    add_note_button: "Add note"
    no_notes: "No notes yet."
    confirm_delete_note: "Delete this note?"
    estimates_heading: "Estimates"
    no_estimates: "No estimates have been bid to this client yet."
    role_header: "Role"        # new contacts table column header
  client_notes:
    create:
      notice: "Note added."
    destroy:
      notice: "Note deleted."
contacts:
  role_label: "Role"          # form label
```

---

## Implementation Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-27 | `client_notes` is a separate table, not a JSONB column on `clients` | Enables indexed lookups, proper cascade deletes, and future filtering by date range or keyword without schema changes |
| 2026-05-27 | Notes are append-only (no edit action) | Preserves audit trail integrity; Blake's use case is a conversation log, not a document editor |
| 2026-05-27 | `role` on contacts is free-form string, not an enum | The set of roles in a millwork shop varies by shop; imposing an enum now would require migrations for every new role label |
| 2026-05-27 | Attachments deferred (no `active_storage_*` tables in schema) | Confirmed absent from schema; configuring ActiveStorage requires migrations and storage backend decision; deferred to separate spec |
| 2026-05-27 | Estimates panel uses `@client.estimates` ordered by `updated_at: :desc` | Most recently worked-on estimate is most relevant; no new query objects needed for this read |
| 2026-05-27 | Standard redirect chosen for `ClientNotesController#create` | Consistent with app-wide pattern of redirect-after-POST used by all other controllers; no Turbo Stream response required |

---

## Test Requirements

### Model specs

**`Contact` model (`spec/models/contact_spec.rb` — additions):**
- A contact with a role value is valid.
- A contact with a blank role is valid.
- Saving a role value persists it on the record.

**`ClientNote` model (`spec/models/client_note_spec.rb` — new file):**
- A client note with a body is valid.
- A client note with a blank body is invalid with an error on `body`.
- `ClientNote` belongs to a `Client`.
- Destroying a `Client` cascade-destroys its `ClientNote` records.
- `ClientNote` records for a client are returned newest-first by the default association order.

### Request specs

**`ContactsController` (`spec/requests/contacts_spec.rb` — additions):**
- `POST /clients/:client_id/contacts` with a `role` param — creates the contact with the role value.
- `PATCH /clients/:client_id/contacts/:id` with a blank `role` — updates successfully (role is optional).

**`ClientNotesController` (`spec/requests/client_notes_spec.rb` — new file):**
- `POST /clients/:client_id/client_notes` with a valid body — creates the note, redirects to `client_path`.
- `POST /clients/:client_id/client_notes` with a blank body — returns 422; no record created.
- `DELETE /clients/:client_id/client_notes/:id` — destroys the note, redirects to `client_path`.
- `DELETE /clients/:client_id/client_notes/:id` where note belongs to a different client — returns 404.
- `POST /clients/:client_id/client_notes` unauthenticated — redirects to login.
- `DELETE /clients/:client_id/client_notes/:id` unauthenticated — redirects to login.

**`ClientsController` (`spec/requests/clients_spec.rb` — additions):**
- `GET /clients/:id` — response includes the estimates panel and notes timeline without N+1 queries.

### System specs

**`spec/system/client_crm_spec.rb` — new file:**

1. Estimator adds a role to a contact: visits contact edit form, fills in role, saves, sees the role in the contacts table on the client show page.
2. Estimator adds a note: visits client show page, types a note, submits, sees the note appear in the timeline with a timestamp.
3. Estimator submits a blank note: sees the inline validation error; no note is added to the timeline.
4. Estimator deletes a note: clicks delete, confirms, note disappears from the timeline.
5. Estimator sees estimates panel: client with two estimates shows both; each links to the estimate edit page. Client with no estimates shows empty-state message.

---

## Proposed Task Breakdown

| Task | ACs covered | Estimated complexity |
|------|-------------|----------------------|
| T1: Migration — add `role` to contacts + `client_notes` table | AC-1, AC-3 | 1 point |
| T2: `ClientNote` model + `Client` model update (association + cascade) | AC-3, AC-4 | 1 point |
| T3: `ClientNotesController` + routes | AC-5, AC-7, AC-8, AC-11 | 2 points |
| T4: Contact form + contacts table Role column | AC-1, AC-2 | 1 point |
| T5: Notes timeline on client show page (form + list + delete) | AC-5, AC-6, AC-7, AC-8 | 3 points |
| T6: Estimates panel on client show page + `ClientsController#show` preloads | AC-9, AC-10 | 2 points |
| T7: i18n keys + model/request/system specs | AC-12 + all ACs via tests | 3 points |

Total: 13 points. All tasks are sized at 1-3 points; no single task exceeds 5 points.

---

## Dependencies

- SPEC-010 (Estimating Foundation) — `Client` model with `has_many :estimates` must exist. Status: done.
- No other specs are prerequisites; the `contacts` table and `ContactsController` are already wired.

---

## Change Log

| Date | Change | Affected IDs | Rationale |
|------|--------|-------------|-----------|
| 2026-05-27 | Initial spec authored | All | First version |
| 2026-05-27 | Added implementation note on `clients.notes` / `ClientNote` label collision; renamed existing panel label to "General Notes"; new timeline labelled "Activity / Notes"; added `general_notes_label` i18n key | Views section, i18n section, R14 | Review finding: without explicit guidance, developer would produce two unlabelled "Notes" sections |
| 2026-05-27 | R9 — replaced optionality with explicit redirect-after-POST requirement; removed Turbo Stream option | R9 | Review finding: ambiguous strategy; codebase pattern is always redirect-after-POST |
| 2026-05-27 | Fixed i18n key inconsistency: standardised on `confirm_delete_note` throughout; removed unreachable `client_notes.destroy.confirm_delete` key | R8, i18n section | Review finding: two keys with different names for the same string; `client_notes.destroy` scope is unreachable from a view partial in clients/show scope |
| 2026-05-27 | R13 / `ClientsController#show` — removed explicit `.order` call from `@client_notes` assignment; rely on association default scope | R13, Controllers section | Review finding: prose and code block were inconsistent; single source of ordering truth is the model |
| 2026-05-27 | Removed `scope :chronological` from `ClientNote` model definition | Technical Scope — Models | Review finding: no AC, AT, or rule referenced ascending order; dead code |
