# ADR-008: Estimating Module Refactor — Data Model and Implementation Plan

**Status:** accepted
**Date:** 2026-04-10
**Deciders:** architect-agent

Supersedes: ADR-006 (burden total calculation), ADR-007 (phase 4 data model review)
Supersedes in part: ADR-001 (markup level), ADR-003 (real-time totals), ADR-005 (line item entry UX)

---

## Context

The estimating module was built on an incorrect conceptual model. The prior design structured the data as:

```
Estimate → EstimateSection (a named group, e.g. "Kitchen") → LineItem (one material or labor entry)
```

After reviewing the actual Excel template the shop uses, this model is wrong on two axes:

1. "Sections" (rooms) do not exist in the workflow at all. The estimating grid has no grouping layer.
2. A "line item" in the spreadsheet is not one material component or one labor entry — it is one **finished product** (e.g. "Base 2 Door"), with all its material components and all its labor categories expressed as columns on that single row.

The spreadsheet has two distinct structural areas that must be modeled:

- **Materials tab** — a per-estimate price book of raw material slots (sheet goods, hardware) with user-entered quote prices and a tax-rate-adjusted cost. The slot identifiers are fixed and known in advance (PL1–PL6, PULL1–6, HINGE1–6, SLIDE1–6, BANDING1–6, plus named slots: 1/4" MEL, 3/4" MEL G2S, BALTIC DOVETAIL, LOCKS, etc.).
- **Totals tab** — the main grid where each row is one finished product. Material quantities and types are columns on that row, as are labor hours per trade category. There is no nesting.

The prior data model also made `EstimateMaterial` use generic category/slot_number integers, which cannot express the named slots (BALTIC DOVETAIL, LOCKS) that sit outside the numbered sequences.

No production data exists. The app is pre-launch. A clean wipe and rebuild is safe and is the correct choice.

---

## Decisions

This ADR records five decisions. Each is stated first, then the rationale and alternatives follow.

### Decision 1 — Remove EstimateSection entirely; LineItem belongs directly to Estimate

`EstimateSection` is removed. `LineItem` gains `estimate_id` as its direct foreign key. The old `estimate_section_id` FK and the `estimate_sections` table are dropped.

### Decision 2 — LineItem uses flat columns for material components, not a join table

Each of the nine material component types (exterior, interior, interior_2nd, back, banding, drawers, pulls, hinges, slides) is represented as a pair of columns on `line_items`: `<component>_qty` (decimal, nullable) and `<component>_material_id` (FK to materials, nullable). Locks get only `locks_qty` (no material FK — the locks price is a fixed slot in the materials table, looked up by slot_key at calculation time). `other_material_cost` is a freeform decimal.

### Decision 3 — Calculated fields are Ruby methods only; nothing is stored

`price_ea`, `subtotal_materials`, labor subtotals, `non_burdened_total`, and `burdened_total` are computed in a service object (`EstimateTotalsCalculator`) and in model methods. No calculated column is persisted. This was the existing policy (ADR-003/ADR-006) and it is reaffirmed here.

### Decision 4 — Materials use a string slot_key, not integer slot_number; seeded per estimate

The `materials` table (replacing `estimate_materials`) uses a string `slot_key` column (e.g. `"PL1"`, `"HINGE3"`, `"BALTIC_DOVETAIL"`, `"LOCKS"`) instead of the prior `category` + `slot_number` pair. The full slot list is defined as a constant in the `Material` model. Slots are seeded on estimate creation via an `after_create` callback using `insert_all`.

`tax_exempt` is read from the client at estimate creation time and copied onto the estimate as a boolean. This is discussed under Decision 5.

### Decision 5 — tax_exempt copied to estimate at creation; tax_rate stored on estimate

`Client#tax_exempt` sets the initial value of `Estimate#tax_exempt` at creation. The estimate stores its own `tax_exempt` boolean and `tax_rate` decimal independently of the client after that point. This allows the estimator to override tax treatment per job without changing the client record, and it freezes the tax assumption at the time of quoting.

---

## Rationale

### Decision 1 — Remove EstimateSection

The spreadsheet has no grouping layer. Adding one to the data model introduced a meaningless level of indirection. Every feature that worked with line items had to navigate through a section that carried no business meaning. Removing it simplifies every query, every form, every Turbo Stream target, and every calculator path.

