# ADR-010: Restore Per-Estimate Materials Price Book; Reframe Product Catalog as Template Only

**Status:** accepted
**Date:** 2026-04-13
**Deciders:** architect-agent

Supersedes: ADR-009 (Product Catalog — Data Model and Line Item Integration)
Amends: ADR-008 (Estimating Module Refactor) — the material slot and line item FK decisions from ADR-008 are reinstated

---

## Context

### The original workflow (the Excel template)

The shop's estimating spreadsheet has two distinct structural areas:

**Tab 2 — Per-estimate materials price book.** Before pricing any cabinets, the estimator enters all raw materials for this specific job: sheet goods (PL1–PL6 and named MEL/veneer variants) and hardware (hinges, pulls, slides, banding, etc.) with the prices from this job's supplier quotes. A slot named `PL1` might be "Maple Plywood 3/4" at $68/sheet on one job and "MDF 3/4" at $32/sheet on another. The slot identifiers are stable; the prices are job-specific.

**Tab 1 — The product grid.** Each row is one finished product (e.g., "Base 2-Door"). Columns D through AW encode which material slot each component uses and how many, plus labor hours per category (detail, mill, assembly, customs, finish, install) and equipment. The estimator pastes rows from takeoff software (qty, description, unit) and fills in the material/labor columns. The grid reads prices from Tab 2; the estimator never enters dollar amounts on Tab 1 except as freeform overrides.

This two-tab structure is the load-bearing design insight: **material pricing is a property of the job, not the product.**

### What SPEC-010 and ADR-008 got right

SPEC-010 built the per-estimate materials price book correctly: a `materials` table with `estimate_id`, `slot_key` (e.g., `"PL1"`, `"HINGE3"`, `"BALTIC_DOVETAIL"`), `quote_price`, and `cost_with_tax`. Line items referenced materials via `<component>_material_id` FK columns. The `EstimateTotalsCalculator` resolved costs by loading materials indexed by id, then multiplying component quantity by `material.cost_with_tax`. This design mirrors the actual spreadsheet workflow precisely.

### What SPEC-013 and ADR-009 got wrong

SPEC-013 replaced the per-estimate price book with flat `<slot>_unit_price` columns stored directly on `line_items` and on the `products` catalog. The rationale given was simplification: eliminate seeding, eliminate the `cost_with_tax` recalculation callbacks, and allow the calculator to operate with a single LaborRate query.

This rationale optimized for implementation simplicity at the cost of domain correctness. The consequence is a workflow break:

- An estimator building an estimate cannot enter the job's supplier quote prices in one place and have all product rows pick them up automatically. Instead, they must enter a unit price for each material component on every line item individually.
- A "Base 2-Door" cabinet uses exterior plywood. The product catalog stores a `exterior_unit_price`. But what that plywood costs depends on this job's species choice, panel size, and supplier quote. A global catalog price for "exterior plywood" is wrong by design — it will be stale the moment a supplier changes prices or the shop changes species.
- If a job uses the same plywood on forty cabinet rows, SPEC-013's approach requires that price to be set (or overridden) on all forty line items. The whole purpose of Tab 2 in the spreadsheet is to enter it once.
- The price embedded on the product catalog will diverge from market reality. The shop has no mechanism to reprice a job's materials without editing every line item.

The SPEC-013 calculator simplification is also overstated: the ADR-008 calculator required only two queries (materials by estimate id, labor rates). The SPEC-013 calculator reduces that to one. This is not a material performance gain at the record volumes this app will see.

### The correct role of a product catalog

The value of the catalog is saving the estimator from filling in columns D through AW from scratch on every common product. The catalog should pre-fill: which material slot category each component uses (exterior sheet good, interior sheet good, pulls hardware, etc.), default quantities for each component, and default labor hours. It does not and cannot know what any material costs on a given job. Prices come from the job's Tab 2.

---

## Decision

**Restore the per-estimate materials price book** as the authoritative source of material pricing. All material costs on line items must resolve through FK references to per-estimate `materials` rows, not from inline unit price columns.

