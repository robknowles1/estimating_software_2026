# Spec: Product Catalog and Line Item Refactor

**ID:** SPEC-013
**Status:** done
**Priority:** high
**Created:** 2026-04-11
**Author:** pm-agent

---

## Summary

This spec delivers the product catalog and removes the per-estimate materials price book entirely. The business builds a fixed set of products (e.g., "MDF Base 2-door", "Plywood Upper 1-door"); all material costs, labor hours, and equipment defaults are properties of the product, not of the individual estimate. Estimators pick products from the catalog when building an estimate, the line item is pre-filled with the product's values, and they adjust as needed. Freeform line items (no product selected) remain supported. The per-estimate `materials` table and its seeding/recalculation machinery are deleted. The `EstimateTotalsCalculator` is simplified to read flat columns directly from line items with no materials query.

This spec covers two tightly coupled changes that must ship together:
1. **Product Catalog CRUD** — new `products` table, model, controller, views, and sidebar nav link.
2. **Line Item and Estimate Refactor** — schema changes to `line_items`, deletion of `Material` model and related code, calculator rewrite, and estimate edit page updates.

---

## User Stories

- As an estimator, I want to browse the product catalog and select a product when adding a line item, so that I do not have to re-enter material and labor defaults for every common product.
- As an estimator, I want the line item form to be pre-filled with the selected product's values, so that I can review and override them before saving.
- As an estimator, I want to add a freeform line item with no product selected, so that I can handle one-off or custom work that is not in the catalog.
- As an admin user, I want to create, edit, and delete products in the catalog, so that the catalog stays current with the shop's pricing and product mix.
- As an admin user, I want products grouped by category in the catalog and in the product selector, so that I can find items quickly as the catalog grows.
- As an estimator, I want to see "based on [product name]" on a line item card when the item originated from a catalog product, so that I know the source of the pre-filled values.

---

## Acceptance Criteria

### Product Catalog CRUD

1. Given the sidebar navigation, a "Products" link is present and accessible to any logged-in user, leading to the products index page.
2. Given the products index page, all products are listed with name, category, and unit columns. When no products exist, an empty state with a "New Product" call-to-action is shown.
3. Given the new product form, when submitted without a name, a validation error is displayed and no record is created.
4. Given a valid product form submitted with name, category, unit, slot descriptions, unit prices, quantities, labor hours, and equipment fields, a `Product` record is created with all values persisted.
5. Given an existing product, when edited and saved, all changed fields are updated and a success flash message is displayed.
6. Given an existing product, when deleted, the product record is destroyed and any `line_items` that referenced it have their `product_id` set to null (no line item data is lost).
7. Given the product form, the nine material slots (exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides) and locks are presented with labeled description, unit price, and quantity fields — except banding, which has no quantity field (banding is a flat per-unit cost), and locks, which has description, unit price, and quantity.
8. Given the product form, labor hours fields are present for: detail, mill, assembly, customs, finish, install. Equipment hours and equipment rate fields are also present.

### Line Item Refactor — Schema and Model

9. Given the refactored schema, `line_items` has no `_material_id` FK columns. Each slot (exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides, locks) has `{slot}_description` (string) and `{slot}_unit_price` (decimal) columns. All existing `{slot}_qty` columns are retained (banding retains no qty column per ADR-008). `locks_unit_price` is present.
10. Given a line item, it has an optional nullable `product_id` FK to `products` with `ON DELETE SET NULL` behavior.
11. Given `Product#apply_to(line_item)`, calling it copies all slot descriptions, unit prices, qtys, labor hours, equipment hours, equipment rate, and unit from the product into the line item's flat columns. It does not save the record.

### Line Item Creation with Product Selection

