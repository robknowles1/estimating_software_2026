# Spec: Phase 3 — Estimate Scaffold and Sections

**ID:** SPEC-005
**Status:** ready
**Priority:** high
**Created:** 2026-04-04
**Author:** pm-agent

---

## Summary

This phase creates the outer container for all estimate work: the Estimate record and its EstimateSections. An estimate belongs to a client, has a human-readable auto-generated estimate number, and carries a lifecycle status. Sections group line items and carry a default markup percentage. This phase delivers a demoable estimate shell — a user can create an estimate, add sections, reorder them, and change the estimate's status — before any line items are introduced.

## User Stories

- As an estimator, I want to start a new estimate by selecting a client and naming the job so that I can begin building the cost breakdown.
- As an estimator, I want to organize an estimate into named sections so that the document is structured and readable.
- As an estimator, I want to reorder sections so that the estimate reflects how I want to present the work.
- As an estimator, I want to change the status of an estimate so that I know where each job stands.
- As an estimator, I want a dashboard showing all estimates so that I can find and resume any job.

## Acceptance Criteria

1. Given a logged-in user, when they create a new estimate by selecting an existing client and providing a job title, the estimate is saved in "draft" status with an auto-generated estimate number.
2. Given a new estimate is created in 2026, the estimate number follows the format `EST-2026-NNNN` (zero-padded four-digit sequence, e.g., `EST-2026-0001`).
3. Given two estimates are created concurrently, each receives a unique estimate number. No two estimates share the same number.
4. Given a new estimate form with no client selected, when submitted, a validation error is shown and no record is created.
5. Given a new estimate form with no title, when submitted, a validation error is shown and no record is created.
6. Given a saved estimate, when an estimator adds a named section, the section appears in the estimate with a default position.
7. Given a section with no name, when the section form is submitted, a validation error is shown and no section is saved.
8. Given multiple sections on an estimate, when an estimator uses the up/down reorder controls, the sections reposition correctly and persist across page reloads.
9. Given a section with no line items, when an estimator deletes it, the section is removed.
10. Given a section that contains line items, when an estimator attempts to delete it, a confirmation dialog is shown before the cascade delete proceeds.
11. Given a saved estimate, when an estimator changes its status from the allowed values (draft, sent, approved, lost, archived), the new status is persisted and reflected in the dashboard.
12. Given the estimates dashboard, the list shows estimate number, client name, job title, status, and last-modified date for each estimate.
13. Given the estimates dashboard, when an estimator filters by a status, only estimates with that status are shown.
14. Given the estimates dashboard, when an estimator searches by client name or job title, only matching estimates are shown.

## Technical Scope

### Data / Models

- New model: `Estimate`
  - Columns: `id`, `client_id integer not null FK`, `created_by_user_id integer not null FK`, `title string not null`, `estimate_number string not null unique`, `status string not null default 'draft'`, `job_start_date date null`, `job_end_date date null`, `notes text null`, `client_notes text null`, `created_at`, `updated_at`
  - `enum :status, { draft: "draft", sent: "sent", approved: "approved", lost: "lost", archived: "archived" }, default: "draft"`
  - `belongs_to :client`; `belongs_to :created_by, class_name: "User", foreign_key: :created_by_user_id`
  - `has_many :estimate_sections, dependent: :destroy, -> { order(:position) }`
  - `has_many :line_items, through: :estimate_sections`
  - `before_validation :assign_estimate_number, on: :create` — generates `EST-YYYY-NNNN` within a database transaction with a lock to prevent duplicates. See data-model-review.md for the reference implementation.
  - Indexes: `client_id`, `created_by_user_id`, `estimate_number` (unique), `status`, `updated_at`.

- New model: `EstimateSection`
  - Columns: `id`, `estimate_id integer not null FK`, `name string not null`, `position integer not null default 0`, `default_markup_percent decimal(5,2) not null default 0.0`, `created_at`, `updated_at`
  - `belongs_to :estimate`
  - `has_many :line_items, dependent: :destroy, -> { order(:position) }`
  - `acts_as_list scope: :estimate` (requires `acts_as_list` gem from SPEC-002)
  - Indexes: `estimate_id`; composite `(estimate_id, position)`.

### API / Logic

- `EstimatesController`: `index`, `show`, `new`, `create`, `edit`, `update`, `destroy` — all require login.
  - `create`: sets `created_by_user_id` to `current_user.id`.
  - `update`: includes status change (no separate action needed for MVP status transitions).
  - Dashboard (`index`): accepts `status` and `q` query params for filtering and search.