The one genuine grouping concern — putting the countertop quote on a separate line from cabinetry — is handled by the job-level `countertop_quote` field on `Estimate`, not by a section model.

### Decision 2 — Flat columns on LineItem

**Why not a line_item_materials join table:**

A join table would make the data model more normalized, but the spreadsheet's column grid is the user's mental model. The grid has exactly nine typed material component slots per product row; that structure does not change between jobs. Representing this as rows in a join table would require the UI to build a dynamic grid from database rows — adding complexity in the view layer (ordering, rendering, adding/removing slots) that the flat-column approach avoids entirely. The join table buys normalization at the cost of UX complexity that users did not ask for and the data does not warrant.

A flat-column table with up to ~25 material/labor columns is wide by relational norms, but it is directly readable, directly queryable without joins, and maps one-to-one with the spreadsheet grid that estimators are trained on. The table will never have millions of rows. Width is not a performance concern at this scale.

**The one legitimate concern with flat columns** is that adding a new component type requires a migration. This is acceptable because the slot structure is defined by the shop's workflow, not by software requirements, and the shop has been using the same slot structure for years.

### Decision 3 — No stored calculated fields

Storing calculated fields requires cache invalidation logic whenever any input changes — material prices, tax rates, labor rates, estimate settings, or individual line item values. In this domain every one of those inputs can change independently, making invalidation logic complex and fragile. Recalculating from source on every page load is negligible in cost at this record volume. The `EstimateTotalsCalculator` service object (established in ADR-006) is the single calculation point and remains so.

The one exception worth noting: if PDF generation turns out to be slow (Phase 6), a denormalized "snapshot" of the totals at the moment of PDF generation may be stored as a JSON column for display in the PDF only. This is deferred and not part of the current schema.

### Decision 4 — String slot_key

The prior `category` + `slot_number` integer scheme could not represent named slots like `BALTIC_DOVETAIL` or `LOCKS` that have no number. A string key is more general and more legible. The FK from `line_items` columns to `materials` references this table by surrogate `id` (not by slot_key), which is the correct FK pattern. The slot_key is a business identifier used for seeding and display, not for joining.

### Decision 5 — tax_exempt copied to estimate

The alternative is to always read `tax_exempt` from the associated client at calculation time. This is rejected because: (a) the client's tax status can change between the quoting and billing stages, (b) copying the value makes the estimate a complete snapshot of the job's terms at the time of quoting, consistent with how the spreadsheet was used (a saved .xlsx file is immutable after the fact). The estimator can manually override `tax_exempt` on an estimate if the client's status is job-specific.

---

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Keep EstimateSection as an optional grouping | Backward compatible with existing UI | Grouping layer still maps to nothing in the workflow; every calculation path still navigates a meaningless join | The concept does not exist; pretending it does adds permanent complexity |
| line_item_materials join table | Fully normalized; easy to add new component types without migrations | UI must dynamically build the nine-column grid from rows; ordering and rendering logic moves to view; no benefit at this data volume | Flat columns match the spreadsheet's mental model exactly; join table adds complexity without value |
| Store calculated totals in DB | Faster reads; snapshot history | Invalidation logic for six types of input change; stale data risk; no production volume that would justify it | Recalculate on demand is simpler and correct at this scale |
| Integer slot_number + category for materials | Matches prior design | Cannot express named slots (BALTIC_DOVETAIL, LOCKS); prior design was already wrong | String slot_key is more general and maps to the actual slot identifiers in the spreadsheet |
| Read tax_exempt from client at calculation time | No copy; always current | Estimate no longer represents a point-in-time snapshot; client status change silently changes historical quotes | Snapshot semantics are the correct choice for a job-quoting document |
| Staged migrations preserving old LineItem data | No data loss | No production data exists; old schema is wrong; preserving wrong data adds migration complexity for zero value | Clean wipe is safe and correct pre-launch |

---

## Consequences

### Positive