**Reframe the product catalog** as a template of slot-type hints, default quantities, and default labor hours only. Remove all `_unit_price` columns from `products`. The catalog pre-fills the structure of a line item; the per-estimate price book fills in the costs.

---

## Rationale

Material cost is a job-scoped variable. It changes between estimates, changes mid-job if a supplier adjusts pricing, and varies by species, grade, and panel dimension. Storing it on a global product record or inline on a line item makes it impossible to reprice all products on a job without editing every row. The two-tab spreadsheet structure exists precisely because the shop discovered this the hard way over years of use.

Restoring the price book accepts two costs: introducing the global `materials` library and `estimate_materials` join table, and restoring the `cost_with_tax` recalculation callback when `tax_rate` changes. Both are well-understood patterns with negligible performance impact at this record volume. The tradeoff is: a richer data model in exchange for correct domain behavior. This is the correct tradeoff. The slot_key / auto-seed design from ADR-008 is not restored — the library-first model is strictly better: the estimator curates materials rather than working around a fixed constant list.

The product catalog still provides value as a template. Its role is narrowed to slot-type hints (which material category does this component typically use), default quantities, and labor hours. It does not know prices. This is a clean and honest model.

---

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Keep SPEC-013 flat unit prices on line items (current state) | Simpler calculator (one query); no seeding; fewer callbacks | Estimator must reprice every line item individually; cannot update material prices job-wide; catalog prices go stale immediately; breaks the Tab 2 workflow entirely | Domain-incorrect; breaks the fundamental workflow the spreadsheet embodies |
| Global material rate table shared across all estimates | Enter prices once; no per-estimate seeding | A "PL1" price shared across all jobs is wrong — prices differ by job, supplier quote, and species; would need overrides everywhere, recreating the per-estimate book anyway | Same problem as flat columns; material cost is job-scoped, not global |
| JSONB column on estimates for material prices | Flexible; no separate table | No FK integrity; calculator must parse JSON; no column-level type safety; more complex to query and test | Separate table with typed columns is simpler and more correct |
| Keep SPEC-013 with a UI to bulk-update line item prices | Could partially mitigate the workflow break | Adds a new UI surface to work around a data model problem; the workaround is more complex than just restoring the correct model | Fixing the model is simpler than engineering around a wrong model |
| Restore materials table but also keep unit_price on line items as a cache | Might allow calculator to avoid the materials join | Two sources of truth for material price; cache invalidation required; adds complexity with no benefit | Single source of truth (materials table) is simpler and correct |

---

## Consequences

### Positive

- The two-tab workflow of the spreadsheet is honored: enter job material prices once in Tab 2, all product rows resolve costs automatically.
- Repricing a job's materials (new supplier quote, species change) requires editing the materials price book only; all line item totals update automatically via `cost_with_tax`.
- Product catalog entries are stable and honest: they contain slot defaults and labor hours, not prices that go stale.
- Tax rate changes on the estimate cascade correctly to all material costs via a single SQL update (already designed in ADR-008).

### Negative

- Three new tables are introduced: global `materials` library, `estimate_materials` (per-estimate pricing), `material_sets`, and `material_set_items`. The `after_save :recalculate_material_costs` callback is restored on `Estimate`; the `after_create :seed_materials` callback is NOT restored (no auto-seeding in the new design).
- The `EstimateTotalsCalculator` must load `estimate_materials` by id (two queries: estimate_materials, labor rates) instead of one.
- The `products` table becomes narrower (removing `_unit_price` columns). This is a schema change relative to the current SPEC-013 state.
- Estimators must explicitly build the estimate's material list (from the library or by creating new entries) before assigning materials to line items. There is no auto-seeded starting set.
- More developer work to migrate from the current SPEC-013 schema to the correct schema.

### Risks

