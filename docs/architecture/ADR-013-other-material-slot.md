# ADR-013: Replace `other_material_cost` Flat Field with a Searchable Material Slot

**Status:** proposed
**Date:** 2026-04-27
**Deciders:** architect-agent


## Context

`line_items.other_material_cost` is a plain decimal that lets an estimator enter a freeform per-unit dollar amount for miscellaneous materials. It bypasses the price book entirely — tax is not applied and there is no audit trail linking the cost to a specific material.

SPEC-018 proposes replacing this with a proper material slot (material selector + quantity) identical in structure to the existing eight named slots (exterior, interior, etc.), backed by `estimate_materials`.

Two tables are directly affected:

- `line_items` — holds the current `other_material_cost` decimal and all existing `_material_id` / `_qty` slot pairs
- `products` — also has an `other_material_cost` decimal that `Product#apply_to` copies into new line items


## Decision

Replace `line_items.other_material_cost` with two nullable columns:

- `other_material_id` — bigint FK to `estimate_materials`, ON DELETE SET NULL
- `other_qty` — decimal(10,4), nullable

The existing column is retained (not dropped) until confirmed that no production data needs migrating. Dropping it is a follow-on migration after data verification.

`products.other_material_cost` is left unchanged in this spec. A product template carries a default cost, not a material reference. The apply_to copy of `other_material_cost` becomes a dead write once the line item no longer uses that column — the spec must explicitly address what (if anything) a product should pre-fill for the other slot.

The combobox is populated from ALL `estimate_materials` for the estimate with no role filter. No new role value or category filter is introduced.

The `EstimateMaterial::ROLES` constant is extended to add `"other"` only if filtering is required — based on the decision below, it is not.


## Rationale

### Question 1 — Category column: is it needed?

`materials.category` already exists and is validated as `%w[sheet_good hardware]`. It describes the physical nature of the material globally; it does not describe its role on a specific estimate or line item.

`estimate_materials.role` currently has one value: `"locks"`. Locks uses role because it has no `_material_id` FK — the calculator resolves it by scanning for the single locks entry by role. Every other slot resolves by explicit FK. The "other" slot will have an explicit FK (`other_material_id`), so it does not need a role value for resolution.

The key question is whether filtering is needed in the UI: should the "Other" combobox show only materials the estimator has flagged as "other-type" items, or all estimate materials?

Any material can legitimately be an "other" cost on any job. Restricting the list by role or category would force the estimator to first tag a material before they can use it in the other slot — added friction with no correctness benefit. Show all estimate materials; no new category or role value is needed.

### Question 2 — Migration strategy

The proposed approach is correct: add `other_material_id` and `other_qty` as nullable columns alongside the existing `other_material_cost`. This is non-breaking and allows the two to coexist during transition.

Two concerns that the spec must address:

**Concern A — Calculator receiving both fields.** After migration, a line item could have both `other_material_cost` (a legacy value) and `other_material_id` set. The calculator currently adds `li.other_material_cost.to_d`. If the new FK path is also added, both would be summed — a double-count. The calculator must use one or the other, not both. The recommended approach: after the migration, zero out `other_material_cost` for any row that gets an `other_material_id` assignment. For the calculator, use the FK path when `other_material_id` is present and fall back to `other_material_cost` if not (during the transition window). Once all rows are confirmed migrated, remove the fallback and drop the column.

**Concern B — products.other_material_cost.** The `products` table also has `other_material_cost`. `Product#apply_to` copies this value into the new line item. After this change, the copied value will land in `line_items.other_material_cost` (the old column). If the old column is kept as a fallback during transition, this works. If the old column is eventually dropped, `apply_to` must be updated. This is a pre-drop concern, not a concern for this spec, but the spec should document it.

### Question 3 — Calculator change

The proposed new line is:

```ruby
material_cost_per_unit += li.other_qty.to_d * estimate_materials_by_id[li.other_material_id]&.cost_with_tax.to_d
```

This is consistent with the existing slot pattern. Edge cases:

- `other_material_id` is nil: `estimate_materials_by_id[nil]` returns nil; `nil&.cost_with_tax` returns nil; `.to_d` returns 0. Safe.
- `other_material_id` is set but the record was deleted and ON DELETE SET NULL fired: same as nil case. Safe.
- `other_qty` is nil: `.to_d` returns 0. Safe.
- `other_material_id` points to a record no longer in `estimate_materials_by_id` (should not happen given FK, but if estimate_materials is cached stale): returns 0. Acceptable.

During the transition, the calculator needs a fallback. The cleanest version:

