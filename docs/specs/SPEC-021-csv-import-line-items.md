# Spec: CSV Import for Estimate Line Items

**ID:** SPEC-021
**Status:** done
**Priority:** high
**Created:** 2026-05-12
**Author:** pm-agent

---

## Summary

Estimators currently add line items one at a time through a form on the estimate page. Many source estimates arrive as CSV exports from an external system with dozens of products. This feature adds a bulk import path: the user uploads a CSV file from the estimate page, the system parses it into grouped product rows, finds or creates matching Product catalog entries, and appends new line items to the estimate — leaving any existing line items untouched.

## User Stories

- As an estimator, I want to upload a CSV file on the estimate page, so that I can create all line items from a source document in one action instead of entering them one by one.
- As an estimator, I want the import to skip clarification and exclusion rows automatically, so that I do not have to clean up the CSV before uploading.
- As an estimator, I want products found in the catalog to have their material and labor templates applied, so that estimated costs are pre-filled.
- As an estimator, I want newly imported products saved to the catalog, so that future estimates can reuse them.
- As an estimator, I want a clear flash message telling me how many line items were created, so that I know whether the import succeeded and how much was imported.
- As an estimator, I want a failed import to leave the estimate unchanged, so that I do not need to manually undo a partial import.

## Acceptance Criteria

1. Given an authenticated user on the estimate edit/show page, when they view the line items section, then a file upload control (labelled "Import CSV") is present and accessible without navigating to another page.
2. Given a valid CSV file matching the defined format, when the user submits it via the import control, then exactly one line item is created per unique product number (col 4), skipping any rows where col 0 starts with "z" or col 4 is blank; and when a "Total" row (col 7 == "Total") exists for a product group, that row's qty (col 8) is used; otherwise the first non-Total row's qty is used.
3. Given a successful import, when line items are created, then each line item is linked to a Product record (product_id is set); Products that did not previously exist in the catalog are created with name from col 5, category from col 0, and unit from col 9.
4. Given a product name from the CSV matches an existing Product record (case-insensitive, stripped of leading/trailing whitespace), when the line item is created, then `product.apply_to(line_item)` is called so material slot qtys and labor hours from the catalog template are applied.
5. Given a successful import, when the estimate is reloaded, then the newly created line items are appended after any pre-existing line items on the estimate (pre-existing line items are not modified or removed).
6. Given a successful import of N products, when the controller redirects, then a flash notice contains the count N (e.g. "Imported 12 line items").
7. Given a CSV file that cannot be parsed (malformed CSV, missing required columns, non-numeric quantity values), when the import is submitted, then no line items or products are created, the estimate is unchanged, and a flash alert is shown describing the error.
8. Given an unauthenticated request to the import route, when the request is made, then the response redirects to the login page and no records are created.

## Technical Scope

### Data / Models

No schema changes required. The import reads from existing `products`, `line_items`, and `estimates` tables only. Product.find_or_create logic uses a case-insensitive name match: `Product.where("lower(name) = ?", name.downcase.strip).first_or_initialize`.

### API / Logic

**Route** — add a collection route inside the `line_items` resource block:

```ruby
resources :line_items, only: [...] do
  collection do
    post :import
  end
  member do
    patch :move
  end
end
```

This yields `POST /estimates/:estimate_id/line_items/import` with named helper `import_estimate_line_items_path`.

**Service object** — `app/services/line_item_csv_importer.rb`

Class: `LineItemCsvImporter`

Constructor: `initialize(estimate, file)` where `file` is an ActionDispatch::Http::UploadedFile (or any object responding to `#path` and `#read`).

Public method: `call` — returns a result object (or plain struct) with:
- `line_items_created` (Integer) — count of line items appended
- `error` (String or nil) — human-readable error message; nil on success

Internal parse logic (stateful, single pass):

1. Use Ruby's `CSV.foreach` (or `CSV.parse`) with `liberal_parsing: true` to tolerate minor formatting variance.
2. Skip a row if `row[0].to_s.strip` starts with "z" (case-sensitive as per source format) or `row[4].to_s.strip` is blank or zero.
3. Maintain a `current_group` hash: `{ product_number:, name:, category:, unit:, qty: }`.
4. On a non-Total row where `row[4]` differs from `current_group[:product_number]`: finalize the current group (if any) and open a new group with `product_number: row[4].strip`, `name: row[5].to_s.strip`, `category: row[0].to_s.strip`, `unit: row[9].to_s.strip`, `qty: row[8].to_s.strip.to_d`.
5. On a Total row (`row[7].to_s.strip == "Total"`): override `current_group[:qty]` with `row[8].to_s.strip.to_d`.
6. After all rows: finalize the last group.
7. Raise a descriptive error (caught in rescue block) if the CSV has fewer than 10 columns in any non-skipped row, or if any finalized group has qty <= 0.