| Risk | Mitigation |
|------|-----------|
| Estimator forgets to add materials before assigning them to line items | Materials setup banner on the estimate show page; banner disappears once at least one `estimate_materials` row exists |
| `cost_with_tax` on an `estimate_materials` record goes stale if `tax_rate` changes | `after_save :recalculate_material_costs` on Estimate (single SQL UPDATE across all `estimate_materials` for the estimate, not a per-record loop) |
| `before_save :compute_cost_with_tax` fires a query to load the estimate | Ensure `estimate` is preloaded on `EstimateMaterial` before save; `belongs_to :estimate` handles this when built through `estimate.estimate_materials.build` |
| Line item references an `estimate_materials` record from a different estimate | FK is `estimate_materials.id`; a validation or DB constraint should confirm the referenced row belongs to the same estimate |
| Soft-deleting a library material that is in active use on estimates | Blocked at the model layer — validate presence of `estimate_materials` rows before allowing discard; return a user-facing validation error |

---

## Data Model

### `materials` table — global library (SPEC-014 addition)

This replaces the per-estimate-only design. All materials now exist first in a shared global library. Per-estimate pricing lives in `estimate_materials` (see below).

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| name | string NOT NULL | e.g. "Maple Plywood 3/4" |
| description | string | additional detail; searchable alongside name |
| category | string NOT NULL | "sheet_good" or "hardware" |
| unit | string | e.g. "sheet", "each" |
| default_price | decimal(12,4) NOT NULL default 0 | set on creation; updated only via Materials CRUD — never auto-updated from estimate activity |
| discarded_at | datetime | NULL = active; non-NULL = soft-deleted (discard gem pattern) |
| created_at / updated_at | datetime | |

Search is performed across both `name` and `description` columns.

Soft delete behaviour: setting `discarded_at` archives the record. A material that has any associated `estimate_materials` rows must be blocked from soft deletion (model validation error returned to the UI — do not raise an exception). Hard delete is not supported. Any logged-in user may create, edit, or soft-delete materials (RBAC is out of scope for this phase).

No duplicate detection or fuzzy matching — the team manages duplicates manually via the Materials CRUD.

### `estimate_materials` table — per-estimate pricing

Replaces the ADR-008/SPEC-010 `materials` table. The slot_key / seeded-rows model is retired; instead every row references a global library entry.

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| estimate_id | bigint NOT NULL FK → estimates ON DELETE CASCADE | |
| material_id | bigint NOT NULL FK → materials | never nullable; all materials enter via the library |
| quote_price | decimal(12,4) NOT NULL default 0 | this job's price, defaulted from `material.default_price` on creation; estimator may override |
| cost_with_tax | decimal(12,4) NOT NULL default 0 | stored computed value: `quote_price * (1 + tax_rate)` (or `quote_price` if estimate.tax_exempt) |
| created_at / updated_at | datetime | |

Unique index: `(estimate_id, material_id)` — one row per material per estimate.

Display fields (name, description, category, unit) are not denormalized onto `estimate_materials`; they are joined from the `materials` library at query time.

Note: the `slot_key`, `category` (on the per-estimate row), and `label` columns from the ADR-008 `Material::SLOTS` design are retired. Category and display information live on the global `materials` record.

### Material Sets (`material_sets` + `material_set_items` tables)

A named, reusable grouping of library materials. Any logged-in user may create, edit, or delete sets (RBAC out of scope).

**`material_sets`**

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| name | string NOT NULL | display name for the set |
| created_at / updated_at | datetime | |

**`material_set_items`**

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| material_set_id | bigint NOT NULL FK → material_sets ON DELETE CASCADE | |
| material_id | bigint NOT NULL FK → materials | |
| created_at / updated_at | datetime | |

No price is stored on the set or its items — prices always come from the library's `default_price` at the time the set is applied to an estimate.

**Applying a set to an estimate:** for each `material_set_item`, create an `estimate_materials` row with `quote_price` defaulted from `material.default_price`. If an `estimate_materials` row already exists for that `material_id` on the estimate (same unique index), skip it — no duplicate rows, no overwrite of an existing `quote_price`. Unused materials on an estimate (no line items referencing them) have zero effect on pricing and can be left in place.

### `line_items` table changes from current SPEC-013 state

**Remove** the ten `<slot>_unit_price` columns and the ten `<slot>_description` columns (exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides, locks — both `_description` and `_unit_price` for each).

