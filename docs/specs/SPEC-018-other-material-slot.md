# Spec: Other Material Slot — Combobox + Qty (Replaces Flat Cost Field)

**ID:** SPEC-018
**Status:** done
**Priority:** medium
**Created:** 2026-04-27
**Author:** pm-agent

---

## Summary

The line item form currently has an "Other Material Cost" number field where users enter a flat dollar amount per unit. This feature replaces that field with a structured material slot — a plain `collection_select` (matching the pattern of the 8 existing named slots) paired with a qty field — so cost is calculated as `other_qty × cost_with_tax` from the estimate's price book rather than being typed manually. The combobox is populated from ALL `estimate_materials` for the estimate, unfiltered by category. The existing `other_material_cost` column is kept in the schema as a legacy fallback; it is not dropped in this spec.

---

## User Stories

- As an estimator, I want to select an "other" material from the estimate's price book and enter a quantity, so that the per-unit cost is calculated automatically and stays in sync when the price book price changes.
- As an estimator, I want the Other slot to behave exactly like the Exterior, Interior, and other named slots, so that I do not have to remember a different interaction pattern.
- As an estimator, I want existing line items that have a legacy `other_material_cost` value to continue to calculate correctly until I update them, so that no historical estimate data is silently lost.

---

## Acceptance Criteria

1. Given the database schema, when a migration runs, then `line_items` has two new columns: `other_material_id` (bigint, nullable, FK to `estimate_materials` with `ON DELETE SET NULL`) and `other_qty` (decimal `precision: 10, scale: 4`, nullable). The existing `other_material_cost` column is still present and unchanged.

2. Given the line item edit form, when the page renders, then the "Other Material Cost" number field is replaced by: (a) a plain `collection_select` for `other_material_id` populated with ALL `estimate_materials` for the estimate (unfiltered by category), and (b) a qty text field using `formula-input` controller, laid out in the same 12-column grid row as the other 8 named slots. No Tom Select / `material_combobox_controller` is used.

3. Given a line item with `other_material_id` set to a valid `estimate_material` and `other_qty` set to a positive decimal, when `EstimateTotalsCalculator#call` runs, then `material_cost_per_unit` for that line item includes `other_qty.to_d * estimate_materials_by_id[other_material_id]&.cost_with_tax.to_d` via the following conditional (and the legacy `other_material_cost` branch is skipped):

   ```ruby
   if li.other_material_id.present?
     material_cost_per_unit += li.other_qty.to_d *
       estimate_materials_by_id[li.other_material_id]&.cost_with_tax.to_d
   else
     material_cost_per_unit += li.other_material_cost.to_d
   end
   ```

4. Given a legacy line item where `other_material_id` is nil and `other_material_cost` is a non-zero decimal, when `EstimateTotalsCalculator#call` runs, then that line item's `material_cost_per_unit` still includes `other_material_cost.to_d` (legacy fallback via the `else` branch of the conditional in AC-3).

5. Given the line item controller, when a create or update request is submitted, then `other_material_id` and `other_qty` are accepted in strong params. `other_material_cost` remains in strong params as a legacy passthrough and is not removed.

6. Given the `LineItem` model's `material_ids_belong_to_estimate` validation (or equivalent `MATERIAL_ID_COLUMNS` list), when `other_material_id` is present, then it is validated as belonging to the correct estimate — the same check applied to the 8 existing slot IDs. A crafted form post with an `other_material_id` from a different estimate must be rejected. `MATERIAL_ID_COLUMNS` is extended to include `:other_material_id`.

7. Given an i18n-complete form, when the Other slot label and any new UI strings are rendered, then they use `t()` lookup keys under `line_items.form` in `en.yml` — no hardcoded English strings appear in the view. The slot label key is `line_items.form.material_slot_other` ("Other"). The existing `other_material_cost_label` key under `line_items.form` is removed from `en.yml` when the legacy number field is deleted.

---

## Technical Scope

### Data / Models

**Migration** (`line_items`):
- Add `other_material_id` bigint nullable, FK to `estimate_materials(id)` with `ON DELETE SET NULL`.
- Add `other_qty` decimal `precision: 10, scale: 4`, nullable.
- Do not touch `other_material_cost`.

**`LineItem` model**:
- Add `belongs_to :other_material, class_name: "EstimateMaterial", foreign_key: :other_material_id, optional: true`.
- Add `:other_material_id` to `MATERIAL_ID_COLUMNS` so the existing `material_ids_belong_to_estimate` validation covers it automatically.

### API / Logic

**`EstimateTotalsCalculator`**:
- Replace `material_cost_per_unit += li.other_material_cost.to_d` with the following conditional. This prevents double-counting while both columns coexist and preserves correct calculation for legacy records:

  ```ruby
  if li.other_material_id.present?
    material_cost_per_unit += li.other_qty.to_d *
      estimate_materials_by_id[li.other_material_id]&.cost_with_tax.to_d
  else
    material_cost_per_unit += li.other_material_cost.to_d
  end
  ```

**`LineItemsController`**:
- Add `:other_material_id` and `:other_qty` to `SHARED_LINE_ITEM_PARAMS`. Keep `:other_material_cost`.

### UI / Frontend