- The data model maps directly to the spreadsheet grid that estimators know. Onboarding friction is reduced.
- `EstimateTotalsCalculator` simplifies significantly — no section aggregation pass, no section_quantity multiplier threaded through all calculations.
- Views simplify — line items render directly from estimate, no intermediate section controller or partial layer.
- Turbo Stream DOM IDs simplify — `dom_id(@line_item)` is sufficient; no need for section-scoped IDs.
- The materials table can express every slot in the actual spreadsheet including named hardware slots.
- String slot_keys are human-readable in the database and in logs.

### Negative

- `line_items` table is wide (~35 columns). Developers must read the model carefully to understand which columns are active for a given product row. A model comment block documenting the column groups is required.
- Every new component type the shop might add in future requires a migration (though this is unlikely given years of stable slot structure).
- `materials.cost_with_tax` is a derived value. The decision of whether to store it or compute it on the fly requires a follow-up decision (see Implementation Notes).

### Risks

| Risk | Mitigation |
|------|-----------|
| `line_items` wide-table approach confuses future developers | Thorough model comment block; clear column naming convention |
| `cost_with_tax` computed incorrectly if tax_rate changes after materials are priced | Recompute cost_with_tax whenever quote_price or estimate tax_rate changes; or store as computed column (see Implementation Notes) |
| `after_create` seed on Estimate fires in all test contexts, bloating the test DB | Add `skip_material_seeding` factory trait (same pattern as ADR-007 recommendation) |
| Removing EstimateSection breaks existing UI/controller code that was built in prior phases | All estimating controllers and views must be rebuilt from scratch; auth/clients/contacts are untouched |
| Missing `tax_rate` on estimate at seeding time means `cost_with_tax` seeds as zero | Seed materials after estimate is fully initialized; seed callback must read estimate.tax_rate |

---

## Schema — Final Approved Design

### Tables to drop

- `estimate_sections`
- `estimate_materials` (replaced by `materials`)
- `catalog_items`

### Tables to rewrite

#### `estimates` — keep existing columns, add/change:

| Column | Type | Notes |
|--------|------|-------|
| client_id | bigint NOT NULL | existing |
| created_by_user_id | bigint NOT NULL | fix TD-01 type from ADR-007 |
| title | string NOT NULL | existing |
| estimate_number | string NOT NULL UNIQUE | existing |
| status | string NOT NULL default 'draft' | existing |
| notes | text | existing |
| client_notes | text | existing |
| job_start_date | date | existing |
| job_end_date | date | existing |
| tax_rate | decimal(5,4) NOT NULL default 0.08 | NEW — rate used for cost_with_tax on materials |
| tax_exempt | boolean NOT NULL default false | NEW — copied from client at creation |
| miles_to_jobsite | decimal(8,2) | existing |
| installer_crew_size | integer NOT NULL default 2 | existing; change default to 2 (per spreadsheet) |
| delivery_crew_size | integer NOT NULL default 2 | existing; change default to 2 |
| on_site_time_hrs | decimal(6,2) | existing |
| pm_supervision_percent | decimal(5,2) NOT NULL default 4.00 | existing; change default to 4 |
| profit_overhead_percent | decimal(5,2) NOT NULL default 10.00 | existing; change default to 10 |
| install_travel_qty | decimal(8,2) | NEW — job-level fixed cost row |
| delivery_qty | decimal(8,2) | NEW |
| per_diem_qty | decimal(8,2) | NEW |
| hotel_qty | decimal(8,2) | NEW |
| airfare_qty | decimal(8,2) | NEW |
| countertop_quote | decimal(12,2) | NEW |

Remove from estimates: nothing that currently exists is removed (backward compatible for existing estimate rows).

#### `materials` (new table, replaces `estimate_materials`)

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| estimate_id | bigint NOT NULL FK → estimates ON DELETE CASCADE | |
| slot_key | string NOT NULL | e.g. "PL1", "HINGE3", "BALTIC_DOVETAIL", "LOCKS" |
| category | string NOT NULL | "sheet_good" or "hardware" |
| description | string | user-entered label for the slot |
| quote_price | decimal(12,4) NOT NULL default 0 | user-entered per-estimate price |
| cost_with_tax | decimal(12,4) NOT NULL default 0 | computed: quote_price * (1 + tax_rate); stored for read performance |
| created_at / updated_at | datetime | |

Unique index: `(estimate_id, slot_key)`.