12. Given the estimate edit page, when an estimator clicks "Add Product," a product selector (searchable, grouped by category) is shown before or as part of the new line item form.
13. Given an estimator selects a catalog product in the add-line-item flow, the line item form is pre-filled with the product's name as the description and all material, labor, and equipment values. The estimator may override any field before saving.
14. Given the estimator modifies any pre-filled fields before submitting, the saved line item reflects the estimator's values, not the original product values. The product copy is a snapshot; future product edits do not affect this line item.
15. Given an estimator adds a line item without selecting a product, all fields default to blank/zero and the estimator enters values freeform. The line item saves with `product_id: null`.
16. Given a line item card on the estimate where `product_id` is set, the card displays "based on [product name]" as an informational annotation. If the product has since been deleted, this annotation is omitted.

### Calculator Rewrite

17. Given a line item with slot description and unit price columns populated, the calculator computes `material_cost_per_unit` as:
    `(exterior_qty * exterior_unit_price) + (interior_qty * interior_unit_price) + (interior2_qty * interior2_unit_price) + (back_qty * back_unit_price) + banding_unit_price + (drawers_qty * drawers_unit_price) + (pulls_qty * pulls_unit_price) + (hinges_qty * hinges_unit_price) + (slides_qty * slides_unit_price) + (locks_qty * locks_unit_price) + other_material_cost`.
    All nil values are treated as zero. Banding has no qty multiplier — its unit price is applied directly.
18. Given `EstimateTotalsCalculator.new(estimate).call`, the calculator fires exactly one database query (loading `LaborRate` records). No materials query is made. Line items are provided to the calculator as a preloaded association from the controller.
19. Given an estimate with no line items, the calculator returns a grand non-burdened total of zero without error.

### Deleted Code and UI Cleanup

20. Given the estimate edit page, the "Materials" button in the estimate top bar and the materials setup banner are removed.
21. Given the application, the `Material` model, `MaterialsController`, and all associated views and route entries are deleted. No runtime errors occur when accessing estimates or line items.

---

## Technical Scope

### Data / Models

#### Migration (single batch, run on feature branch)

Run as one migration file or a numbered sequence. Order matters:

1. Clear existing data: `LineItem.delete_all` and `Estimate.delete_all`. (Pre-production — no data to preserve.)
2. Drop all FK constraints from `line_items` to `materials`.
3. Remove nine `_material_id` columns from `line_items`: `exterior_material_id`, `interior_material_id`, `interior2_material_id`, `back_material_id`, `banding_material_id`, `drawers_material_id`, `pulls_material_id`, `hinges_material_id`, `slides_material_id`.
4. Add to `line_items` for each of the ten slots (exterior, interior, interior2, back, banding, drawers, pulls, hinges, slides, locks): `{slot}_description string` and `{slot}_unit_price decimal(12,4)`. Banding gets no qty column (already absent). Locks gets `locks_description string` (new) and `locks_unit_price decimal(12,4)` (new); `locks_qty` already exists.
5. Create `products` table (see schema below).
6. Add `product_id bigint` nullable FK to `line_items`, referencing `products`, `ON DELETE SET NULL`.
7. Drop `materials` table.

#### `products` table (new)

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| name | string NOT NULL | e.g. "MDF Base 2-door" |
| category | string | e.g. "Base Cabinets" — plain string, no FK |
| unit | string NOT NULL default 'EA' | |
| exterior_description | string | |
| exterior_unit_price | decimal(12,4) | |
| exterior_qty | decimal(10,4) | |
| interior_description | string | |
| interior_unit_price | decimal(12,4) | |
| interior_qty | decimal(10,4) | |
| interior2_description | string | |
| interior2_unit_price | decimal(12,4) | |
| interior2_qty | decimal(10,4) | |
| back_description | string | |
| back_unit_price | decimal(12,4) | |
| back_qty | decimal(10,4) | |
| banding_description | string | |
| banding_unit_price | decimal(12,4) | no qty — flat per-unit cost |
| drawers_description | string | |
| drawers_unit_price | decimal(12,4) | |
| drawers_qty | decimal(10,4) | |
| pulls_description | string | |
| pulls_unit_price | decimal(12,4) | |
| pulls_qty | decimal(10,4) | |
| hinges_description | string | |
| hinges_unit_price | decimal(12,4) | |
| hinges_qty | decimal(10,4) | |
| slides_description | string | |
| slides_unit_price | decimal(12,4) | |
| slides_qty | decimal(10,4) | |
| locks_description | string | |
| locks_unit_price | decimal(12,4) | |
| locks_qty | decimal(10,4) | |
| other_material_cost | decimal(12,2) | |
| detail_hrs | decimal(8,4) | |
| mill_hrs | decimal(8,4) | |
| assembly_hrs | decimal(8,4) | |
| customs_hrs | decimal(8,4) | |
| finish_hrs | decimal(8,4) | |
| install_hrs | decimal(8,4) | |
| equipment_hrs | decimal(8,4) | |
| equipment_rate | decimal(10,2) | |
| created_at / updated_at | datetime | |

