# Spec: Material Alias and Auto-Population on CSV Import

**ID:** SPEC-022
**Status:** done
**Priority:** high
**Created:** 2026-05-22
**Author:** pm-agent

---

## Summary

When an estimator imports a CSV takeoff (SPEC-021), each line item lands with a product name like "PL1 Base Cabinet" or "SS5 Tall Open Box." The prefix codes (`PL1`, `SS5`) are job-specific architect codes — the estimator must currently look up what each code means for this job and then manually assign every material slot on every line item. On a large estimate this takes a full day. This spec introduces a `short_code` field on `estimate_materials` (the per-estimate price book) so that the estimator can assign a short code (e.g., `PL1`) to each price book entry once per job. During CSV import — and optionally on demand — any line item whose product name contains a known short code has its material slots auto-populated with the matching `estimate_materials` record. Line items that could not be matched are visually flagged so the estimator knows what still needs manual attention.

---

## User Stories

- As an estimator, I want to type a short code (e.g., `PL1`) on each row in the estimate's price book, so that I can link architect codes to materials once per job rather than on every line item.
- As an estimator, I want CSV-imported line items to have their material slots automatically assigned when the product name contains a known short code, so that I do not have to fill in materials row-by-row after import.
- As an estimator, I want unmatched line items (no short code found in the product name) to be visually flagged on the estimate page, so that I can quickly identify which rows still need manual material assignment.
- As an estimator, I want to re-run auto-population after editing short codes, so that I can fix mis-assignments without deleting and re-importing line items.
- As an estimator, I want a warning if two price book entries have the same short code, so that I can fix the conflict before relying on auto-population.

---

## Acceptance Criteria

1. Given the estimate's price book (`/estimates/:id/estimate_materials`), when the estimator views a row in the materials table, then an editable "Short Code" text field is present on the edit form for each `estimate_material` record. The field is optional; blank short codes are valid.

2. Given an estimator sets a short code (e.g., `PL1`) on an `estimate_material` record and saves, then `estimate_materials.short_code` is persisted. The short code is displayed as a read-only badge in the price book index table alongside the material name.

3. Given two `estimate_material` rows on the same estimate have the same non-blank short code, when either is saved, then a validation error is shown and the save is rejected. Short codes must be unique per estimate (case-insensitive comparison); blank short codes are exempt from the uniqueness check.

4. Given a CSV is imported and the estimate has at least one price book entry with a non-blank short code, when a line item's product name contains that short code string (case-insensitive substring match), then:
   a. The matching `estimate_material` is assigned to the `exterior_material_id` slot of that line item.
   b. The same `estimate_material` is also assigned to `interior_material_id`, `interior2_material_id`, and `back_material_id` for that line item.
   c. If the estimate also has an `estimate_material` with `role = "locks"`, `locks_qty` is left unchanged (already set by `Product#apply_to`); no material slot assignment is made for locks (resolved by role at calculator time).
   d. Hardware material slots (`drawers_material_id`, `pulls_material_id`, `hinges_material_id`, `slides_material_id`) are **not** auto-assigned by this spec; they are left null for manual assignment. Only the four primary slots (exterior, interior, interior2, back) are populated. See OQ-B.

5. Given a product name matches more than one short code in the price book (e.g., name "PL1 SS5 Cabinet" where both `PL1` and `SS5` are defined short codes), when the import runs, then the **longest-matching** short code is used for all primary slots (exterior, interior, interior2, back) and the line item is created without error. The importer counts these as ambiguous matches and includes a warning in the flash message: e.g., "Imported 12 line items. 2 had ambiguous short code matches — longest match was used." Use i18n key `t(".notice_with_ambiguity", imported: N, ambiguous: N)`. A line item is ambiguous if, after longest-match selection, the description still contains at least one other short code as a substring. Longest-match is used to minimise false positives (e.g. short code `PL` would otherwise match product names containing `PL1`, `PL2`, etc.).