- `EstimateSectionsController`: nested under estimates. Actions: `new`, `create`, `edit`, `update`, `destroy` — all require login.
  - `destroy`: use Turbo confirm dialog for sections that have line items. Cascade is handled by `dependent: :destroy` on the association.
  - Reorder action: `PATCH /estimates/:estimate_id/estimate_sections/:id/move` (or similar) — accepts `direction: up|down`, calls `acts_as_list` `move_higher` / `move_lower`.
- Routes: `resources :estimates do; resources :estimate_sections; end`; add member route for reorder.
- `current_user` available from Authentication concern (SPEC-003).

### UI / Frontend

- Estimates dashboard (`/estimates`): sortable by updated_at (default), filterable by status dropdown, text search field for client name or job title.
- New estimate form: client selector (dropdown of existing clients), title field, optional job_start_date / job_end_date, notes. "Or create a new client" link.
- Estimate edit page: shows estimate metadata at top, list of sections with line item counts, add section form/button, reorder controls (up/down arrows), delete button per section.
- Section form: name field, default_markup_percent field.
- Status badge on estimate show/edit page; editable via dropdown or segmented button set.

### Background Processing
- None.

## Test Requirements

### Unit Tests

- `Estimate`: `assign_estimate_number` generates correct format on create.
- `Estimate`: two estimates saved in the same year increment the sequence correctly.
- `Estimate`: status enum accepts valid values; rejects invalid values.
- `Estimate`: validates presence of `title` and `client_id`.
- `EstimateSection`: validates presence of `name`.
- `EstimateSection`: `acts_as_list` inserts at the bottom of the list on create.

### Integration Tests

- `POST /estimates` with valid params: creates estimate with correct estimate_number, status "draft", redirects to edit.
- `POST /estimates` without a client: returns 422, shows error.
- `POST /estimates/:id/estimate_sections` with valid params: creates section, appears on estimate edit page.
- `PATCH /estimates/:id/estimate_sections/:id/move` with direction "up": section position decrements.
- `DELETE /estimates/:id/estimate_sections/:id` with no line items: destroys section.
- `PATCH /estimates/:id` with new status: persists updated status.
- `GET /estimates?status=sent`: returns only estimates with "sent" status.

### End-to-End Tests

- Create an estimate for an existing client, add three sections, reorder them, confirm order persists after page reload.
- Change estimate status to "sent", navigate to dashboard, confirm it appears in the "sent" filter.

## Out of Scope

- Drag-and-drop section reordering (deferred to Phase 7 polish).
- Estimate duplication / cloning (Phase 7).
- Hard block on editing an estimate in "approved" status (post-MVP gap flagged in data-model-review.md).
- Estimate versioning / change orders (post-MVP).

## Open Questions

- OQ-08 is resolved: `job_start_date` / `job_end_date` date range columns.
- OQ-12 (estimate number format): `EST-YYYY-NNNN` is assumed. Confirm with shop owner before Phase 3 ships — if a different format is required, it only affects the generation callback, not the schema.
- No blockers for this phase.

## Dependencies

- SPEC-004 (Phase 2 — Clients and Contacts) must be complete. Creating an estimate requires a `client_id` to exist.
- SPEC-002 (Phase 0 — Foundation): `acts_as_list` gem must be in the bundle.

---

## Technical Guidance

**Reviewed by:** architect-agent
**Date:** 2026-04-04
**Relevant ADRs:** None new — existing decisions are sufficient for this phase.

---

### Pre-condition: Gemfile must be fixed before any model work

`bcrypt` is still commented out in the Gemfile. `has_secure_password` (added in Phase 1) raises at runtime without it. Confirm `gem "bcrypt", "~> 3.1.7"` is uncommented and `bundle install` has been run before generating any Phase 3 models. The `acts_as_list` gem must also be present. Both are Phase 0 prerequisites (build-order.md).

---

### Estimate number generation — use `SELECT FOR UPDATE` on PostgreSQL

The reference implementation in `data-model-review.md` calls `.lock("FOR UPDATE")` on the ActiveRecord query. PostgreSQL supports row-level locking natively, so this is the correct and idiomatic approach:

```ruby
def assign_estimate_number
  return if estimate_number.present?
  year = Date.current.year
  Estimate.transaction do
    last_num = Estimate.where("estimate_number LIKE ?", "EST-#{year}-%")
                       .order(:estimate_number)
                       .lock("FOR UPDATE")
                       .last
                       &.estimate_number
                       &.split("-")
                       &.last
                       &.to_i || 0
    self.estimate_number = "EST-#{year}-#{(last_num + 1).to_s.rjust(4, '0')}"
  end
end
```