**Add back** the nine `<component>_material_id` FK columns pointing to `estimate_materials`, with `ON DELETE SET NULL`:
- `exterior_material_id`, `interior_material_id`, `interior2_material_id`, `back_material_id`, `banding_material_id`, `drawers_material_id`, `pulls_material_id`, `hinges_material_id`, `slides_material_id`

These FKs reference `estimate_materials.id`, not `materials.id` directly, so the resolved `cost_with_tax` for this estimate is always used.

Note: `locks` does not get a `_material_id` FK column. The LOCKS price is resolved at calculation time by looking up the estimate's LOCKS entry in `estimate_materials`. `locks_qty` stays on line_items.

**Remove** `locks_description` and `locks_unit_price` from `line_items`.

**Keep** all `<slot>_qty` columns: `exterior_qty`, `interior_qty`, `interior2_qty`, `back_qty`, `drawers_qty`, `pulls_qty`, `hinges_qty`, `slides_qty`, `locks_qty`. Banding has no qty column (per ADR-008 Decision 2 — banding is an on/off selection, cost applied at 1x per unit).

**Keep** `product_id` nullable FK to `products` (display/audit only; ON DELETE SET NULL). Keep `other_material_cost`, all labor hour columns, `equipment_hrs`, `equipment_rate`, `description`, `quantity`, `unit`, `position`, `estimate_id`.

### `products` table changes from current SPEC-013 state

**Remove** all ten `<slot>_unit_price` columns (exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides, locks).

**Remove** all ten `<slot>_description` columns.

**Add** per-slot `<slot>_slot_type` hint (optional — see Open Questions): a string indicating which material slot category this component typically uses (e.g., `"sheet_good"` or `"hardware"`). This hint allows the pre-fill UI to default the material selector to the appropriate category. If not added now, the estimator must choose the slot manually from the estimate's available materials.

**Planned enhancement (not in scope for SPEC-014):** The product catalog currently pre-fills slot-type hints (category: sheet_good vs hardware), qty defaults, and labor hour defaults. Suggesting specific materials from the global library for each product slot — so that applying a product can also auto-populate `estimate_materials` rows — is a planned enhancement deferred to a future spec.

**Keep** all `<slot>_qty` columns: these are the default quantities that `apply_to` copies into the line item. Keep all labor hour columns (`detail_hrs`, `mill_hrs`, `assembly_hrs`, `customs_hrs`, `finish_hrs`, `install_hrs`), `equipment_hrs`, `equipment_rate`, `other_material_cost`, `name`, `category`, `unit`.

### What `Product#apply_to(line_item)` does after this change

It copies only: `<slot>_qty` values for the nine component slots (not descriptions, not unit prices); all labor hour columns; `equipment_hrs`, `equipment_rate`, `other_material_cost`, `unit`. It does NOT copy any `_material_id` FK — the estimator must assign which material slot to use for each component, from the estimate's price book. The product's `_qty` defaults tell the estimator how many units of each material this product type typically uses.

This is the honest version of the method: it pre-fills the quantities and labor hours, but the price book assignments are a job-level decision.

---

## Calculator

`EstimateTotalsCalculator` loads per-estimate pricing from `estimate_materials`:

1. Load all `estimate_materials` for the estimate (with `material` preloaded for display if needed), indexed by `id` — one query.
2. The LOCKS entry is included in step 1 and identified by joining to `materials.name` or by a designated category — the exact lookup strategy is the developer's choice (see Implementation Notes).
3. Load all `LaborRate` records, indexed by `labor_category` — one query.
4. For each line item, compute `material_cost_per_unit`:

```
sum over nine component slots of:
  (component_qty.to_d * estimate_materials_by_id[component_material_id]&.cost_with_tax.to_d)
+ (locks_qty.to_d * locks_estimate_material&.cost_with_tax.to_d)
+ banding_estimate_material&.cost_with_tax.to_d   (no qty multiplier — 1x per unit)
+ other_material_cost.to_d
```

All arithmetic is BigDecimal. Nil material_id or nil record contributes zero (safe navigation + `.to_d`).