Indexes: `(name)` for search; `(category)` for grouping.

#### `Product` model (`app/models/product.rb`)

```ruby
MATERIAL_SLOTS = %i[exterior interior interior2 back banding drawers pulls hinges slides locks].freeze
LABOR_CATEGORIES = %i[detail mill assembly customs finish install].freeze
```

Validations: `name` presence; `unit` presence.

`apply_to(line_item)` instance method: copies each slot's description, unit_price, and (where applicable) qty; copies all labor hours; copies `other_material_cost`, `equipment_hrs`, `equipment_rate`, `unit`. Does not save. Does not assign `product_id` — the controller sets that separately. Banding has no qty assignment. See ADR-009 Decision 3 for the full method body.

#### `LineItem` model changes

- Remove nine `belongs_to :{slot}_material` associations.
- Add `belongs_to :product, optional: true`.
- Retain `acts_as_list scope: :estimate`.
- Retain validations: `description` presence; `quantity` numericality `> 0`; `unit` presence.
- Update the model comment block to reflect the new column groups: Core (description, quantity, unit, position), Material Descriptions + Unit Prices (exterior through locks, flat columns), Material Quantities (exterior_qty through locks_qty, except banding), Other Cost (other_material_cost), Labor (detail_hrs through install_hrs), Equipment (equipment_hrs, equipment_rate), Catalog Reference (product_id).

#### `Estimate` model changes

Remove:
- `has_many :materials, dependent: :destroy`
- `after_create :seed_materials` callback
- `after_update :recalculate_material_costs` callback
- `seed_materials` private method
- `recalculate_material_costs` private method

Retain: `tax_rate`, `tax_exempt`, `copy_tax_exempt_from_client` before_create callback, `assign_estimate_number` before_validation callback, all job-level cost fields.

#### `Material` model — deleted

Delete: `app/models/material.rb`, `app/controllers/materials_controller.rb`, `app/views/materials/` directory, any `materials` route entries, and all spec files in `spec/models/material_spec.rb`, `spec/requests/materials_spec.rb`, `spec/system/` material-related specs.

### API / Logic

#### Routes

Add to `config/routes.rb`:

```ruby
resources :products
```

Top-level resource. No nesting.

Remove the `resources :materials` entry (or any nested `materials` route under estimates).

#### `ProductsController`

Standard Rails resource controller. Actions: `index`, `new`, `create`, `edit`, `update`, `destroy`. All actions require login (inherited from `ApplicationController`). No special authorization — any logged-in user may manage products in this phase.

- `index`: `@products = Product.order(:category, :name)`. No pagination required at current catalog size.
- `create` / `update`: flash i18n notice on success; re-render form with errors on failure.
- `destroy`: `ON DELETE SET NULL` handles the FK; just call `@product.destroy` and redirect.
- Strong params: all product columns except `id`, `created_at`, `updated_at`.

#### `LineItemsController` — create action

When `params[:product_id]` is present:

1. Find the product: `product = Product.find(params[:product_id])`.
2. Build the line item: `@line_item = @estimate.line_items.build(line_item_params)`.
3. Set the reference: `@line_item.product = product`.
4. Copy defaults: `product.apply_to(@line_item)`.
5. Re-apply params: `@line_item.assign_attributes(line_item_params)` — so estimator overrides in the form take precedence over product defaults.
6. Save and respond with Turbo Stream as before.

The `update` action does NOT call `apply_to` unless a `reset_from_catalog` param is explicitly sent (out of scope for this phase — on update, only `line_item_params` are applied). This prevents silent overwrites of estimator customizations.

#### `EstimateTotalsCalculator` rewrite

Constructor loads only `LaborRate.all.index_by(&:labor_category)` (one query). Line items arrive preloaded via `estimate.line_items`.

`material_cost_per_unit` formula per line item (all arithmetic in BigDecimal, nil treated as zero via `.to_d`):

```
(exterior_qty   * exterior_unit_price)
+ (interior_qty  * interior_unit_price)
+ (interior2_qty * interior2_unit_price)
+ (back_qty      * back_unit_price)
+ banding_unit_price
+ (drawers_qty   * drawers_unit_price)
+ (pulls_qty     * pulls_unit_price)
+ (hinges_qty    * hinges_unit_price)
+ (slides_qty    * slides_unit_price)
+ (locks_qty     * locks_unit_price)
+ other_material_cost
```

All other calculator logic (labor subtotals, equipment total, burden multiplier, COGS breakdown, job-level fixed costs) is unchanged from SPEC-012. The public interface is unchanged: `EstimateTotalsCalculator.new(estimate).call`.

In `EstimatesController#show` (and wherever the estimate edit page is rendered), update the eager load to remove materials:

```ruby
@estimate = Estimate.includes(:line_items).find(params[:id])
```

### UI / Frontend

#### Products index page (`app/views/products/index.html.erb`)

- Page title: "Products" (i18n).
- Subtitle: e.g., "Manage the catalog of products the shop builds." (i18n).
- Table columns: Name, Category, Unit, Last Updated, actions (Edit, Delete).
- Products sorted by category then name.
- Empty state: "No products yet. Add the first product to get started." with a "New Product" button.
- "New Product" button in the page header.
- Delete link uses a Rails `button_to` with `method: :delete` and a data-confirm prompt (i18n).

#### Products new/edit form (`app/views/products/_form.html.erb`)

Form sections:
1. **Basic Info**: Name (required), Category (text input — not a select, to allow free entry), Unit.
2. **Material Slots**: A grid or table of the ten slots. For each slot:
   - Exterior, Interior, Interior 2, Back, Drawers, Pulls, Hinges, Slides, Locks: Description (text), Unit Price (decimal), Qty (decimal).
   - Banding: Description (text), Unit Price (decimal). No Qty field.
   - Other Material Cost: single decimal field at the bottom of the materials section.
3. **Labor Hours**: Detail, Mill, Assembly, Customs, Finish, Install — each a decimal input labeled in hours.
4. **Equipment**: Equipment Hours, Equipment Rate ($/hr).

All labels use i18n keys under `products.form.*`. Reuse existing slot label keys from `line_items.form.*` where applicable.

Validation errors rendered inline above the form (standard Rails `@product.errors`).

#### Sidebar navigation (`app/views/layouts/_sidebar.html.erb`)

Add a "Products" nav link below "Estimates" (or in a logical position). Uses `t("nav.products")` i18n key. Active state follows the existing pattern used for Clients and Users links.

#### Estimate edit page changes

- Remove the "Materials" button from the estimate top bar.
- Remove the materials setup banner (`materials_banner_text` / `materials_banner_link`).
- Update the empty state text for line items (remove the reference to setting up material costs first).

#### Product selector on the estimate edit page

When an estimator clicks "Add Product":