**On `cost_with_tax` storage decision:** Store it. The alternative is computing it at query time via a join to estimates to get tax_rate, which requires either a join in every material query or a separate lookup. Storing it and recomputing on save (before_save callback on Material, or a recalculate call whenever estimate.tax_rate changes) is simpler. The callback: `self.cost_with_tax = quote_price * (1 + estimate.tax_rate)`. The estimate must be preloaded (`belongs_to :estimate`) so the callback does not fire a query.

When `estimate.tax_rate` changes, all materials for that estimate must have `cost_with_tax` recomputed. Implement as: `after_save :recalculate_material_costs, if: :saved_change_to_tax_rate?` on Estimate, which calls `materials.each(&:recalculate_cost_with_tax!)` or preferably a single SQL update.

**Slot definitions:** Define a constant `Material::SLOTS` as an ordered array of hashes:

```ruby
Material::SLOTS = [
  # Sheet Goods
  { slot_key: "PL1",            category: "sheet_good" },
  { slot_key: "PL2",            category: "sheet_good" },
  { slot_key: "PL3",            category: "sheet_good" },
  { slot_key: "PL4",            category: "sheet_good" },
  { slot_key: "PL5",            category: "sheet_good" },
  { slot_key: "PL6",            category: "sheet_good" },
  { slot_key: "QTR_MEL",        category: "sheet_good", label: "1/4\" MEL" },
  { slot_key: "TH_MEL_G2S",     category: "sheet_good", label: "3/4\" MEL G2S" },
  { slot_key: "TH_MEL_PLYCORE", category: "sheet_good", label: "3/4\" MEL PLYCORE" },
  { slot_key: "TH_MEL3",        category: "sheet_good", label: "3/4\" MEL3" },
  { slot_key: "TH_MEL4",        category: "sheet_good", label: "3/4\" MEL4" },
  { slot_key: "TH_MEL5",        category: "sheet_good", label: "3/4\" MEL5" },
  { slot_key: "TH_MEL6",        category: "sheet_good", label: "3/4\" MEL6" },
  { slot_key: "ONE_MEL1",       category: "sheet_good", label: "1\" MEL1" },
  { slot_key: "ONE_MEL2",       category: "sheet_good", label: "1\" MEL2" },
  { slot_key: "ONE_MEL3",       category: "sheet_good", label: "1\" MEL3" },
  { slot_key: "VENEER1",        category: "sheet_good" },
  { slot_key: "VENEER2",        category: "sheet_good" },
  { slot_key: "VENEER3",        category: "sheet_good" },
  { slot_key: "VENEER4",        category: "sheet_good" },
  { slot_key: "VENEER5",        category: "sheet_good" },
  { slot_key: "VENEER6",        category: "sheet_good" },
  # Hardware
  { slot_key: "PULL1",          category: "hardware" },
  { slot_key: "PULL2",          category: "hardware" },
  { slot_key: "PULL3",          category: "hardware" },
  { slot_key: "PULL4",          category: "hardware" },
  { slot_key: "PULL5",          category: "hardware" },
  { slot_key: "PULL6",          category: "hardware" },
  { slot_key: "HINGE1",         category: "hardware" },
  { slot_key: "HINGE2",         category: "hardware" },
  { slot_key: "HINGE3",         category: "hardware" },
  { slot_key: "HINGE4",         category: "hardware" },
  { slot_key: "HINGE5",         category: "hardware" },
  { slot_key: "HINGE6",         category: "hardware" },
  { slot_key: "SLIDE1",         category: "hardware" },
  { slot_key: "SLIDE2",         category: "hardware" },
  { slot_key: "SLIDE3",         category: "hardware" },
  { slot_key: "SLIDE4",         category: "hardware" },
  { slot_key: "SLIDE5",         category: "hardware" },
  { slot_key: "SLIDE6",         category: "hardware" },
  { slot_key: "BANDING1",       category: "hardware" },
  { slot_key: "BANDING2",       category: "hardware" },
  { slot_key: "BANDING3",       category: "hardware" },
  { slot_key: "BANDING4",       category: "hardware" },
  { slot_key: "BANDING5",       category: "hardware" },
  { slot_key: "BANDING6",       category: "hardware" },
  { slot_key: "BALTIC_DOVETAIL",category: "hardware" },
  { slot_key: "FH_MELAMINE",    category: "hardware", label: "5/8\" MELAMINE" },
  { slot_key: "TH_MELAMINE",    category: "hardware", label: "3/4\" MELAMINE" },
  { slot_key: "LOCKS",          category: "hardware" },
].freeze
```