**`app/views/line_items/_form.html.erb`**:
- Remove the "Other Material Cost" `number_field` block (the `<div class="mt-4 pt-4 border-t ...">` section at the bottom of the Materials card).
- Add a new slot row in the same `grid grid-cols-12` layout as the 8 named slots, positioned consistently with the other named material slots (not as a footer). The row contains:
  - Col 1: slot label via `t("line_items.form.material_slot_other")`.
  - Col 2–7: `collection_select :other_material_id` populated from ALL `estimate_materials` for the estimate (no category filter), with `include_blank: "— none —"` and the same display format as other slots (`"#{em.material.name} ($#{number_with_precision(em.quote_price, precision: 2)})")`). This is a plain Rails `collection_select` — no Tom Select / `material_combobox_controller`.
  - Col 8–11: `text_field :other_qty` with `data: { controller: "formula-input", action: "blur->formula-input#evaluate" }` and `inputmode: "decimal"`, matching the pattern of other qty fields.

**`config/locales/en.yml`**:
- Under `line_items.form`: add `material_slot_other: "Other"`.
- Create the following block (it does not currently exist in `en.yml` and must be created, not extended):

  ```yaml
  activerecord:
    attributes:
      line_item:
        other_material_id: "Other Material"
        other_qty: "Other Qty"
  ```

### Background Processing

None.

---

## Test Requirements

### Unit Tests

**`spec/models/line_item_spec.rb`**:
- `other_material_id` column exists with correct type and is nullable.
- `other_qty` column exists with correct type and is nullable.
- `other_material_cost` column still exists.
- `belongs_to :other_material` association is `optional: true`.
- `material_ids_belong_to_estimate` rejects an `other_material_id` that belongs to a different estimate.

**`spec/services/estimate_totals_calculator_spec.rb`**:
- When `other_material_id` is set and `other_qty` is 2, and `cost_with_tax` is 5.00, `material_cost_per_unit` includes 10.00.
- When `other_material_id` is nil and `other_material_cost` is 7.50 (legacy), `material_cost_per_unit` includes 7.50.
- When both `other_material_id` is nil and `other_material_cost` is 0, other cost contributes 0.
- When `other_material_id` is set on a line item but the corresponding `estimate_material` is not present in `estimate_materials_by_id` (e.g. removed from the price book), then that slot contributes 0 to `material_cost_per_unit` (the safe-navigation `&.cost_with_tax.to_d` returns 0.0). Assert this explicitly.

### Integration Tests

**`spec/requests/line_items_spec.rb`**:
- POST to create a line item with `other_material_id` and `other_qty` params saves both fields on the record.
- PATCH to update a line item with `other_material_id` and `other_qty` updates both fields.
- PATCH with an `other_material_id` belonging to a different estimate returns `422` and does not save.
- POST to create a line item with an `other_material_id` belonging to a different estimate is rejected with the same `material_ids_belong_to_estimate` validation error.

### End-to-End Tests

**`spec/system/line_items_spec.rb`** (one new scenario):
- Given an estimate with any material in its price book (quote price $10.00, estimate tax rate 0%), when a user opens the line item edit form, selects that material in the Other slot select, enters qty `3`, and saves, then assert `expect(page).to have_text('$30.00')` within the line item card, confirming the calculator's `non_burdened_total` includes the other material cost.

---

## Out of Scope

- Dropping the `other_material_cost` column — that is a follow-on cleanup spec once all line items have been migrated to the new slot pattern.
- Changes to the price book UI — any material can be used as an "other" item; no special category or flow is needed.
- Migrating existing `other_material_cost` data to the new slot automatically — users will update affected line items manually.
- The `products` table has its own `other_material_cost` column; `Product#apply_to` copies it into new line items via the legacy column. This is not touched in SPEC-018 — new line items created from a product template will have `other_material_cost` populated (handled by the calculator fallback) and `other_material_id` blank. Updating `apply_to` is a follow-on task.
- Multiple repeating "other" slots — single slot only, matching the single-slot pattern of the 8 named slots.
- Any change to the Locks slot.

---

## Open Questions

All open questions are resolved. No blocking questions remain.

1. **[CLOSED]** Category filtering: do NOT add `"other"` to `materials.category`. The combobox shows ALL `estimate_materials` for the estimate, unfiltered — any material can be used as an "other" item. No changes to the `Material` model or `materials` category validation are required.

2. **[CLOSED]** Data migration: no data migration required. Existing records with `other_material_cost` values calculate correctly via the conditional fallback in the calculator (`else` branch when `other_material_id` is nil).

3. **[CLOSED]** Product `apply_to` interaction: `Product#apply_to` copies `other_material_cost` into new line items via the legacy column. New line items from a product template will have `other_material_cost` populated and `other_material_id` blank; the calculator `else` branch handles this correctly. Updating `apply_to` is deferred to a follow-on task (see Out of Scope).

---

## Dependencies

- SPEC-014 (Materials Rework — Global Library, Per-Estimate Pricing) — done. The `materials`, `estimate_materials`, and FK pattern on `line_items` this spec extends are already in place.
- SPEC-015 (Searchable Material Combobox) — done. The `material_combobox_controller` exists but is not used on the line item form material slots (plain `collection_select` is used there). No dependency on SPEC-015 for the slot UI itself.
- SPEC-016 (Formula Input Qty Fields) — done. The `formula-input` Stimulus controller is already wired to qty fields and is reused as-is for `other_qty`.
