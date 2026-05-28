# Spec: Estimate Date Fields

**ID:** SPEC-023
**Status:** ready
**Priority:** low
**Created:** 2026-05-27
**Author:** spec-agent

---

## Goal

Replace the generic `job_start_date` / `job_end_date` columns on estimates with purpose-named columns that match how Blake (estimator, TrimArt) actually uses them: one date for when the bid must be submitted, and one date for when work is expected to begin on site. This is a column rename with no behaviour change — only naming, labels, and i18n keys change.

---

## Non Goals

- Adding new date fields beyond the two renamed ones.
- Date validation (e.g., bid due date must precede job start date).
- Displaying dates on the estimate index page.
- Surfacing dates in any printed or exported output (PDF, CSV).
- Any change to estimate creation logic or defaults.

---

## Definitions

| Term | Definition |
|------|-----------|
| Bid Due Date | The date by which the estimator must submit the bid or proposal to the client. Maps to the new `bid_due_date` column. |
| Job Start Date | The date on which work is expected to begin on site. Maps to the new `job_start_date` column. |
| Column rename migration | A migration that renames an existing database column, preserving all existing row data. No data is deleted or transformed. |

---

## Interfaces

### Database columns — before and after

| Before | After | Type |
|--------|-------|------|
| `estimates.job_start_date` | `estimates.bid_due_date` | `date`, nullable |
| `estimates.job_end_date` | `estimates.job_start_date` | `date`, nullable |

### Form fields (estimates `_form` partial)

| Field | Label (before) | Label (after) |
|-------|---------------|--------------|
| `bid_due_date` (was `job_start_date`) | "Start Date" | "Bid Due Date" |
| `job_start_date` (was `job_end_date`) | "End Date" | "Job Start Date" |

### Strong parameters

`EstimatesController#estimate_params` must replace `:job_start_date, :job_end_date` with `:bid_due_date, :job_start_date`.

### i18n keys (`config/locales/en.yml`)

| Before | After |
|--------|-------|
| `activerecord.attributes.estimate.job_start_date: "Start Date"` | `activerecord.attributes.estimate.bid_due_date: "Bid Due Date"` |
| `activerecord.attributes.estimate.job_end_date: "End Date"` | `activerecord.attributes.estimate.job_start_date: "Job Start Date"` |

Note: the `job_start_date` i18n key name is retained (it now refers to the renamed column of the same name, i.e. the former `job_end_date`). Only its label value changes from `"Start Date"` to `"Job Start Date"`. A new key `bid_due_date` is added with the value `"Bid Due Date"`. The old `job_end_date` key is removed.

---

## Rules

R1: The `estimates` table must have a `bid_due_date` column (date, nullable) and a `job_start_date` column (date, nullable). The columns `job_end_date` must no longer exist after the migration runs.

R2: The rename migration must use `rename_column` (not `remove_column` + `add_column`) so that existing date values are preserved without any data loss.

R3: The estimate form must render a date field labelled "Bid Due Date" bound to `bid_due_date`, and a date field labelled "Job Start Date" bound to `job_start_date`. Field order: Bid Due Date appears first (left), Job Start Date appears second (right), matching the existing two-column grid layout. Field positions are unchanged from the current form — the left field (`job_start_date`, renamed to `bid_due_date`) remains on the left; the right field (`job_end_date`, renamed to `job_start_date`) remains on the right. No DOM reorder is required.

R4: The strong parameters permit list in `EstimatesController` must include `:bid_due_date` and `:job_start_date`. The old symbol `:job_end_date` must be removed.

R5: All i18n label keys for the renamed columns must be updated so that no "Start Date" or "End Date" strings remain for these fields in `en.yml`.

R6: No existing application code, test file, or factory may reference the column name `job_end_date` after this change is applied. Migration files are exempt from this check.

---

## Edge Cases

E1: Estimates created before the migration that have a value in `job_start_date` retain that value in the renamed `bid_due_date` column. Estimates that have a value in `job_end_date` retain that value in the renamed `job_start_date` column. No values are lost.

E2: Estimates with `nil` in either date column remain `nil` after the rename — no default is introduced.

E3: The status-update and job-costs sub-forms on `app/views/estimates/edit.html.erb` do not include the date fields and require no changes.

---

## Acceptance Criteria

AC-1: After running `db:migrate`, the `estimates` table has a `bid_due_date` column and a `job_start_date` column. The `job_end_date` column does not exist. Existing date values (if any) are preserved in the renamed columns.

AC-2: The estimate new/edit form renders a date input with label "Bid Due Date" bound to `bid_due_date`, and a date input with label "Job Start Date" bound to `job_start_date`. The two fields appear side-by-side in a two-column grid, Bid Due Date on the left.

AC-3: Submitting the estimate form with a value in either date field saves that value to the correct column (`bid_due_date` or `job_start_date`). Submitting with both fields blank saves `nil` to both columns.