The developer must verify this slot list against the actual spreadsheet before writing the seed callback. Treat this list as provisional.

#### `line_items` (complete rebuild)

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| estimate_id | bigint NOT NULL FK → estimates ON DELETE CASCADE | direct FK; no section |
| description | string NOT NULL | product name e.g. "Base 2 Door" |
| quantity | decimal(10,2) NOT NULL default 1 | how many units of this product |
| unit | string NOT NULL default 'EA' | EA, LF, etc. |
| position | integer NOT NULL default 0 | acts_as_list |
| exterior_qty | decimal(10,4) | |
| exterior_material_id | bigint FK → materials nullable | |
| interior_qty | decimal(10,4) | |
| interior_material_id | bigint FK → materials nullable | |
| interior2_qty | decimal(10,4) | |
| interior2_material_id | bigint FK → materials nullable | |
| back_qty | decimal(10,4) | |
| back_material_id | bigint FK → materials nullable | |
| banding_material_id | bigint FK → materials nullable | no qty — coverage calculated from product dimensions or just a flag |
| drawers_qty | decimal(10,4) | |
| drawers_material_id | bigint FK → materials nullable | |
| pulls_qty | decimal(10,4) | |
| pulls_material_id | bigint FK → materials nullable | |
| hinges_qty | decimal(10,4) | |
| hinges_material_id | bigint FK → materials nullable | |
| slides_qty | decimal(10,4) | |
| slides_material_id | bigint FK → materials nullable | |
| locks_qty | decimal(10,4) | no material FK; price from LOCKS slot |
| other_material_cost | decimal(12,2) | freeform material cost per unit |
| detail_hrs | decimal(8,4) | hours per unit |
| mill_hrs | decimal(8,4) | |
| assembly_hrs | decimal(8,4) | |
| customs_hrs | decimal(8,4) | |
| finish_hrs | decimal(8,4) | |
| install_hrs | decimal(8,4) | |
| equipment_hrs | decimal(8,4) | |
| equipment_rate | decimal(10,2) | |
| created_at / updated_at | datetime | |

Indexes: `(estimate_id)`, `(estimate_id, position)`. All material_id FKs: `ON DELETE SET NULL` (if a material slot is removed, the line item reference nullifies rather than cascade-deleting the product row).

**Schema deviation from proposed design:** The proposed design listed `banding_material_id` with a note "no qty". This ADR retains that. Banding cost = `banding_material.cost_with_tax` per unit (or zero if null). No quantity column for banding — the spreadsheet treats banding as an on/off type selection per product, not a measured quantity.

#### `labor_rates` — keep, update default rates

Keep the existing table. Update seed data to match the spreadsheet:

| labor_category | hourly_rate |
|----------------|------------|
| detail | 65.00 |
| mill | 100.00 |
| assembly | 45.00 |
| customs | 65.00 |
| finish | 75.00 |
| install | 80.00 |

These are the rates shown in the spreadsheet. Confirm with the shop owner before first production use.

---

## Calculator — Updated Design

The `EstimateTotalsCalculator` from ADR-006 is replaced in full. The new calculator operates on a flat line item list (no sections). Its responsibilities:

1. Load all materials for the estimate indexed by `id` (one query).
2. Load all labor rates indexed by `labor_category` (one query).
3. For each line item, compute:
   - `material_cost_per_unit` = sum over all nine component slots of `(component_qty || 0) * material.cost_with_tax` + locks cost + `other_material_cost`
   - `subtotal_materials` = `material_cost_per_unit * quantity`
   - Labor subtotals per category: `hrs * labor_rate * quantity`
   - `equipment_total` = `equipment_hrs * equipment_rate * quantity`
   - `non_burdened_total` = `subtotal_materials + sum(all labor subtotals) + equipment_total`