```ruby
if li.other_material_id.present?
  material_cost_per_unit += li.other_qty.to_d * estimate_materials_by_id[li.other_material_id]&.cost_with_tax.to_d
else
  material_cost_per_unit += li.other_material_cost.to_d
end
```

This is explicit, testable, and eliminates the double-count risk.

### Question 4 — Price book UI

No filtering. The combobox is populated from `estimate.estimate_materials.includes(:material)` — the same collection already used for all other slots. The estimator adds a material to the price book first (existing workflow), then selects it in the other slot.

The UX is identical to the existing named slots: a Tom Select searchable combobox showing material name and quote price, with a "none" option. The slot label is "Other" and the qty field behaves identically to exterior/interior/etc.

No role-flagging step is required before a material can appear in the other slot. This matches the existing experience for all other slots.


## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Add `role = "other"` to EstimateMaterial and filter combobox | Provides an explicit tag so estimators can see which materials they have flagged as "other" | Adds friction (must tag before use); any material can be "other" on any job; locks is the only precedent for role-based filtering, and it exists only because locks has no FK | No correctness or UX benefit; increases workflow steps |
| Add `category` column to `materials` for "miscellaneous" | Categorise materials globally | `materials.category` already exists and means physical type (sheet_good / hardware), not estimate role | Overloads the existing category semantics; would require a third category value |
| Keep `other_material_cost` as-is | No migration work | Tax not applied; no audit trail; does not link to the price book | Does not meet the SPEC-018 requirement |
| Drop `other_material_cost` immediately in the same migration | Cleaner schema | Destroys existing data; no transition window | Unsafe for any estimate with an existing other_material_cost value |


## Consequences

### Positive

- "Other" materials now flow through the price book: tax is applied consistently, costs are auditable.
- The line item form is uniform — all material slots (including "other") use the same combobox + qty pattern.
- The calculator change is a minimal, patterned addition consistent with existing slot handling.
- The `LineItem#material_ids_belong_to_estimate` validation generalises naturally: `other_material_id` should be added to `MATERIAL_ID_COLUMNS` (or an equivalent check) so the existing ownership guard covers it.

### Negative

- Two columns (`other_material_cost` and `other_material_id`) coexist temporarily, requiring the transition fallback in the calculator and a data migration plan.
- `products.other_material_cost` becomes semantically orphaned once `line_items.other_material_cost` is dropped. This must be resolved in a future spec before the old column is dropped.

### Risks

- **Double-count during transition.** If a line item has both `other_material_cost` set and `other_material_id` set and the calculator sums both, the total is wrong. Mitigation: the conditional fallback in the calculator (see Implementation Notes), plus a data migration that zeroes `other_material_cost` when setting `other_material_id`.
- **products.apply_to regression.** If the old column is dropped before `Product#apply_to` is updated, applying a product template will silently write to a non-existent column (ActiveRecord will raise on save). Mitigation: update `apply_to` before or in the same migration that drops `other_material_cost`.


## Implementation Notes

**Migration (non-destructive):**

```ruby
add_column :line_items, :other_material_id, :bigint
add_column :line_items, :other_qty, :decimal, precision: 10, scale: 4
add_foreign_key :line_items, :estimate_materials,
                column: :other_material_id, on_delete: :nullify
add_index :line_items, :other_material_id
```

Do not drop `other_material_cost` in this migration.

**Model:**

Add to `LineItem`:

```ruby
belongs_to :other_material, class_name: "EstimateMaterial",
           foreign_key: :other_material_id, optional: true
```

Add `:other_material_id` to `MATERIAL_ID_COLUMNS` so the existing `material_ids_belong_to_estimate` validation covers it automatically.

**Calculator (transition-safe):**

Replace the current `material_cost_per_unit += li.other_material_cost.to_d` line with:

```ruby
if li.other_material_id.present?
  material_cost_per_unit += li.other_qty.to_d *
    estimate_materials_by_id[li.other_material_id]&.cost_with_tax.to_d
else
  material_cost_per_unit += li.other_material_cost.to_d
end
```

**Form:**

Add the "Other" row to the materials grid in `_form.html.erb` using the same Tom Select combobox as the other slots (per SPEC-015 pattern). The row is positioned after slides and before banding, or after the existing named slots — developer's choice based on visual grouping. Include a qty field (same formula-input Stimulus controller).

**Controller permit list:**

Add `:other_material_id` and `:other_qty` to the `line_item_params` strong parameters permit list.

**products.other_material_cost (deferred):**

Do not change the `products` table or `Product#apply_to` in this spec. Document the orphan as a follow-on task. The follow-on should either: (a) add an `other_qty` column to `products` as a template default and update `apply_to` to copy it, or (b) remove `other_material_cost` from `products` if the field is unused after the line item column drop.