1. A modal or inline form section appears (Turbo Frame or Stimulus-toggled — developer's choice, consistent with existing line item form patterns).
2. The form includes a product selector: a `<select>` element with `<optgroup>` tags grouped by category, listing all products ordered by name within each group. An empty/blank option ("Select a product...") is first, allowing freeform entry.
3. When a product is selected and the form is submitted, `product_id` is passed as a top-level param to `LineItemsController#create`. The description field is pre-populated with the product name (can be overridden). All material, labor, and equipment fields are pre-filled from the product via the server-side `apply_to` call.
4. If no product is selected (blank option), the form submits without `product_id` — freeform entry proceeds as before.

Note on pre-fill UX: The initial implementation may use a standard form submit cycle (not client-side live pre-fill). Full client-side pre-fill via Stimulus (loading product data into the form on select) is a Phase 7 polish item. In this phase, selecting a product and clicking a "Load Product" or "Add" button that submits to the server and returns a pre-filled form via Turbo Stream is acceptable.

#### Line item card

- Add a "based on [product name]" annotation to the collapsed line item card when `line_item.product` is present (use safe navigation: `@line_item.product&.name`).
- If `product_id` is set but the product has been deleted (`product` returns nil), display nothing (no annotation, no error).

#### i18n additions required

Add to `config/locales/en.yml`:

```yaml
nav:
  products: "Products"

products:
  create:
    notice: "Product was successfully created."
  update:
    notice: "Product was successfully updated."
  destroy:
    notice: "Product was successfully deleted."
  index:
    title: "Products"
    subtitle: "Manage the catalog of products the shop builds."
    new_button: "New Product"
    empty_title: "No products yet"
    empty_description: "Add the first product to get started."
    col_name: "Name"
    col_category: "Category"
    col_unit: "Unit"
    col_updated: "Last Updated"
    confirm_delete: "Delete %{name}? Line items based on this product will not be affected."
  new:
    title: "New Product"
    subtitle: "Add a product to the catalog."
  edit:
    title: "Edit Product"
    subtitle: "Update %{name}."
  form:
    basic_heading: "Basic Info"
    materials_heading: "Materials"
    labor_heading: "Labor Hours"
    equipment_heading: "Equipment"
    other_material_cost: "Other Material Cost"
    select_product: "Select a product..."
    based_on: "based on %{name}"

activerecord:
  attributes:
    product:
      name: "Name"
      category: "Category"
      unit: "Unit"
```

Remove or deprecate the following i18n keys that are no longer used:
- `estimates.layout.materials_button`
- `estimates.edit.materials_banner_text`
- `estimates.edit.materials_banner_link`
- `estimates.edit.no_line_items` — update value to remove materials reference
- All keys under `materials.*`

### Background Processing

None.

---

## Test Requirements

### Unit Tests

#### `Product` model (`spec/models/product_spec.rb`)

- Validates presence of `name`.
- Validates presence of `unit`.
- `apply_to(line_item)` copies `exterior_description`, `exterior_unit_price`, `exterior_qty` to the line item.
- `apply_to(line_item)` copies all nine other slot descriptions, unit prices, and qtys (spot-check interior, locks).
- `apply_to(line_item)` copies banding description and unit price but does not assign `banding_qty` (banding has no qty column).
- `apply_to(line_item)` copies all six labor hour fields.
- `apply_to(line_item)` copies `other_material_cost`, `equipment_hrs`, `equipment_rate`, and `unit`.
- `apply_to(line_item)` does not save the line item.
- `apply_to(line_item)` does not assign `product_id` (that is the controller's responsibility).

#### `LineItem` model (`spec/models/line_item_spec.rb`)

- Retains existing validations: `description` presence; `quantity > 0`; `unit` presence.
- `belongs_to :product, optional: true` — a line item with `product_id: nil` is valid.
- No material FK associations exist on the model (confirm `respond_to?(:exterior_material)` is false).

#### `EstimateTotalsCalculator` (`spec/services/estimate_totals_calculator_spec.rb`)

- Given a line item with known `exterior_qty`, `exterior_unit_price`, and no other slots set, `material_cost_per_unit` equals `exterior_qty * exterior_unit_price`.
- Given a line item with `banding_unit_price` set and all qty slots nil, `material_cost_per_unit` equals `banding_unit_price` (no qty multiplier).
- Given a line item with `locks_qty` and `locks_unit_price` set, `locks_qty * locks_unit_price` is included in material cost.
- Given a line item with `other_material_cost` set, it is included in material cost.
- All nil slot values contribute zero (no nil arithmetic errors).
- Result uses `BigDecimal` — standard material + labor inputs produce no floating point rounding errors.
- Calculator fires exactly one database query regardless of line item count (verify with query count assertion or `expect { }.to make_database_queries(count: 1)` if the counter gem is available; otherwise assert the labor rates are preloaded and no N+1 occurs via a comment explaining the design).
- Remove all existing specs that reference `Material`, `materials_hash`, or `slot_key` lookups.

### Request Tests

#### `ProductsController` (`spec/requests/products_spec.rb`)

- `GET /products` — returns 200; renders the index.
- `GET /products/new` — returns 200.
- `POST /products` with valid params — creates a product, redirects to products index.
- `POST /products` with blank name — returns 422, re-renders form with errors.
- `GET /products/:id/edit` — returns 200.
- `PATCH /products/:id` with valid params — updates the product, redirects.
- `PATCH /products/:id` with blank name — returns 422.
- `DELETE /products/:id` — destroys the product, redirects. Line items with that `product_id` have `product_id` set to null (verify in the test).
- All actions redirect to login when unauthenticated.

#### `LineItemsController` — updated specs (`spec/requests/line_items_spec.rb`)

- `POST /estimates/:id/line_items` with `product_id` and no other overrides: creates line item with description matching the product name and `exterior_description` matching the product's `exterior_description`.
- `POST /estimates/:id/line_items` with `product_id` and an overridden `description` param: saves the overridden description, not the product name.
- `POST /estimates/:id/line_items` without `product_id`: creates a freeform line item with `product_id: nil`.
- `POST /estimates/:id/line_items` — no material FK params are accepted (strong params must not include `_material_id` keys).
- Remove all request specs that reference material assignments (e.g., setting `exterior_material_id`).

### End-to-End Tests

#### Product catalog management (`spec/system/products_spec.rb`)

- A logged-in user visits the Products index, clicks "New Product," fills in name ("MDF Base 2-door"), category ("Base Cabinets"), exterior description ("MDF"), exterior unit price ("45.00"), exterior qty ("1.5"), detail hours ("0.75"), and saves. The new product appears in the products index.
- A logged-in user edits the product, changes the name, and saves. The updated name appears in the index.
- A logged-in user deletes the product. It is removed from the index. (Any line items referencing it retain their data.)

#### Estimate line item with product selection (`spec/system/line_items_spec.rb`)

- A logged-in user creates an estimate, navigates to the estimate edit page, clicks "Add Product," selects "MDF Base 2-door" from the product dropdown, and submits. A line item card appears with "MDF Base 2-door" as the description and "based on MDF Base 2-door" annotation.
- A logged-in user adds a freeform line item (no product selected), enters a description manually, and saves. The line item card appears with no "based on" annotation.
- A logged-in user adds a product-based line item, then overrides the description field before saving. The saved card shows the overridden description, not the product name.

#### Estimate page — materials elements removed (`spec/system/estimates_spec.rb` or inline)

- The estimate edit page does not contain a "Materials" button or materials setup banner for any estimate.

---

## Migration Strategy

This is a pre-production application with no user data to preserve. The migration strategy is a clean-break approach:

1. Clear all line item and estimate data in the migration body before altering schema (`LineItem.delete_all`, `Estimate.delete_all`).
2. Execute all schema changes in a single migration or a numbered sequence within the same feature branch.
3. Run on the feature branch before any application code changes are tested, to ensure the schema and code changes are developed together.
4. After migration runs: `bin/rails db:seed` will re-seed labor rates (no estimate or line item seed data exists). Verify with `bundle exec rspec` on the full suite.

No rollback of production data is required. The `down` method on the migration may raise `ActiveRecord::IrreversibleMigration` given that data is cleared.

---

## Deleted Files Checklist

The developer must delete or empty the following files and verify no runtime reference remains:

- `app/models/material.rb`
- `app/controllers/materials_controller.rb`
- `app/views/materials/` (entire directory)
- `spec/models/material_spec.rb`
- `spec/requests/materials_spec.rb`
- Any `spec/system/` file dedicated to materials price book flows
- `spec/factories/materials.rb` (or the `:material` factory block if in a shared factory file)
- The `:material` FactoryBot factory
- The `skip_material_seeding` trait on the `:estimate` factory (no longer needed)
- The `materials` route entry in `config/routes.rb`

After deletion, run `bundle exec rspec` and verify no `NameError: uninitialized constant Material` or similar errors appear.

---

## Out of Scope

- Role-based access control for the products catalog (any logged-in user may manage products in this phase; admin-only restriction is future work).
- Client-side live pre-fill of the line item form when a product is selected (Stimulus-driven instant pre-population without a server round-trip is Phase 7 polish).
- "Reset from catalog" button on an existing line item to re-apply the current product values (future feature; guarded by the `reset_from_catalog` param convention described above).
- Product import from CSV or spreadsheet.
- Product versioning or price history.
- Analytics on product usage (which products are most-used in estimates).
- A separate product categories table or admin screen for managing category names (plain string is sufficient per ADR-009 Decision 7).
- PDF output (SPEC-008 / future).
- Job-level cost and burdened total changes (SPEC-012 — separate spec; calculator changes here must preserve SPEC-012 output).

---

## Open Questions

- **OQ-A (non-blocking):** Should the product selector on the estimate edit page support incremental search (Stimulus + fetch against `/products.json`)? The initial implementation uses a plain `<select>` with `<optgroup>` grouping, which is sufficient for a catalog of up to ~100 products. Upgrade to a searchable combobox if the catalog grows beyond that. No action needed before shipping.
- **OQ-B (non-blocking):** Should the product index show the full material slot breakdown inline, or only name/category/unit with an "Edit" drill-down? The spec calls for the abbreviated list view (name, category, unit, last updated). Full breakdown is only visible on the edit form. Confirm with the shop owner if they want a quick-scan view of prices on the index before building.
- **OQ-C (non-blocking):** The `locks_description` column is added to both `products` and `line_items` in this spec (ADR-009 schema table lists it). The current `line_items` table has `locks_qty` but no `locks_description`. Confirm the developer adds `locks_description` to both tables in the migration — this is a net-new column on both, not a rename.

---

## Dependencies

- SPEC-010, SPEC-011, SPEC-012 must be complete (or their schema must exist). This spec alters the `line_items` and `estimates` tables and replaces the calculator logic built in those phases.
- `acts_as_list` gem must be in the bundle (already present per SPEC-002).
- `LaborRate` seed data must be present (`detail`, `mill`, `assembly`, `customs`, `finish`, `install` records). No change to seed data is required by this spec.
- ADR-009 (accepted) governs all schema and integration decisions. The developer does not need to re-read the ADR — all decisions are summarized in this spec's Technical Scope section. Key decisions for quick reference:
  - Flat columns on both `products` and `line_items` (no join table, no JSONB).
  - Copy-on-select: line item values are a point-in-time snapshot; product edits do not reprice existing estimates.
  - `product_id` on `line_item` is display/audit only; `ON DELETE SET NULL`; ignored by calculator.
  - Banding has no qty — its `unit_price` is a flat per-unit cost (no multiplier in the calculator).
  - `apply_to` is called explicitly in the controller, not via a callback.
  - Category is a plain string on `products`, not a FK to a categories table.