4. Sum all line item `non_burdened_total` values → `grand_non_burdened`.
5. Compute job-level fixed costs from estimate fields (install_travel, delivery, per_diem, hotel, airfare).
6. Compute burden multiplier: `(1 + profit_overhead_percent/100) * (1 + pm_supervision_percent/100)`.
7. `burdened_total` = `grand_non_burdened * burden_multiplier + job_level_fixed_costs`.
8. Compute COGS breakdown by category (materials, shop labor, install labor, equipment, countertops).
9. Return a value object with all totals.

The two-pass section-level burden allocation from ADR-006 is removed. The simpler single-pass design is correct because there are no sections to distribute travel costs across.

All arithmetic: `BigDecimal` throughout. Labor rates and material prices arrive from the DB as `BigDecimal` (decimal columns). No `Float` anywhere in the calculator.

---

## ADRs Superseded or Modified by This Decision

| ADR | Change |
|-----|--------|
| ADR-001 (markup level) | Superseded. Markup is now only relevant for job-level freeform cost lines (other_material_cost). The per-line-item markup_percent column is removed. |
| ADR-003 (real-time totals) | Architecture pattern (Stimulus for in-form, Turbo Streams on save) is retained. The Turbo Stream targets change because there are no sections — targets are the line item row and the estimate grand total. |
| ADR-005 (line item entry UX) | Superseded. The UX is now a spreadsheet-style grid, not a freeform description + catalog autocomplete. CatalogItem is removed. |
| ADR-006 (burden total calculation) | Superseded by the updated calculator described above. Two-pass section algorithm is removed. |
| ADR-007 (phase 4 data model review) | Superseded. All schema decisions from ADR-007 are replaced by this ADR. |

---

## Implementation Notes

### Migration strategy

No production data exists. Execute in order:

1. Drop `catalog_items`, `estimate_sections`, `estimate_materials` tables.
2. Drop and recreate `line_items` with the new schema.
3. Modify `estimates`: add `tax_rate`, `tax_exempt`, `install_travel_qty`, `delivery_qty`, `per_diem_qty`, `hotel_qty`, `airfare_qty`, `countertop_quote`; update defaults for `installer_crew_size`, `delivery_crew_size`, `pm_supervision_percent`, `profit_overhead_percent`.
4. Fix TD-01 from ADR-007: `change_column :estimates, :created_by_user_id, :bigint` and drop the `default: 0`.
5. Create `materials` table.
6. Update `db/seeds.rb`: update `LaborRate` seed rates; remove any `EstimateMaterial`, `EstimateSection`, or `CatalogItem` seed code.

All migrations in a single batch on a feature branch. Run `db:schema:load` in CI rather than replaying individual migrations.

### Models to delete

- `app/models/estimate_section.rb`
- `app/models/estimate_material.rb`
- `app/models/catalog_item.rb`

### Models to create

- `app/models/material.rb` — belongs_to :estimate; before_save to compute cost_with_tax; SLOTS constant; seed callback target.

### Models to rewrite

- `app/models/estimate.rb` — remove estimate_sections and estimate_materials associations; add materials and line_items direct associations; update after_create to seed materials; add tax_exempt copying from client in before_create; update validations for new defaults.
- `app/models/line_item.rb` — complete rewrite; belongs_to :estimate directly; acts_as_list scope: :estimate; all nine material FK associations (optional: true); material cost method; labor cost method using labor_rates hash (do not call LaborRate per-item); no markup_percent.

### Controllers to delete

- `EstimateSectionsController`
- `EstimateMaterialsController` (to be rebuilt as `MaterialsController`)

### Controllers to rebuild

- `EstimatesController` — update strong params; update create action to copy tax_exempt from client.
- `LineItemsController` — complete rewrite; direct estimate scoping; Turbo Stream responses target line item row + estimate totals partial.
- `MaterialsController` (new, replaces EstimateMaterialsController) — CRUD for the estimate's materials price book.

### Turbo Stream DOM ID conventions

- Line items: `dom_id(@line_item)` → `line_item_<id>`
- Estimate totals partial: target id `estimate_<id>_totals`
- Materials grid: target id `estimate_<id>_materials`

### UX shape of the line item grid