5. All other calculator logic (labor subtotals, equipment total, burden multiplier, job-level fixed costs, COGS breakdown) is unchanged from the SPEC-012 design.

The two queries (estimate_materials + labor rates) are both loaded once per calculator instantiation, not per line item. There is no N+1 risk.

---

## UX Flow

The correct two-step estimate workflow:

**Step 1 — Set up the materials price book (Tab 2).**
The estimate show page displays a materials setup banner ("Set up material costs before adding products") that links to the materials price book page. The estimator adds materials for this job via one of two paths:

- **Library search → select:** The estimator searches the global `materials` library (across both `name` and `description`). Selecting a result creates an `estimate_materials` row with `quote_price` pre-filled from `material.default_price`. The estimator adjusts the price if this job's quote differs. The library record is not modified.
- **Not found → create new:** If the needed material is not in the library, the estimator enters it. This creates a `materials` library entry (with the entered price as `default_price`) and an `estimate_materials` row in one step.

Alternatively, the estimator may apply a **material set** to bulk-add a named group of materials in one action. Any materials already present on the estimate are skipped.

**Step 2 — Add product rows (Tab 1).**
The estimator adds line items to the estimate. When they select a product from the catalog, `Product#apply_to` pre-fills the default quantities and labor hours. For each component, the estimator selects which material to assign from the estimate's `estimate_materials` entries (a dropdown or selector). The default qty from the product pre-fill tells them "this product typically uses 1.5 sheets of exterior material" — the estimator confirms or overrides the qty and confirms or overrides which material is assigned. The calculator reads `estimate_material.cost_with_tax` from the selected record.

This flow matches the spreadsheet exactly. The catalog saves time by pre-filling the structural defaults; the per-estimate materials table is the single source of truth for all costs on this job.

---

## Migration Strategy

The app is pre-production with no user data to preserve. All estimate and line item data can be cleared.

**From the current SPEC-013 schema to the correct schema:**

1. `LineItem.delete_all`, `Estimate.delete_all` — clear existing data before altering schema.
2. Remove the ten `<slot>_unit_price` columns from `line_items`.
3. Remove the ten `<slot>_description` columns from `line_items`. (Note: `locks_description` is also removed.)
4. Add back the nine `<component>_material_id` bigint FK columns to `line_items`, all nullable, all `ON DELETE SET NULL` → `estimate_materials`.
5. Remove the ten `<slot>_unit_price` columns from `products`.
6. Remove the ten `<slot>_description` columns from `products`.
7. Create the global `materials` library table (columns: `id`, `name`, `description`, `category`, `unit`, `default_price`, `discarded_at`, timestamps). Create the `estimate_materials` table (columns: `id`, `estimate_id` FK, `material_id` FK, `quote_price`, `cost_with_tax`, timestamps) with unique index on `(estimate_id, material_id)`. Create `material_sets` (id, name, timestamps) and `material_set_items` (id, material_set_id FK, material_id FK, timestamps).
8. Add routes and controllers for `MaterialsController` (global library CRUD + soft delete), `EstimateMaterialsController` (nested under estimates), and `MaterialSetsController`.
9. Create `Material` model with soft-delete guard (block discard if `estimate_materials` rows exist), searchable scope across `name` + `description`, and `discarded_at` scope (discard gem pattern). Create `EstimateMaterial` model with `belongs_to :estimate`, `belongs_to :material`, and `before_save :compute_cost_with_tax`.
10. Restore callbacks on `Estimate`: `after_save :recalculate_material_costs, if: :saved_change_to_tax_rate?`, `after_save :recalculate_material_costs, if: :saved_change_to_tax_exempt?`. Note: `after_create :seed_materials` is NOT restored — the new design does not auto-seed. The estimator builds the estimate's material list manually (or via a material set).
11. Add `has_many :estimate_materials, dependent: :destroy` and `has_many :materials, through: :estimate_materials` on `Estimate`.

**What stays from SPEC-013:**
- `products` table (minus price columns) — keep the catalog, it is still valuable as a template.
- `ProductsController`, products views, products routes — keep all of this; only the product form changes (remove price inputs, add slot-type selectors or leave them for a future phase).
- `product_id` FK on `line_items` — keep; display/audit purpose is unchanged.
- `Product#apply_to` — keep, but the method now only copies `_qty` and labor hour columns.
- `LineItem` validations and `acts_as_list` — unchanged.