6. Given a CSV is imported and a line item's product name contains no short code from the price book and matches no existing product in the catalog by name (i.e., it is a fully unrecognized row), when the estimate page is reloaded, then that line item is displayed with a visual "Needs review" flag (e.g., a yellow badge or warning icon on the line item card) indicating that no short code match was found.

7. Given the estimate's price book page, when there is at least one price book entry with a non-blank short code, then a button labelled "Apply short codes to all line items" is present. When clicked, the button re-runs short code matching across all existing line items on the estimate (not just newly imported ones) using the current short code state, overwriting any existing material slot assignments on matched line items.

8. Given an unauthenticated request to any new route introduced by this spec, when the request is made, then the response redirects to the login page and no records are modified.

---

## Technical Scope

### Data / Models

#### `estimate_materials` table — add `short_code` column

Add one column to the existing `estimate_materials` table:

| Column | Type | Notes |
|--------|------|-------|
| short_code | string | nullable; architect code for this job, e.g. `PL1`. Max 32 characters recommended but not DB-enforced. |

Migration: `add_column :estimate_materials, :short_code, :string`.

No index required; short code lookups are scoped to a single estimate and performed in Ruby after loading the estimate's materials.

**`EstimateMaterial` model updates:**

- Add `validates :short_code, uniqueness: { scope: :estimate_id, case_sensitive: false }, allow_blank: true`.
- Permit `short_code` in `EstimateMaterialsController#estimate_material_params`.
- Strip leading/trailing whitespace before validation: `before_validation { self.short_code = short_code.to_s.strip.presence }`.

#### No other schema changes

No changes to `line_items`, `products`, `materials`, or `estimates` tables.

The "needs review" flag is a derived display state, not a stored column. A line item is considered unmatched if **no short code from the current estimate's price book appears as a case-insensitive substring of its `description`**. Whether or not `exterior_material_id` is populated is not part of this check — a manually-assigned material should not suppress the badge if no short code was matched, and an auto-matched item that subsequently has its short code deleted should remain unflagged until the next "Apply short codes" run.

### API / Logic

#### Short code matching service — `app/services/line_item_alias_matcher.rb`

Class: `LineItemAliasMatcherService`

Constructor: `initialize(estimate)`

- On initialize, load all `estimate_materials` with a non-blank `short_code`, sorted by `short_code.length DESC` (longest first) to implement longest-match semantics, into a local array: `@code_entries`.
- Longest-match ensures that a short code of `PL1` beats a short code of `PL` when both appear on the same estimate, preventing false positives.

Public method: `match(line_item)` — given a single `LineItem` instance (not yet persisted or already persisted):
1. Return `nil` immediately if `@code_entries.empty?`.
2. Compute `desc = line_item.description.to_s.downcase` (nil-safe; an unsaved line item may not yet have a description set).
3. Use `String#include?` — **not** a regex — to check for substring presence. This is required because short codes may contain regex-special characters (e.g., `C+`, `T.1`).
4. Iterate through `@code_entries` (longest short code first); find the first entry whose `short_code.downcase` appears in `desc`.
5. If a match is found, assign the matched `estimate_material.id` to the line item's `exterior_material_id`, `interior_material_id`, `interior2_material_id`, and `back_material_id`. This **unconditionally overwrites** any existing values in those slots.
6. Return the matched `estimate_material`, or `nil` if no match.

The caller is responsible for detecting multi-code ambiguity: after longest-match selection, if the description still contains at least one other short code as a substring, the match is ambiguous. The service itself assigns only the longest match; the caller increments an `ambiguous_count`.

Public method: `apply_to_all_line_items` — wraps all saves in a single `ActiveRecord::Base.transaction` block. Applies `match` to every line item on the estimate, saves each line item if a match was found, and returns a result struct with `{ matched: Integer, unmatched: Integer, ambiguous: Integer }`. If any save raises, the transaction rolls back and the error is re-raised to the caller. The service must be initialized with the same estimate that owns the line items it is matching against; the `material_ids_belong_to_estimate` validation on `LineItem` will reject any cross-estimate assignment.