The line item entry screen is a horizontal scrolling grid matching the spreadsheet's column layout. Each row is one product. Editing a row opens an inline form (Turbo Frame) or a slide-over panel — to be decided by the developer and confirmed with the estimator. A flat list with inline editing is the recommended starting point; a modal/panel adds latency.

The materials price book is a separate screen (tab or linked page within the estimate), not embedded in the line item grid.

### Test infrastructure

All existing system/model/request specs in `spec/models`, `spec/requests`, `spec/system` for estimating are to be deleted and rewritten from scratch. Auth, users, and client specs are untouched.

Factory changes:
- Delete `FactoryBot :estimate_section`, `:estimate_material`, `:catalog_item`, `:line_item` factories.
- Create `:material` factory.
- Rewrite `:line_item` factory with direct `estimate_id` association.
- Add `skip_material_seeding` trait to `:estimate` factory.

### Open questions to resolve before development starts

| OQ | Question | Default if not answered |
|----|---------|------------------------|
| OQ-A | Confirm slot list against actual spreadsheet — are there slots beyond what is listed in this ADR? | Use this ADR's list; amend if needed |
| OQ-B | Is banding entered as a type-only selection (no quantity) per this ADR, or does the shop enter a linear-foot quantity for banding? | Type-only per this ADR |
| OQ-C | What is the actual mileage rate used in burden calculations? | $0.67/mile (federal rate); configure in initializer |
| OQ-D | Delivery fixed rate: is $400 per delivery hardcoded or user-overridable per estimate? | Store on estimate as `delivery_rate` decimal; default $400 |
| OQ-E | Per diem rate: is $65/day hardcoded? | Store on estimate as `per_diem_rate` decimal; default $65 |
| OQ-F | What does the "equipment" fixed cost row represent, and how does it relate to per-line-item equipment_hrs/rate? | Treat as separate; equipment_hrs/rate on line items is per-product; job-level equipment is a separate fixed-cost field if needed |

OQ-D and OQ-E affect the schema: if the rates are user-overridable, add `delivery_rate` and `per_diem_rate` decimal columns to `estimates`. The developer should add these columns by default and seed with the spreadsheet defaults. If the shop owner later decides they are fixed, the columns can be removed.

---

## Phased Build Plan

The refactor is large enough to warrant its own phased delivery. Suggested spec file boundaries:

### Phase A — SPEC-010: Estimating Foundation (data layer + materials price book)

Scope:
- All migrations (drop old tables, create materials, rebuild line_items, modify estimates)
- `Material` model, `Estimate` model updates, `LaborRate` seed update
- `MaterialsController` — edit the per-estimate price book (one form for all slots)
- View: estimate show page with a link to the materials price book
- No line item entry yet

Acceptance: An estimate can be created; its materials price book populates automatically; the estimator can enter quote prices; `cost_with_tax` updates when prices are saved.

### Phase B — SPEC-011: Line Item Grid

Scope:
- `LineItem` model (all columns, associations, cost methods)
- `LineItemsController` — create, update, destroy with Turbo Stream responses
- View: horizontal scrolling grid for line item entry
- `EstimateTotalsCalculator` — flat version, all labor and material costs
- Estimate show page: totals summary (non-burdened, burdened)

Acceptance: An estimator can add product rows, assign material types from the price book, enter labor hours, and see live totals update via Turbo Streams.

### Phase C — SPEC-012: Job-Level Costs and Final Totals

Scope:
- Job-level cost fields on estimate (install_travel_qty, delivery_qty, per_diem_qty, hotel_qty, airfare_qty, delivery_rate, per_diem_rate)
- Estimate settings form for crew sizes, miles, percentages, countertop quote
- Calculator extended to include job-level fixed costs and COGS breakdown
- Final totals display (matching spreadsheet's "total" area)

Acceptance: All numeric fields from the spreadsheet's job-level section are enterable; the final totals match a hand-calculated known estimate.

### Phase D — SPEC-013: Document Output (previously Phase 6)

Scope: Same as prior SPEC-008 (PDF/print output), now targeting the new data model.

### Phase E — SPEC-014: Polish (previously Phase 7)

Scope: Same as prior SPEC-009, plus soft-delete on estimates (P7-01), labor category management (P7-02).

---