**What is removed:**
- All `_unit_price` and `_description` columns from both `products` and `line_items`.
- The calculator's flat-column material cost formula.

**Factory updates:**
- Create `:material` factory for the global library (name, description, category, unit, default_price; discarded_at nil).
- Create `:estimate_material` factory (belongs to an estimate and a material; quote_price defaults from material.default_price).
- Remove the `skip_material_seeding` trait from `:estimate` — it is no longer relevant since seeding is not automatic.
- Rewrite `:line_item` factory: remove `<slot>_unit_price` and `<slot>_description` attributes; add `<component>_material_id` associations pointing to `estimate_materials` records (create associated estimate_material and material as needed for specs that exercise cost calculations).
- Update `Product` factory: remove `<slot>_unit_price` and `<slot>_description` attributes.
- Create `:material_set` and `:material_set_item` factories.

---

## Implementation Notes for the Developer

### Do not merge calculator queries

Resist the temptation to combine the materials and labor rates queries (e.g., via a join or a custom SQL select). Keep them as two separate `index_by` queries. The code is clearer and the performance is identical at this data volume.

### The LOCKS slot resolution

LOCKS has no `_material_id` FK column on `line_items`. Since the slot_key design is retired, the calculator must identify the LOCKS `estimate_material` by some other means — for example, the estimator tags a material as serving the locks role, or the UI associates the locks component with an `estimate_materials` id stored on the estimate or line item. The exact resolution mechanism is an open implementation detail for SPEC-014. One pragmatic option: add a `role` string column to `estimate_materials` (nullable, values like `"locks"`, `"banding"`) so the calculator can find these by role. The developer should confirm the approach before building.

### Banding has no quantity

The banding component cost is `banding_material.cost_with_tax * 1` per product unit — no qty column exists. This is intentional per ADR-008 Decision 2 and the spreadsheet's treatment of banding as an on/off selection.

### `apply_to` in the controller

After this change, `Product#apply_to` only copies quantities and labor hours. The controller still calls it on line item creation when a product is selected. The estimator must still assign material slots manually from the estimate's price book. A future enhancement (not in scope for the immediate fix spec) could pre-select a default slot based on the product's slot-type hints and the estimate's available materials — but that is polish.

### Estimate layout

The materials price book UI requires a link from the estimate top bar. Restore the "Materials" button in the estimate layout (removed in SPEC-013). Restore the materials setup banner on the estimate show page.

---

## Open Questions

| OQ | Question | Status | Impact |
|----|---------|--------|--------|
| OQ-A | Should the product catalog store a `<slot>_slot_type` hint (e.g., `exterior_slot_type: "sheet_good"`) so the material selector can default to the right category? Or is the estimator expected to always choose the slot manually? | Open | If yes, add string hint columns to `products`; if no, the UI shows all estimate materials undifferentiated |
| OQ-B | Is the materials price book a prerequisite gate (estimate blocks line item entry until at least one material is set) or an advisory banner only? | Open | UX design of the materials setup banner |
| OQ-C | ~~Confirm the `Material::SLOTS` list against the actual spreadsheet~~ | **Closed — resolved by new design.** The slot_key / seeded-rows design is retired. The library is populated by the estimator, not seeded from a constant. No slot list to verify. | N/A |
| OQ-D | When a product is pre-filled into a line item, should the default `<component>_material_id` be null (estimator must choose) or should it attempt to auto-match? | Open | Affects complexity of `apply_to` and the line item form; auto-match is a planned future enhancement (see product catalog suggestions note above) |
| OQ-E | Should the materials price book be editable inline on the estimate page (Turbo Frame per row) or as a separate full-page form? | Open | UX preference; separate page is simpler |

**Roles (resolved):** Role-based access control is out of scope for this phase. All create/edit/soft-delete actions on `materials`, `material_sets`, and `material_set_items` are available to any logged-in user.
