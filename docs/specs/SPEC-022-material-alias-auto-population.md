# Spec: Material Alias and Auto-Population on CSV Import

**ID:** SPEC-022
**Status:** ready
**Priority:** high
**Created:** 2026-05-22
**Author:** pm-agent

---

## Summary

When an estimator imports a CSV takeoff (SPEC-021), each line item lands with a product name like "PL1 Base Cabinet" or "SS5 Tall Open Box." The prefix codes (`PL1`, `SS5`) are job-specific architect codes — the estimator must currently look up what each code means for this job and then manually assign every material slot on every line item. On a large estimate this takes a full day. This spec introduces a material alias field on `estimate_materials` (the per-estimate price book) so that the estimator can assign a short alias (e.g., `PL1`) to each price book entry once. During CSV import — and optionally on demand — any line item whose product name contains a known alias has its material slots auto-populated with the matching `estimate_materials` records. Line items that could not be matched are visually flagged so the estimator knows what still needs manual attention.

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
   d. Material slots that the product template leaves at zero qty (`drawers_qty`, `pulls_qty`, `hinges_qty`, `slides_qty`) are still assigned the matched alias material for those slots; the cost contribution will be zero due to zero qty.

5. Given a product name matches more than one short code in the price book (e.g., name "PL1 SS5 Cabinet" where both `PL1` and `SS5` are defined short codes), when the import runs, then the **longest-matching** short code is used for all primary slots (exterior, interior, interior2, back) and the line item is created without error; a warning is included in the import flash message indicating the ambiguous match. Longest-match is used to minimise false positives (e.g. short code `PL` would otherwise match product names containing `PL1`, `PL2`, etc.).

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

The "needs review" flag is a derived display state, not a stored column. A line item is considered unmatched if: (a) no short code from the price book appears in its `description`, and (b) the line item has no material assigned on the `exterior_material_id` slot.

### API / Logic

#### Short code matching service — `app/services/line_item_alias_matcher.rb`

Class: `LineItemAliasMatcherService`

Constructor: `initialize(estimate)`

- On initialize, load all `estimate_materials` with a non-blank `short_code`, sorted by `short_code.length DESC` (longest first) to implement longest-match semantics, into a local array: `@code_entries`.
- Longest-match ensures that a short code of `PL1` beats a short code of `PL` when both appear on the same estimate, preventing false positives.

Public method: `match(line_item)` — given a single `LineItem` instance (not yet persisted or already persisted):
1. Return `nil` immediately if `@code_entries.empty?`.
2. Downcase `line_item.description`.
3. Iterate through `@code_entries` (longest short code first); find the first entry whose `short_code.downcase` appears as a substring of the description.
4. If a match is found, assign the matched `estimate_material.id` to the line item's `exterior_material_id`, `interior_material_id`, `interior2_material_id`, and `back_material_id`.
5. Return the matched `estimate_material`, or `nil` if no match.

The caller is responsible for detecting multi-code ambiguity (more than one short code substring found in the description after longest-match selection) and recording a warning. The service itself assigns only the longest match.

Public method: `apply_to_all_line_items` — applies `match` to every line item on the estimate, saves each line item if a match was found, and returns a result struct with `{ matched: Integer, unmatched: Integer }`.

#### `LineItemCsvImporter` — extend `persist` to call short code matching

After creating each `LineItem` in the `persist` loop, instantiate (or reuse) a `LineItemAliasMatcherService` for the estimate and call `match(line_item)` before `line_item.save!`. Track how many items were matched vs. unmatched. Return these counts in the `Result` struct.

Update `Result = Data.define(:line_items_created, :matched_count, :unmatched_count, :error)`.

Update the controller flash to include the unmatched count when `result.unmatched_count > 0`: e.g., "Imported 12 line items (3 need review — no short code match found)."

#### New controller action — `apply_aliases`

Add a member-collection action under estimates:

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
2. Call `apply_to_all_line_items`.
3. Redirect to `edit_estimate_path(@estimate)` with a flash notice containing the matched and unmatched counts (i18n key: `t(".notice", matched: result[:matched], unmatched: result[:unmatched])`).

### UI / Frontend

#### Price book index — short code column and "Apply short codes" button

On `app/views/estimate_materials/index.html.erb`:

- Add a "Short Code" column to the price book table, displaying `em.short_code.presence || "—"` as a read-only badge (e.g., a small monospace pill in slate or amber) alongside the material name.
- Add an "Apply short codes to all line items" button in the page header area (near the existing "Add material" button). The button submits a POST form to `apply_aliases_estimate_line_items_path(@estimate)`. It should only be visible when at least one `estimate_material` on this estimate has a non-blank `short_code`.

#### Price book edit form — short code field

On `app/views/estimate_materials/_form.html.erb` (and the `edit` view):

- Add a text input for `short_code` below the existing `quote_price` and `role` fields.
- Label: `t(".short_code_label")` (i18n).
- Placeholder: e.g., `PL1` (i18n key).
- Show inline validation errors if uniqueness fails.