#### `LineItemCsvImporter` — extend `persist` to call short code matching

Instantiate one `LineItemAliasMatcherService` **once, before the `groups.each` loop**, then call `match(line_item)` for each line item before `line_item.save!`. Track matched, unmatched, and ambiguous counts.

Update the `Result` struct:
```ruby
Result = Data.define(:line_items_created, :matched_count, :unmatched_count, :ambiguous_count, :error)
```

**All existing `Result.new(...)` call sites in the importer** (including the `rescue` path that returns `Result.new(line_items_created: 0, error: e.message)`) must be updated to include the new fields (e.g., `matched_count: 0, unmatched_count: 0, ambiguous_count: 0`) — otherwise `Data.define` will raise `ArgumentError` at runtime.

Flash message variants (use distinct i18n keys):
- All matched, none ambiguous: "Imported 12 line items. All materials auto-assigned." (`t(".notice_all_matched")`)
- Some unmatched: "Imported 12 line items. 3 need review — no short code match found." (`t(".notice_with_unmatched", imported: N, unmatched: N)`)
- Some ambiguous: "Imported 12 line items. 2 had ambiguous short code matches — longest match was used." (`t(".notice_with_ambiguity", imported: N, ambiguous: N)`)
- Both: combine the two warning sentences in a single flash notice.

#### New controller action — `apply_aliases`

Add a **collection** action on the nested `line_items` resource (not a member action — do not use `member do`):

```
POST /estimates/:estimate_id/line_items/apply_aliases
```

Route addition in the `line_items` collection block:
```ruby
collection do
  post :import
  post :apply_aliases
end
```

`LineItemsController#apply_aliases`:
1. Instantiate `LineItemAliasMatcherService.new(@estimate)`.
2. Call `apply_to_all_line_items`. If it raises (transaction rollback), rescue and redirect with an error flash.
3. Redirect to `edit_estimate_path(@estimate)` with a flash notice containing matched, unmatched, and ambiguous counts. Use the same i18n key variants as the importer flash (see above).

### UI / Frontend

#### Price book index — short code column and "Apply short codes" button

On `app/views/estimate_materials/index.html.erb`:

- Add a "Short Code" column to the price book table, displaying `em.short_code.presence || "—"` as a read-only badge (e.g., a small monospace pill in slate or amber) alongside the material name.
- Add an "Apply short codes to all line items" button in the page header area (near the existing "Add material" button). The button submits a POST form to `apply_aliases_estimate_line_items_path(@estimate)`. Visibility check: `@estimate_materials.any? { |em| em.short_code.present? }` — use the already-loaded collection, not an extra query.

#### Price book edit form — short code field

On `app/views/estimate_materials/_form.html.erb` (and the `edit` view):

- Add a text input for `short_code` below the existing `quote_price` and `role` fields.
- Label: `t(".short_code_label")` (i18n).
- Placeholder: e.g., `PL1` (i18n key).
- Show inline validation errors if uniqueness fails.

#### Estimate edit page — "Needs review" flag on line items

On the line item card partial (wherever line items are rendered on the estimate edit page):

- Render a yellow "Needs review" badge on the card if no short code from the estimate's current price book appears as a case-insensitive substring of `line_item.description`. Compute this in the view (or a helper) using the already-loaded `@estimate_materials` collection — no extra query. Use i18n key `t("line_items.card.needs_review")`.
- The badge is a visual hint only; it does not prevent the estimator from saving or editing the line item.
- A line item with a manually-assigned `exterior_material_id` but no matching short code **will still show** the badge. A line item auto-matched on import **will not show** the badge as long as its short code remains in the price book.

#### Import flash message

See flash message variants specified in the `LineItemCsvImporter` section above. The same i18n keys are shared by both the import action and the `apply_aliases` action.

### Background Processing

None. Both the import extension and the `apply_aliases` action are synchronous. At realistic estimate sizes (a few hundred line items) this is appropriate.

---