The `FOR UPDATE` lock prevents concurrent transactions from reading the same last estimate number simultaneously. A safe fallback is to rescue `ActiveRecord::RecordNotUnique` on the estimate_number unique index and retry once. Choose one approach and document it in a code comment. The unique index on `estimate_number` is the real safety net; the locking strategy is defense-in-depth.

---

### Status enum — use string-backed enum, not integer

The spec correctly specifies `enum :status, { draft: "draft", sent: "sent", ... }`. Do not use the integer-backed shorthand (`enum :status, %i[draft sent ...]`) — integer enums make SQL queries unreadable and are fragile under reordering. The string form is already called out in `data-model-review.md` and the principle is in the ADR index. This is a one-way door: changing from integer to string enum after data is in production requires a data migration.

---

### `has_many` scope syntax in Rails 8

The spec shows:
```ruby
has_many :estimate_sections, dependent: :destroy, -> { order(:position) }
```
In Rails 8 the scope lambda must be the second positional argument — before keyword arguments. The above is correct. Confirm it is not accidentally written as:
```ruby
has_many :estimate_sections, -> { order(:position) }, dependent: :destroy  # wrong order in some Rails versions
```
Test with `estimate.estimate_sections.to_sql` to verify the ORDER BY is present.

---

### Section reorder controller action — use `acts_as_list` methods directly

The spec proposes `PATCH /estimates/:estimate_id/estimate_sections/:id/move` with a `direction` param. Keep this simple:

```ruby
# routes.rb
resources :estimate_sections do
  member { patch :move }
end

# EstimateSectionsController
def move
  @section = EstimateSection.find(params[:id])
  params[:direction] == "up" ? @section.move_higher : @section.move_lower
  redirect_to edit_estimate_path(@section.estimate), status: :see_other
end
```

Do not build a custom position-swap query. `acts_as_list` handles gap-filling and boundary conditions (moving the first item "up" is a no-op). Return a `303 See Other` redirect — this is a state-mutating action and must not be GET.

---

### Dashboard N+1 query risk

`GET /estimates` renders estimate number, client name, title, status, updated_at. The client name requires a JOIN or eager load. Always use:
```ruby
@estimates = Estimate.includes(:client).order(updated_at: :desc)
```
Add a filter scope:
```ruby
scope :with_status, ->(s) { where(status: s) if s.present? }
scope :search, ->(q) { where("title LIKE :q OR clients.company_name LIKE :q", q: "%#{q}%").joins(:client) if q.present? }
```
The search scope requires a JOIN, not just `includes`. Test that the search and status filters can be chained: `Estimate.includes(:client).with_status(params[:status]).search(params[:q])`.

---

### Turbo confirm for section delete with line items

AC-10 requires a confirmation dialog before cascade-deleting a section that has line items. The recommended approach is a Turbo confirm:

```erb
<%= button_to "Delete", estimate_estimate_section_path(@estimate, section),
      method: :delete,
      data: { turbo_confirm: "This section has #{section.line_items.count} line item(s). Delete everything?" } %>
```

This uses a browser `confirm()` dialog, which is the Rails/Turbo default. It is acceptable for MVP. If a custom modal is later required, the `data-turbo-confirm` behavior can be overridden with a Stimulus controller — but that is Phase 7 polish, not MVP.

---

### Route nesting depth

The spec nests EstimateSections under Estimates: `/estimates/:estimate_id/estimate_sections/:id`. In SPEC-006, LineItems are nested under EstimateSections: `/estimate_sections/:estimate_section_id/line_items/:id`. This means line items are NOT nested three levels deep under estimates, which is correct. Keep this shallow. Three-level nesting (`/estimates/:id/estimate_sections/:id/line_items/:id`) should be avoided — it produces unwieldy path helpers and makes it harder to navigate directly to a line item.

---

### Migration checklist

In addition to the columns listed in the spec, ensure the migration includes:
- `add_index :estimates, :estimate_number, unique: true`
- `add_index :estimates, :updated_at`
- `add_index :estimate_sections, [:estimate_id, :position]`
- Foreign key constraints: `add_foreign_key :estimates, :clients` and `add_foreign_key :estimates, :users, column: :created_by_user_id`

PostgreSQL enforces foreign key constraints by default. No additional configuration is needed — `add_foreign_key` in the migration is sufficient.