AC-4: The i18n file `config/locales/en.yml` contains `bid_due_date: "Bid Due Date"` and `job_start_date: "Job Start Date"` under `activerecord.attributes.estimate`. The keys `job_end_date` and the old `job_start_date: "Start Date"` entry do not appear.

AC-5: A codebase-wide search for the string `job_end_date` returns zero matches in `app/`, `spec/`, `config/`, and `db/migrate/` (excluding the rename migration file itself and the original migration that added `job_start_date`/`job_end_date` — both are historical files and will legitimately contain the old column names).

---

## Acceptance Tests

AT1
Given the migration has been run on a database containing an estimate with `job_start_date = 2026-06-01` and `job_end_date = 2026-08-15`
When the estimate is reloaded from the database
Then `estimate.bid_due_date` equals `2026-06-01` and `estimate.job_start_date` equals `2026-08-15`
Covers: R1, R2, E1

AT2
Given an authenticated estimator on the new estimate form
When the page renders
Then a date input with label "Bid Due Date" is present, and a date input with label "Job Start Date" is present, and no label reading "Start Date" or "End Date" appears on the page
Covers: R3, R5

AT3
Given an authenticated estimator on the new estimate form
When they fill in "Bid Due Date" with 2026-07-01 and "Job Start Date" with 2026-09-01 and submit
Then the created estimate has `bid_due_date = 2026-07-01` and `job_start_date = 2026-09-01`
Covers: R3, R4, AC-3

AT4
Given an authenticated estimator on the edit form for an existing estimate
When they clear both date fields and save
Then `bid_due_date` and `job_start_date` are both `nil` on the saved estimate
Covers: R4, E2

AT5
Given an unauthenticated request to `PATCH /estimates/:id` with date parameters
When the request is made
Then the response redirects to the login page and no record is modified
Covers: R4 (strong params path is guarded by authentication)

---

## Implementation Notes

### Migration

Use two `rename_column` calls in a single migration:

```ruby
rename_column :estimates, :job_start_date, :bid_due_date
rename_column :estimates, :job_end_date,   :job_start_date
```

No `change_column`, `add_column`, or `remove_column` calls. The migration must be reversible; `rename_column` is reversible by default in Rails.

**Warning:** Confirm OQ-1 before running this migration. A backwards mapping will silently corrupt date data on all existing estimates.

### Files to touch

| File | Change |
|------|--------|
| `db/migrate/<timestamp>_rename_estimate_date_columns.rb` | New migration — two `rename_column` calls |
| `app/controllers/estimates_controller.rb` | Replace `:job_start_date, :job_end_date` with `:bid_due_date, :job_start_date` in `estimate_params` |
| `app/views/estimates/_form.html.erb` | Replace `f.label :job_start_date` / `f.date_field :job_start_date` with `:bid_due_date`; replace `f.label :job_end_date` / `f.date_field :job_end_date` with `:job_start_date` |
| `config/locales/en.yml` | Rename keys as specified in the Interfaces section |
| `db/schema.rb` | Auto-updated by `db:migrate` — no manual edit |

### No model changes

`Estimate` has no callbacks, validations, or computed attributes referencing either date column. The model file requires no changes.

### No test file changes

A search of `spec/` for `job_start_date` and `job_end_date` returns zero matches (confirmed at spec authoring time). If any factory or spec file is found during implementation to reference `job_end_date`, it must be updated as part of this change per R6.

---

## Open Questions

| OQ | Question | Status |
|----|----------|--------|
| OQ-1 | **IMPLEMENTATION BLOCKER:** Which of the two current columns stores the bid due date (submission deadline) and which stores the job on-site start date? The spec assumes `job_start_date` = bid due date and `job_end_date` = job start date. Confirm with Blake before running the migration. If the mapping is reversed, the `rename_column` calls in the migration must be swapped. | **Unresolved — confirm with Blake before coding.** |

---

## Dependencies

- SPEC-010 (Estimating Foundation) — `estimates` table and `EstimatesController` must exist. Status: done.

---

## Implementation Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-27 | Use `rename_column` (not drop + add) | Preserves existing data without a data migration step. Required by R2. |
| 2026-05-27 | No validation added for date ordering | Out of scope per Non Goals. Estimators sometimes enter partial dates; enforcing ordering would block saves. |

---

## Change Log

| Date | Change | Affected IDs | Rationale |
|------|--------|-------------|-----------|
| 2026-05-27 | Initial spec authored | All | Feature request from Blake (TrimArt) — 2026-05-22 meeting |
| 2026-05-27 | Added OQ-1 (column mapping blocker), migration warning, R3 field-position clarification, R6 migration exemption, AC-5 original-migration exemption, i18n key-vs-value note, E3 file path fix | OQ-1, R3, R6, AC-5, E3, Interfaces | Reviewer feedback — address ambiguities before implementation |
