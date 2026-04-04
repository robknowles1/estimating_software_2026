# Spec: Phase 5 — Catalog and Line Item Autocomplete

**ID:** SPEC-007
**Status:** draft
**Priority:** medium
**Created:** 2026-04-04
**Author:** pm-agent

---

## Summary

This phase adds a searchable catalog of commonly used line item descriptions. When an estimator types in a line item's description field, matching catalog items are suggested via a dropdown. Selecting a suggestion pre-fills description, unit, and unit_cost — all values remain editable. The estimator may ignore the autocomplete and type a custom description freely. The catalog also gets a basic management interface so staff can add, edit, and remove catalog entries over time. A seed script extracts common items from the Excel template.

This phase must not begin until the estimator validation session for OQ-02 has been completed (see Open Questions below).

## User Stories

- As an estimator, I want autocomplete suggestions when I type a line item description so that I can quickly reuse common items without retyping descriptions and looking up costs.
- As an estimator, I want to ignore autocomplete suggestions and type a custom description freely so that I am not blocked when adding a non-catalog item.
- As an estimator or admin, I want to manage the catalog so that it stays accurate and useful over time.

## Acceptance Criteria

1. Given the line item description field is focused and the estimator types at least 2 characters, a dropdown of matching catalog items appears within 300ms (debounced).
2. Given a dropdown is visible, when the estimator selects a catalog item, the description, unit, and unit_cost fields are pre-filled with the catalog item's default values.
3. Given pre-filled values from a catalog selection, the estimator can override any field value before saving.
4. Given the estimator types a description that has no catalog matches, the dropdown does not appear (or shows "No matches") and the estimator can save a fully custom line item.
5. Given the estimator ignores the dropdown and continues typing, the custom description is saved as-is with no requirement for a catalog match.
6. Given the catalog management page, a logged-in user can view all catalog items.
7. Given the catalog management page, a logged-in user can add a new catalog item with description, default_unit, default_unit_cost, and category.
8. Given a catalog item with a blank description, when the form is submitted, a validation error is shown and the item is not saved.
9. Given a saved catalog item, a logged-in user can edit any field and save successfully.
10. Given a saved catalog item, a logged-in user can delete it. Existing line items that were sourced from this catalog item are not affected (catalog_item_id is nullified, not cascade deleted).
11. Given `db:seed` is run, the catalog is pre-populated with common items extracted from the Excel template.

## Technical Scope

### Data / Models

- New model: `CatalogItem`
  - Columns: `id`, `description string not null`, `default_unit string null`, `default_unit_cost decimal(10,2) null`, `category string null`, `created_at`, `updated_at`
  - `has_many :line_items, dependent: :nullify` (nullifies `catalog_item_id` on associated line items — does not delete them)
  - Validates presence of `description`.
  - Indexes: `index_catalog_items_on_description`; `index_catalog_items_on_category`.

- `LineItem` model: `catalog_item_id` already in schema from Phase 4. No migration change needed.

- `db/seeds.rb`: add catalog item seed data derived from the Excel template's common line item descriptions, units, and typical costs. The Excel file (`Estimating Template - 3.21.26.xltx`) is in the repo root and should be reviewed for this purpose.

### API / Logic

- `CatalogItemsController`:
  - Standard CRUD: `index`, `new`, `create`, `edit`, `update`, `destroy` — all require login.
  - Search endpoint: `GET /catalog_items/search?q=<term>` — returns JSON array of matching catalog items (id, description, default_unit, default_unit_cost). Must require login. Matching: case-insensitive prefix or substring match on description. Returns at most 10 results.
- On line item create: if the user selected a catalog suggestion, wire `catalog_item_id` to the selected catalog item's id. This is optional — do not require a catalog match.
- Routes: `resources :catalog_items`; add collection route for `search`.

### UI / Frontend

- Stimulus controller: `description_autocomplete_controller.js`
  - Debounce: 200–300ms after last keypress.
  - On debounce trigger: `fetch` to `/catalog_items/search?q=<value>`, parse JSON, render dropdown.
  - On item select: populate description, unit, unit_cost fields; store selected catalog_item_id in a hidden input.
  - On Escape key or click outside dropdown: dismiss dropdown.
  - Keyboard navigation: up/down arrows to navigate suggestions; Enter to select.
  - Accessibility: use `role="listbox"` and `role="option"` on dropdown elements; manage `aria-activedescendant`.
- Wire the autocomplete controller to the description field in the line item form partial (from Phase 4).
- Catalog management page (`/catalog_items`): table of items with description, unit, cost, category. Filter by category. Links to edit/delete per row. "Add item" button.

### Background Processing
- None.

## Test Requirements

### Unit Tests

- `CatalogItem`: validates presence of description.
- `CatalogItem`: deleting a catalog item nullifies `catalog_item_id` on associated line items, does not delete line items.
- Search query: `CatalogItem.search("trim")` returns matching records case-insensitively.

### Integration Tests

- `GET /catalog_items/search?q=door` without login: redirects to login.
- `GET /catalog_items/search?q=door` with login: returns JSON array with matching items.
- `GET /catalog_items/search?q=zzz_no_match` with login: returns empty JSON array.
- `POST /catalog_items` with valid params: creates item.
- `DELETE /catalog_items/:id`: destroys catalog item; associated line items have `catalog_item_id` set to null.

### End-to-End Tests

- Type "crown" in a line item description field. Confirm a dropdown appears with a matching catalog item. Select the item. Confirm description, unit, and unit_cost are pre-filled. Save the line item. Confirm it persists with the correct values.
- Type "zzzzz" in the description field. Confirm no dropdown appears. Save with a custom description. Confirm it saves successfully.

## Out of Scope

- Catalog-first (Pattern B) workflow — this spec implements Pattern C (freeform with optional autocomplete) per ADR-005.
- Bulk import of catalog items via CSV upload.
- Category management UI (categories are entered as freeform strings on each catalog item).
- Fuzzy / similarity search — substring match is sufficient for MVP.

## Open Questions

- **OQ-02 (BLOCKER for this phase):** The estimator validation session must confirm Pattern C (freeform + autocomplete) is acceptable before development of the Stimulus autocomplete controller begins. If the session reveals a preference for Pattern B (catalog-first), the autocomplete frontend changes significantly, though the CatalogItem model and search endpoint remain the same.
- OQ-11: Should the catalog be pre-seeded from the Excel template? Assumed yes. A developer must review the Excel file in the repo root and extract common items. If the extraction is complex, this can be done as a follow-up seed task after the model and controller are built.

## Dependencies

- SPEC-006 (Phase 4 — Line Items and Totals) must be complete. The autocomplete wires into the line item form from Phase 4.
- OQ-02 estimator validation session must be completed and confirm Pattern C before the autocomplete Stimulus controller is built.