## Test Requirements

### Unit Tests

**`EstimateMaterial` model (`spec/models/estimate_material_spec.rb`):**
- An `estimate_material` with a blank `short_code` is valid.
- An `estimate_material` with a unique `short_code` (within its estimate) is valid.
- Two `estimate_material` records on the same estimate with the same `short_code` (case-insensitive) fails validation with an error on `short_code`.
- Two `estimate_material` records on the same estimate with both blank `short_code` values are both valid (blank is not unique-checked).
- Two `estimate_material` records on different estimates may share the same `short_code` without error.
- `before_validation` strips leading/trailing whitespace from `short_code`.

**`LineItemAliasMatcherService` (`spec/services/line_item_alias_matcher_service_spec.rb`):**
- Given an estimate with one price book entry with `short_code: "PL1"`, and a line item with description `"PL1 Base Cabinet"`, `match` assigns the estimate material to `exterior_material_id`, `interior_material_id`, `interior2_material_id`, and `back_material_id`.
- Given an estimate with one price book entry with `short_code: "PL1"`, and a line item with description `"SS5 Upper Cabinet"` (no match), `match` returns `nil` and assigns no material slots.
- Short code matching is case-insensitive: `short_code: "pl1"` matches description `"PL1 Base Cabinet"`.
- Given two short codes `PL` and `PL1` both present on the estimate, and a line item description `"PL1 Cabinet"`, the **longest match** (`PL1`) is used. This test explicitly documents the longest-match strategy.
- Given `short_code: "C+"` and a line item description `"C+ Cabinet"`, `match` returns the estimate material. This guards against a regex-based implementation (regex would fail or misbehave on special characters; `String#include?` handles them correctly).
- Given a line item with `description: nil` (not yet persisted), `match` does not raise and returns `nil`.
- `match` unconditionally overwrites existing `exterior_material_id` values; calling it twice with different matched materials updates the slot both times.
- `apply_to_all_line_items` on an estimate with 2 matched and 1 unmatched line item returns a result with `matched: 2, unmatched: 1`.
- `apply_to_all_line_items` saves matched line items (their material slots are persisted after the call).
- `apply_to_all_line_items` does not modify or save unmatched line items.
- `apply_to_all_line_items` wraps saves in a transaction: if one line item save raises, no changes are persisted and the error is re-raised.
- When `@code_entries` is empty, `match` returns `nil` immediately without querying the database.

**`LineItemCsvImporter` (`spec/services/line_item_csv_importer_spec.rb` — additions):**
- Given an estimate with a price book entry with `short_code: "PL1"` and a CSV with a product named `"PL1 Base Cabinet"`, after import the created line item has `exterior_material_id` set to the matching estimate material.
- Given a CSV with a product named `"Unknown Material"` (no short code match), the created line item has `exterior_material_id` nil and `result.unmatched_count` is 1.
- Given a CSV with a product named `"PL1 SS5 Cabinet"` where both `PL1` and `SS5` are short codes on the estimate, `result.ambiguous_count` is 1.
- `result.matched_count` and `result.unmatched_count` sum to `result.line_items_created`.
- The rescue path (import fails) returns a `Result` with all count fields set to 0 and `error` populated — verifies no `ArgumentError` from missing `Data.define` keys.

### Integration Tests

**`EstimateMaterialsController` (`spec/requests/estimate_materials_spec.rb` — additions):**
- `PATCH /estimates/:estimate_id/estimate_materials/:id` with a valid unique `short_code` — updates `short_code`; redirects.
- `PATCH /estimates/:estimate_id/estimate_materials/:id` with a duplicate `short_code` (same code already on another row for this estimate) — returns 422 with an error and does not update.
- `PATCH` with a blank `short_code` — succeeds (blank is allowed).

