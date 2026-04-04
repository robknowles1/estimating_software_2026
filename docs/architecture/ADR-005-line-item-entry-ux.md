# ADR-005: Line Item Entry UX — Pattern C (Freeform with Autocomplete)

**Status:** accepted (pending estimator validation — see Risk section)
**Date:** 2026-04-01
**Deciders:** architect-agent

---

## Context

Estimators need to add line items to estimate sections quickly. The spec evaluated three UX patterns and recommended Pattern C: a freeform "Add line item" form where typing a description triggers autocomplete suggestions from a `CatalogItem` table. The estimator can accept a suggestion (pre-fills description, unit, unit_cost) or ignore it and type a custom entry.

The spec flags this as a blocker (OQ-02) pending validation with the actual estimators. This ADR addresses the architectural implications of Pattern C and what changes if the estimators prefer Pattern B (catalog-first).

## Decision

Implement Pattern C. Architect the `CatalogItem` table and the autocomplete endpoint to support Pattern C. Keep the architecture simple enough that it can accommodate Pattern B if stakeholder validation reverses the recommendation.

## Rationale

**Pattern C aligns with the migration path from Excel.** The existing Excel template is freeform — estimators type descriptions directly. Pattern C preserves that muscle memory while making the catalog additive. Forcing estimators through a catalog picker (Pattern B) before they can save a line item creates friction that could slow adoption of the new tool, which is the primary risk at launch.

**The catalog grows organically.** The sharedStrings from the Excel template reveal the shop already has named line item types: crown molding, door casing, closet shelving, hardware categories (pulls, hinges, slides), sheet goods types, stair components, and labor categories (Mill, Finish, Assembly, Detail, PM/Supervision). These can be pre-seeded as `CatalogItem` records to give the autocomplete immediate value on day one without requiring estimators to build the catalog themselves.

**Architectural simplicity.** Pattern C requires:
1. A `CatalogItem` model with a simple text search endpoint.
2. A Stimulus controller that listens for `input` events on the description field and performs a debounced `fetch` to the search endpoint, rendering a dropdown of suggestions.
3. Logic to pre-fill unit and unit_cost fields when a suggestion is selected.

None of this requires a dedicated search engine, full-text index, or complex frontend framework.

## Alternatives Considered

| Option | Pros | Cons | Rejected Because |
|--------|------|------|-----------------|
| Pattern A (spreadsheet grid) | Familiar Excel-like experience | Complex to build well in HTML; tab-to-advance cell navigation is fragile in browsers; poor mobile behavior | Implementation complexity too high for MVP; Stimulus/Hotwire is not the right tool for a full grid |
| Pattern B (catalog-first picker) | Enforces consistency; no freeform errors | Requires catalog to be complete before tool is usable; blocks estimators from entering anything not in catalog | Migration friction; catalog will be incomplete at launch |
| Pattern C (chosen) | Low friction; catalog is optional; familiar mental model | Catalog degrades if nobody maintains it; autocomplete adds frontend complexity | N/A — chosen option |

## Consequences

### Positive
- Estimators can enter any line item immediately, with or without a catalog match.
- The catalog pre-seeded from the Excel template provides immediate value.
- The `CatalogItem` model is simple and independent; it can be extended post-MVP with catalog management UI, import tools, or assembly bundles.
- The autocomplete Stimulus controller is self-contained and reusable.

### Negative
- The catalog will drift over time without active curation. Duplicates and stale entries will accumulate. A basic catalog management UI (CRUD for CatalogItem) should be included in MVP to allow cleanup.
- If the estimator validation (OQ-02) reverses the decision to Pattern B, the autocomplete Stimulus controller becomes unnecessary but the `CatalogItem` model and search endpoint are reusable as a picker backend with minimal change.

### Risks
- **Risk (HIGH):** Estimators may have a strong preference for Pattern B because they already work from a defined scope of work. If the validation session reveals this, the UX changes but the data model does not — `CatalogItem` remains, the line item form becomes a search-and-select rather than a freeform-with-suggest. Build the data layer first, confirm UX with estimators before building the Stimulus autocomplete. This is already flagged as a blocker (OQ-02).
- **Risk:** Autocomplete fetch on every keystroke causes visible lag or excessive server load. Mitigation: debounce the input event (300ms), use LIKE queries on the `description` column with a leading-wildcard-avoided pattern (`description LIKE 'crown%'` not `LIKE '%crown%'`), limit results to 8 items. Add an index on `catalog_items.description` — see Implementation Notes.
- **Risk:** Description field autocomplete does not fire if the estimator pastes text rather than typing. Mitigation: listen to both `input` and `change` events in the Stimulus controller.

## Implementation Notes

**CatalogItem schema:**
```
catalog_items
  id               integer  primary key
  description      string   not null
  default_unit     string
  default_unit_cost decimal(10,2)
  category         string
  created_at       datetime
  updated_at       datetime
```

**Index required:**
```ruby
add_index :catalog_items, :description
add_index :catalog_items, :category
```

PostgreSQL's LIKE with a prefix pattern (`description LIKE 'term%'`) uses the btree index. This is sufficient for a catalog of hundreds to low thousands of items.

**Search endpoint:**
```ruby
# config/routes.rb
get "catalog_items/search", to: "catalog_items#search"
```
```ruby
# CatalogItemsController#search
def search
  items = CatalogItem.where("description LIKE ?", "#{params[:q]}%")
                     .order(:description)
                     .limit(8)
  render json: items.select(:id, :description, :default_unit, :default_unit_cost)
end
```

The search endpoint must be protected by the same `require_login` before_action. Do not make it publicly accessible.

**Stimulus controller** (`description_autocomplete_controller.js`):
- Connects to the description input field.
- On `input` event (debounced 300ms): fetch `/catalog_items/search?q=<value>`.
- On response: render a dropdown list below the input.
- On list item click: populate `description`, `unit`, `unit_cost` fields; close dropdown; focus `quantity` field.
- On `keydown` Escape or click-outside: close dropdown.
- The dropdown is a plain `<ul>` positioned absolutely below the input. No external autocomplete library required.

**Catalog seed data:** The developer should analyze the sharedStrings from the Excel template (`estimating_template_xml/xl/sharedStrings.xml`) to extract line item types and pre-seed `db/seeds.rb`. Key categories visible in the template: Sheet Goods, Hardware (Pulls, Hinges, Slides, Banding, Locks), Labor (Mill, Finish, Assembly, Detail, PM/Supervision), Countertops, General Conditions, Delivery, Install. These map well to the `category` column.

**CatalogItem management UI:** A basic CRUD interface at `/catalog_items` should be included in MVP. It does not need drag-and-drop or bulk operations — a simple table with edit/delete links and a new item form is sufficient.

**Pattern B escape hatch:** If the architecture needs to pivot to Pattern B post-validation, the change is isolated to the line item form view and the Stimulus controller. The `CatalogItem` model, search endpoint, and association between `LineItem` and `CatalogItem` remain unchanged. Consider adding an optional `catalog_item_id` foreign key to `line_items` to track which catalog item a line item originated from — useful for analytics and future assembly features.

```
line_items
  catalog_item_id  integer  null  references catalog_items(id)
```
Add index: `add_index :line_items, :catalog_item_id`.