Finalize group logic: call `Product.where("lower(name) = ?", group[:name].downcase).first_or_initialize` and set `category` and `unit` on the instance before saving if new. Build a `LineItem` on `@estimate.line_items`, call `product.apply_to(line_item)`, then set `line_item.description = product.name`, `line_item.quantity = group[:qty]`, `line_item.product_id = product.id`. Collect all products and line items; persist all inside a single `ActiveRecord::Base.transaction` block after the parse loop completes. Wrap the entire `call` method in a rescue block that catches `CSV::MalformedCSVError`, `ArgumentError`, and any `ActiveRecord::RecordInvalid` to return an error result without raising.

**Controller action** — `LineItemsController#import`:

```ruby
def import
  file = params[:csv_file]
  result = LineItemCsvImporter.new(@estimate, file).call
  if result.error
    redirect_to edit_estimate_path(@estimate), alert: result.error
  else
    redirect_to edit_estimate_path(@estimate),
      notice: t(".notice", count: result.line_items_created)
  end
end
```

The `@estimate` is already set by the `before_action :set_estimate`. No additional authorization check is needed beyond `require_login` (inherited).

### UI / Frontend

On the estimate edit page, in the line items section header (alongside any existing "Add Line Item" button), add an "Import CSV" button that expands an inline form or reveals a small panel. The developer may choose between:
- An inline `<details>` / `<summary>` disclosure widget
- A Turbo Frame or Stimulus-driven toggle
- A direct inline form (always visible)

The form must contain:
- A file input: `name="csv_file"`, `accept=".csv,text/csv"`
- A submit button labelled with `t(".import")`
- The form action points to `import_estimate_line_items_path(@estimate)` with `method: :post` and `multipart: true`

Show no separate import page — the import control lives on the existing estimate edit page. All labels and button text must use i18n keys.

### Background Processing

None. Import is synchronous. Files from real-world usage contain at most a few hundred rows; no async processing is needed.

## Test Requirements

### Unit Tests

File: `spec/services/line_item_csv_importer_spec.rb`

Cover:
- A CSV with two products (no Total rows) creates two line items with the individual row qtys.
- A CSV where a product spans multiple room rows followed by a Total row creates one line item using the Total row qty.
- A row where col 0 starts with "z" is skipped entirely.
- A row where col 4 is blank is skipped.
- A product name that matches an existing Product (case-insensitive) does not create a duplicate; `apply_to` values are present on the resulting line item.
- A product name with no existing match creates a new Product with correct name, category, and unit.
- Import appends to an estimate that already has one line item (pre-existing line item count is unchanged, new ones are added).
- `result.line_items_created` equals the number of finalized groups.
- A malformed CSV (fewer than 10 columns) returns `result.error` non-nil and creates no records.
- A group with qty <= 0 returns `result.error` non-nil and creates no records (full rollback).

### Integration Tests

File: additions to `spec/requests/line_items_spec.rb`

Cover:
- `POST /estimates/:estimate_id/line_items/import` with a valid CSV fixture file redirects to `edit_estimate_path` and increases `LineItem.count` by the expected amount.
- `POST /estimates/:estimate_id/line_items/import` with a valid CSV fixture shows a flash notice containing the count.
- `POST /estimates/:estimate_id/line_items/import` with an invalid/empty file redirects with an alert and does not change `LineItem.count`.
- Unauthenticated `POST` to the import route redirects to the login page.

Use `fixture_file_upload` or `Rack::Test::UploadedFile` to attach a small CSV fixture stored at `spec/fixtures/files/sample_import.csv`.

### End-to-End Tests

None required for this spec. The request specs cover the full controller-to-service-to-database flow. A future UI polish spec may add a system spec for the file upload interaction.

## Out of Scope

- Editing or updating existing line items via CSV (import only appends).
- Deduplication of line items already on the estimate — if the same product appears in both an earlier import and a new one, it is added again.
- Room-level breakdown or sub-grouping — room names (col 2) are ignored.
- CSV export of line items.
- Background/async processing or progress indicators.
- Any UI changes outside the estimate edit page line items section.
- Matching products by product number from the CSV (col 4) — matching is by name only.

## Open Questions

None blocking. The following are deferred decisions:

- **Q1 (deferred):** Should the import route validate that the CSV product number (col 4) matches an existing product code field? Currently products have no numeric code column; name-matching is the agreed approach. If a code column is added in future, import logic would need revisiting.
- **Q2 (deferred):** Should a maximum file size limit be enforced? Rails defaults (typically 25 MB ActionDispatch limit) are sufficient for realistic CSVs; no explicit limit is specified here.

## Dependencies

- SPEC-013 (Product Catalog) — `Product` model and `apply_to` method must be present. Status: done.
- SPEC-011 (Line Item Grid) — `LineItem` model and estimate association must be present. Status: done.