**`LineItemsController` (`spec/requests/line_items_spec.rb` — additions):**
- `POST /estimates/:estimate_id/line_items/apply_aliases` with at least one price book entry with a `short_code` and at least one matching line item — redirects to the estimate edit page; matched line items have `exterior_material_id` set.
- `POST /estimates/:estimate_id/line_items/apply_aliases` unauthenticated — redirects to login.
- `POST /estimates/:estimate_id/line_items/import` with a price book entry that has a `short_code` — the flash notice contains the matched and unmatched counts.
- `POST /estimates/:estimate_id/line_items/import` with an ambiguous match (description contains two short codes) — the flash notice includes the ambiguous count.

### End-to-End Tests

**Short code assignment and auto-population flow (`spec/system/material_alias_spec.rb`):**

1. Estimator visits the price book page for an estimate. Clicks "Edit" on a material row. The "Short Code" field is present. Types `PL1`. Saves. The price book index shows `PL1` next to the material name.
2. Estimator imports a CSV containing a product named `"PL1 Base Cabinet"`. After import, the estimate page shows the new line item without a "Needs review" badge (material was auto-assigned).
3. Estimator imports a CSV containing a product named `"Unknown Material"` (no short code in the price book matches this name). After import, the estimate page shows the new line item with a yellow "Needs review" badge. If the estimator manually assigns a material to that line item, the badge remains (manual assignment does not clear the badge — only a matching short code in the description does).
4. Estimator edits the price book, assigns short code `SS5` to a second material, then clicks "Apply short codes to all line items." A flash notice confirms the matched and unmatched counts. The previously unmatched line item that is now resolved no longer shows the "Needs review" badge (assuming its description contained `SS5`).
5. Estimator attempts to assign short code `PL1` to a second material (same estimate). Saves. A validation error is shown and the short code is not saved.

---

## Out of Scope

- Fuzzy / approximate alias matching (e.g., Levenshtein distance). Only exact substring matching is in scope.
- LLM-based product name interpretation or summarization.
- Short code templates that can be saved and reused across estimates (short codes are per-estimate; cross-estimate reuse is a future feature).
- Automatic detection and suggestion of short codes from imported CSV product name patterns.
- Assigning different aliases to different material slots on the same line item (one alias per line item; it populates all primary slots with the same material).
- Slot-specific alias mapping (e.g., `PL1` for exterior but `PL2` for interior on the same item). All primary slots receive the same matched material.
- Banding and locks alias assignment — banding has no `_qty` column and locks resolves by role; both are out of scope for alias auto-population.
- Asana / external project management sync.
- PDF output changes.
- Any changes to the global materials library (`/materials`) — short codes live only on `estimate_materials`, not on `materials`.

---

## Open Questions

| OQ | Question | Decision |
|----|----------|----------|
| OQ-B | Should hardware slots (`drawers_material_id`, `pulls_material_id`, `hinges_material_id`, `slides_material_id`) also be auto-assigned? | **No — confirmed.** Only the four primary slots (exterior, interior, interior2, back) are assigned. Hardware slots use categorically different materials and should remain null for manual assignment. Slot-specific mapping is a future feature (see Out of Scope). |
| OQ-C | Should "Apply short codes" overwrite existing slot assignments or only fill null slots? | **Overwrite — confirmed.** The action unconditionally overwrites all four primary material FK slots on matched line items regardless of current value. This produces a deterministic, re-runnable clean state. Fill-only would silently skip previously-assigned rows and make re-runs unreliable. |

**Resolved:**
- ~~OQ-A~~ — Column named `short_code` (not `alias`) to avoid Ruby reserved keyword conflict. Resolved before implementation.
- ~~OQ-D~~ — Longest-match strategy adopted. Service sorts `@code_entries` by `short_code.length DESC`. Documented in unit tests.

---

## Dependencies

- SPEC-021 (CSV Import for Estimate Line Items) — `LineItemCsvImporter` service is extended by this spec. Status: done.
- SPEC-014 (Materials Rework) — `estimate_materials` table and `EstimateMaterial` model must exist. Status: done.
- SPEC-011 (Line Item Grid) — `LineItem` model with `exterior_material_id` and related FK columns must exist. Status: done.