#### Estimate edit page — "Needs review" flag on line items

On the line item card partial (wherever line items are rendered on the estimate edit page):

- If a line item has `exterior_material_id` nil (no primary material assigned), render a yellow "Needs review" badge on the card. Use an i18n key: `t("line_items.card.needs_review")`.
- The badge is a visual hint only; it does not prevent the estimator from saving or editing the line item.

#### Import flash message — unmatched count

If `result.unmatched_count > 0` after import, the flash notice reads: e.g., "Imported 12 line items. 3 need review — no short code match found."
If all line items matched, the flash reads: "Imported 12 line items. All materials auto-assigned."
Use distinct i18n keys for each variant.

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
- `apply_to_all_line_items` on an estimate with 2 matched and 1 unmatched line item returns `{ matched: 2, unmatched: 1 }`.
- `apply_to_all_line_items` saves matched line items (their material slots are persisted).
- `apply_to_all_line_items` does not modify or save unmatched line items.
- When `@code_entries` is empty, `match` returns `nil` immediately without querying the database.

**`LineItemCsvImporter` (`spec/services/line_item_csv_importer_spec.rb` — additions):**
- Given an estimate with a price book entry with `short_code: "PL1"` and a CSV with a product named `"PL1 Base Cabinet"`, after import the created line item has `exterior_material_id` set to the matching estimate material.
- Given a CSV with a product named `"Unknown Material"` (no short code match), the created line item has `exterior_material_id` nil and `result.unmatched_count` is 1.
- `result.matched_count` and `result.unmatched_count` sum to `result.line_items_created`.

### Integration Tests

**`EstimateMaterialsController` (`spec/requests/estimate_materials_spec.rb` — additions):**
- `PATCH /estimates/:estimate_id/estimate_materials/:id` with a valid unique `short_code` — updates `short_code`; redirects.
- `PATCH /estimates/:estimate_id/estimate_materials/:id` with a duplicate `short_code` (same code already on another row for this estimate) — returns 422 with an error and does not update.
- `PATCH` with a blank `short_code` — succeeds (blank is allowed).

**`LineItemsController` (`spec/requests/line_items_spec.rb` — additions):**
- `POST /estimates/:estimate_id/line_items/apply_aliases` with at least one price book entry with a `short_code` and at least one matching line item — redirects to the estimate edit page; matched line items have `exterior_material_id` set.
- `POST /estimates/:estimate_id/line_items/apply_aliases` unauthenticated — redirects to login.
- `POST /estimates/:estimate_id/line_items/import` with a price book entry that has a `short_code` — the flash notice contains the matched and unmatched counts.

### End-to-End Tests

**Short code assignment and auto-population flow (`spec/system/material_alias_spec.rb`):**

1. Estimator visits the price book page for an estimate. Clicks "Edit" on a material row. The "Short Code" field is present. Types `PL1`. Saves. The price book index shows `PL1` next to the material name.
2. Estimator imports a CSV containing a product named `"PL1 Base Cabinet"`. After import, the estimate page shows the new line item without a "Needs review" badge (material was auto-assigned).
3. Estimator imports a CSV containing a product named `"Unknown Material"`. After import, the estimate page shows the new line item with a yellow "Needs review" badge.
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

| OQ | Question | Blocks progress? |
|----|----------|-----------------|
| OQ-B | Short code matching populates exterior, interior, interior2, and back slots. Should `drawers_material_id`, `pulls_material_id`, `hinges_material_id`, and `slides_material_id` also be auto-assigned? These slots often use different materials (hardware vs. sheet goods). Current decision: assign only exterior/interior/interior2/back; leave hardware slots null for manual assignment. Confirm with Blake before building. | No — default is exterior/interior/interior2/back only. Developer can make it configurable later. |
| OQ-C | On the "Apply short codes to all line items" action, should existing material slot assignments be overwritten or only filled where null? Overwriting is simpler and more predictable (re-running always gets a clean state). Fill-only is safer if the estimator has manually customized some rows. | No — current spec says overwrite; if Blake prefers fill-only, update AC#7 and the service logic before implementation. |

**Resolved:**
- ~~OQ-A~~ — Column named `short_code` (not `alias`) to avoid Ruby reserved keyword conflict. Resolved before implementation.
- ~~OQ-D~~ — Longest-match strategy adopted. Service sorts `@code_entries` by `short_code.length DESC`. Documented in unit tests.

---

## Dependencies

- SPEC-021 (CSV Import for Estimate Line Items) — `LineItemCsvImporter` service is extended by this spec. Status: done.
- SPEC-014 (Materials Rework) — `estimate_materials` table and `EstimateMaterial` model must exist. Status: done.
- SPEC-011 (Line Item Grid) — `LineItem` model with `exterior_material_id` and related FK columns must exist. Status: done.
