# Spec: Phase 7 — Polish and Hardening

**ID:** SPEC-009
**Status:** draft
**Priority:** low
**Created:** 2026-04-04
**Author:** pm-agent

---

## Summary

After the core workflow is validated with real estimators (Phases 1–6), this phase addresses quality-of-life improvements, performance, and hardening. None of these items block the primary estimating workflow, but they meaningfully improve the day-to-day experience. Items should be scheduled based on feedback gathered during early real-world use — not all of them may be equally valuable.

## User Stories

- As an estimator, I want to drag and drop sections and line items to reorder them quickly so that I do not have to click up/down arrows repeatedly.
- As an estimator, I want to search the estimates dashboard by client name or job title so that I can find a specific estimate without scrolling.
- As an estimator, I want to apply a single markup percentage to all line items in a section at once so that I do not have to set markup on every line item individually.
- As a user, I want to change my own password so that I can maintain account security.
- As an estimator, I want to duplicate an existing estimate so that I can use a past job as a starting point for a similar new job.

## Acceptance Criteria

1. Given sections on an estimate, when an estimator drags a section card to a new position and drops it, the order updates immediately and persists on page reload.
2. Given line items in a section, when an estimator drags a line item to a new position and drops it, the order updates immediately and persists on page reload.
3. Given the estimates dashboard with a search field, when an estimator types a client name or job title fragment, the estimate list filters to matching results without a full page reload.
4. Given a section with multiple line items, when an estimator uses a "Set markup for all items" control and submits a percentage, all line items in that section have their `markup_percent` updated to the new value, and totals update.
5. Given a logged-in user, when they navigate to their account settings and submit a new password with confirmation, the password is updated and they remain logged in.
6. Given an existing estimate, when an estimator clicks "Duplicate," a new estimate is created with the same client, title (prefixed with "Copy of"), sections, and line items, in "draft" status, with a new auto-generated estimate number.
7. Given the estimate index and estimate edit views, when they load with 20+ line items across multiple sections, there are no N+1 query warnings in the Rails log.

## Technical Scope

### Data / Models

- No new models or migrations required for this phase.
- Duplicate estimate action: deep copy of estimate, all sections, and all line items. `catalog_item_id` links are preserved on copied line items. `estimate_number` is newly generated. Status is forced to "draft".

### API / Logic

- Drag-and-drop reorder: `PATCH /estimates/:id/estimate_sections/reorder` and `PATCH /estimate_sections/:id/line_items/reorder` — accept an ordered array of IDs and bulk-update positions using `acts_as_list`.
- Bulk markup update: `PATCH /estimates/:estimate_id/estimate_sections/:id/bulk_markup` — accepts `markup_percent`, updates all child line items.
- Password change: `PATCH /users/:id/password` — validates current password, sets new password.
- Estimate duplication: `POST /estimates/:id/duplicate` — deep copies the estimate and redirects to the new estimate's edit page.
- Dashboard search: add debounced Stimulus controller that re-fetches `/estimates?q=<term>` and replaces the list via Turbo Frame (or implement server-side with standard filter params — developer's choice).

### UI / Frontend

- Drag-and-drop: integrate SortableJS via `stimulus-sortable` or a similar lightweight Stimulus wrapper. Apply to section list and line item list.
- Bulk markup: a form or popover on the section header with a markup_percent input and "Apply to all" button.
- Password change form: accessible from user account settings page.
- "Duplicate" button on estimate show/edit page.
- N+1 fix: add `includes` on `estimates` index query (client, estimate_sections, line_items as needed); add `includes` on estimate edit action.

### Background Processing
- None.

## Test Requirements

### Unit Tests

- Estimate duplication: duplicated estimate has new estimate_number, status "draft", correct section and line item count.
- Bulk markup: all line items in a section have updated markup_percent after bulk update.

### Integration Tests

- `POST /estimates/:id/duplicate`: creates a new estimate record with correct associations, redirects to new estimate.
- `PATCH /estimate_sections/:id/bulk_markup`: all line items in section have updated markup_percent; totals reflect change.
- `PATCH /users/:id/password` with correct current password and matching new password/confirmation: updates password_digest.
- `PATCH /users/:id/password` with incorrect current password: returns 422, does not update.

### End-to-End Tests

- Full estimate creation flow with drag-and-drop: create estimate, add sections, drag to reorder, confirm order persists.
- Duplicate an estimate, confirm new estimate number and "Copy of" title prefix, confirm sections and line items match the original.

## Out of Scope

- Role-based access control (post-MVP).
- Audit trail / who-edited-what history (post-MVP gap flagged in data-model-review.md).
- Soft-delete for clients or users (post-MVP gap).
- Email delivery (post-MVP).
- Mobile native application.
- `cost_type` UI and cost-category reporting (post-MVP).

## Open Questions

- Drag-and-drop library: `stimulus-sortable` (wraps SortableJS) is recommended as the lightest option compatible with Stimulus conventions. Developer should verify the gem/npm package is actively maintained at time of implementation.
- Dashboard search: server-side filtering with Turbo Frame is simpler and more accessible than a full client-side filter. Recommended approach unless the list size justifies a more dynamic solution.

## Dependencies

- SPEC-006 (Phase 4) and SPEC-007 (Phase 5) and SPEC-008 (Phase 6) must be complete before Phase 7 begins. Polish work is scheduled after the core loop is validated with real estimators.
