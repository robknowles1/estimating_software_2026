# Spec: Searchable Material Combobox — Add Material to Price Book

**ID:** SPEC-015
**Status:** done
**Priority:** medium
**Created:** 2026-04-17
**Author:** pm-agent

---

## Summary

The "Add Material" page (`/estimates/:id/estimate_materials/new`, Search Library tab) currently presents a plain text input, a "Search" button, and a results table rendered below via a full-page GET. This two-step flow — type, submit, scan a table, click "Add" — is slower than necessary for a task estimators perform many times per job. This spec replaces the Search Library tab's UI with a searchable dropdown (combobox): the estimator types in a single field, a live-filtered list of library materials appears inline, and selecting an entry immediately submits the hidden form. The "Create New" tab is unchanged. The feature requires no new data model changes and no new database columns — the existing `estimate_materials` create endpoint already accepts a `material_id` parameter.

---

## Library Selection: Tom Select

**Chosen library: Tom Select v2 (base build)**

Tom Select is a lightweight (~16 KB gzipped for the complete build; ~10 KB for the base build), framework-agnostic select/combobox control forked from selectize.js. It ships a proper ESM distribution that is consumable directly from jsDelivr's `/+esm` endpoint, making it pinnable in Rails importmap without any npm tooling. Key evaluation points:

| Criterion | Tom Select | Choices.js | Slim Select |
|---|---|---|---|
| ESM CDN via jsDelivr `/+esm` | Yes — confirmed working | Yes, but no clean ESM-only build | Yes, but requires separate CSS import; ESM build less tested in importmap context |
| Bundle size (base, gzipped) | ~10 KB JS + ~3 KB CSS | ~19 KB | ~7 KB JS |
| Keyboard nav / ARIA | Full ARIA combobox pattern; arrow keys, Enter, Escape | Good but ARIA less complete | Good |
| Active maintenance (as of 2026) | Active; orchidjs org; v2.x stable | Maintained but slower release cadence | Maintained |
| Turbo/Stimulus fit | `destroy()` method for clean teardown on `disconnect()` | `destroy()` method available | `destroy()` available |
| Rails importmap precedent | Multiple documented gists and production apps | Less documented with importmap | Limited documentation |

**Importmap pin instruction:**

```ruby
# config/importmap.rb
pin "tom-select", to: "https://cdn.jsdelivr.net/npm/tom-select@2.4.3/+esm"
```

CSS must be added to the application layout `<head>` (not via importmap):

```html
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/tom-select@2.4.3/dist/css/tom-select.css">
```

The CSS link should be added only once, in `app/views/layouts/application.html.erb` (authenticated layout), scoped via a `content_for` block if the CSS is only needed on estimate pages — or included globally, as it is small and adds no perceived cost.

**Why not a pure Stimulus implementation:** Building an accessible combobox from scratch (ARIA pattern: `role="combobox"`, `aria-expanded`, `aria-autocomplete`, `aria-activedescendant`) is non-trivial and error-prone. Tom Select provides battle-tested ARIA compliance with no additional dependencies beyond itself.

---

## Data Loading: Client-Side on Page Load

**Recommended approach: load all active materials as a JSON payload embedded in the page on load.**

Reasoning:
- The global materials library is expected to stay well under 500 records for a single millwork shop. At 500 materials with name, id, category, and unit, the JSON payload is under 50 KB — negligible.
- Client-side filtering avoids a round-trip on every keystroke and keeps the implementation simpler (no new JSON endpoint, no debounce logic, no loading spinner).
- The page already loads an `Estimate` and its associated records; adding an `@materials` assignment to `EstimateMaterialsController#new` is one line.
- If the library grows beyond ~2 000 entries in a future phase, the controller value can be replaced with an AJAX `load` option — Tom Select supports this without changing the Stimulus controller interface.

The `@materials` collection is serialized into a Stimulus controller value (a JSON array) via a `data-` attribute on the controller element. Tom Select reads this array as its `options` on initialization.

---

## User Stories

- As an estimator, I want to type part of a material name and see a live-filtered dropdown of matching library materials, so that I can find and add a material to the price book in a single interaction without submitting a search form.
- As an estimator, I want keyboard navigation in the material dropdown (arrow keys to move, Enter to select, Escape to close), so that I can add materials without lifting my hands from the keyboard.
- As an estimator, I want the dropdown to show a clear "no results" message when my search term matches nothing in the library, so that I know to switch to the "Create New" tab.
- As an estimator, I want the "Create New" tab to remain exactly as it is today, so that my workflow for adding new materials to the library is unaffected.

---

## Acceptance Criteria

1. Given the "Add Material" page with the "Search Library" tab active, when the page loads, then a single combobox input is rendered (no separate "Search" button, no results table beneath it); the input has a translated placeholder string from `en.yml`.

2. Given the combobox input, when the estimator types one or more characters, then the dropdown filters the list of active library materials in real time, matching on name (case-insensitive, substring match); the filtering happens client-side with no additional HTTP request.

3. Given the combobox dropdown is open and contains results, when the estimator presses the down/up arrow keys, then focus moves through the options; when the estimator presses Enter on a highlighted option, then that option is selected and the form is submitted.

4. Given the estimator selects a material from the combobox, when the selection is made, then a hidden `<input name="material_id">` is populated with the selected material's id and the form is submitted automatically (no separate "Add" button required); the browser navigates to `estimate_estimate_materials_path` with the existing success or already-present flash notice.

5. Given the combobox search term matches no active library materials, when the dropdown would open, then it displays the translated empty-state string from `en.yml` (e.g., "No materials found") rather than an empty list.

6. Given the combobox controller is mounted on a Turbo-navigated page, when the Stimulus controller connects, then Tom Select is initialized on the `<select>` element; when the controller disconnects (Turbo navigation away, or Turbo cache restore), then `tomSelect.destroy()` is called to prevent duplicate initialization and memory leaks.

7. Given a screen reader user navigates to the combobox, when the element is inspected, then it carries the ARIA combobox role, `aria-expanded`, `aria-autocomplete`, and `aria-activedescendant` attributes as rendered by Tom Select's default ARIA output; no additional ARIA attributes need to be hand-authored.

8. Given the "Create New" tab is selected, when the tab renders, then it is identical to the current form (name, description, category, unit, default_price fields, submit button); no changes are made to this tab.

9. Given the combobox page loads, when `Material.active` returns zero records, then the combobox renders with the empty-state placeholder and no dropdown options; no error is raised.

10. Given the current search-form implementation (text field + "Search" button + results table), when SPEC-015 is complete, then these elements no longer exist in the Search Library tab; the GET `?q=` query param handling in `EstimateMaterialsController#new` may be removed or retained (non-breaking either way) but the UI no longer depends on it.

---

## Technical Scope

### Data / Models

No schema changes. No new models.

The only model-layer change: `EstimateMaterialsController#new` must assign `@materials = Material.active.order(:name)` so the view can serialize the options list.

### API / Logic

#### `EstimateMaterialsController#new` — update

Add one assignment:

```ruby
@materials = Material.active.order(:name)
```

The `@query` and `@search_results` assignments may be removed once the search-form UI is gone. Remove the `?q=` GET param handling if it is no longer referenced; the `create` action is unchanged.

#### No new JSON endpoint

Client-side filtering means no new `/materials/search.json` route is required. If a future spec adds async loading, the Stimulus controller's `load` option can be wired to an endpoint at that time.

### UI / Frontend

#### Stimulus controller: `app/javascript/controllers/material_combobox_controller.js`

Responsibilities:
- On `connect()`: initialize Tom Select on the `<select>` element identified by the `selectTarget`.
- Pass `options` from the `materialsValue` (JSON array parsed from the controller's data attribute).
- Configure Tom Select with: `valueField: "id"`, `labelField: "label"`, `searchField: ["label"]`, `placeholder` from the `placeholderValue` string, `noResultsText` from the `emptyStateValue` string, `create: false` (no inline creation — that is the "Create New" tab's job).
- On item selection (`onItemAdd` callback): submit the enclosing form.
- On `disconnect()`: call `this.tomSelect.destroy()` if `this.tomSelect` is defined.

Controller values interface:

```javascript
static values = {
  materials: Array,   // [{ id: 1, label: "Maple Plywood 3/4 — sheet_good" }, ...]
  placeholder: String,
  emptyState: String
}
```

The `label` field combines `material.name` and `material.category.humanize` for disambiguation (e.g., "Maple Plywood 3/4 — Sheet Good"). This formatting is done in the view helper or directly in the view, not in the controller.

#### View: `app/views/estimate_materials/new.html.erb` — Search Library tab section

Replace the existing `form_with(url: ..., method: :get)` search block and the `@search_results` conditional block with:

```erb
<%= form_with url: estimate_estimate_materials_path(@estimate), method: :post,
    data: { controller: "material-combobox",
            "material-combobox-materials-value": @materials.map { |m|
              { id: m.id, label: "#{m.name} — #{m.category.humanize}" }
            }.to_json,
            "material-combobox-placeholder-value": t(".search_placeholder"),
            "material-combobox-empty-state-value": t(".no_results") } do |f| %>
  <%= hidden_field_tag :material_id, nil, id: "material_id_field" %>
  <div class="flex flex-col gap-2">
    <label class="block text-xs font-medium text-slate-700">
      <%= t(".search_label") %>
    </label>
    <select data-material-combobox-target="select"
            class="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm">
      <option value=""></option>
    </select>
  </div>
<% end %>
```

The hidden `material_id` field is populated by the Stimulus controller before form submission. The `<select>` element is the mount point for Tom Select.

#### CSS

Add to `app/views/layouts/application.html.erb` inside `<head>` (before the Tailwind stylesheet link so Tailwind utilities can override Tom Select defaults if needed):

```html
<link rel="stylesheet"
      href="https://cdn.jsdelivr.net/npm/tom-select@2.4.3/dist/css/tom-select.css">
```

No Tailwind purge concern: Tom Select CSS comes from CDN, not from the Tailwind input file.

#### i18n keys — additions to `config/locales/en.yml`

Under the existing `estimate_materials.new` namespace:

```yaml
en:
  estimate_materials:
    new:
      search_label: "Search materials library"
      search_placeholder: "Type to search…"
      no_results: "No materials found — try the Create New tab"
```

The existing `search_tab`, `create_tab`, `title`, `subtitle`, `back_link`, and `default_price_hint` keys are unchanged.

#### "Create New" tab

No changes whatsoever.

### Background Processing

None.

---

## Test Requirements

### Unit Tests

No new model or service unit tests required — no model logic changes.

### Integration Tests

**`spec/requests/estimate_materials_spec.rb` — additions:**

- `GET /estimates/:id/estimate_materials/new` — response body contains the JSON materials array in the `data-material-combobox-materials-value` attribute (verify at least one material name is present when `@materials` is non-empty).
- `GET /estimates/:id/estimate_materials/new` — when `Material.active` is empty, the attribute value is the JSON string `"[]"`.
- Confirm the existing `POST /estimates/:id/estimate_materials` with `material_id` param still creates the row — no change to the create action, but regression coverage.

### End-to-End Tests

**`spec/system/estimate_materials_spec.rb` — replace the "adding a material from the library via search" example:**

The existing example uses `fill_in "q"` and `click_button "Search"`, which will no longer work after this change. Replace it with:

```ruby
describe "adding a material from the library via the combobox" do
  let!(:material) { create(:material, name: "Maple Plywood 3/4", default_price: BigDecimal("68.00")) }

  it "adds the material to the price book after typing and selecting from the dropdown" do
    login
    visit new_estimate_estimate_material_path(estimate, mode: "search")

    # Tom Select replaces the <select> with its own input; find by TS input role
    find(".ts-control input").fill_in with: "Maple"
    find(".ts-dropdown-content .option", text: /Maple Plywood 3\/4/, wait: 3).click

    expect(page).to have_current_path(estimate_estimate_materials_path(estimate), wait: 5)
    expect(page).to have_text("Maple Plywood 3/4", wait: 3)
    expect(page).to have_text("68.0000", wait: 3)
  end

  it "shows the empty-state message when no materials match the search term" do
    login
    visit new_estimate_estimate_material_path(estimate, mode: "search")

    find(".ts-control input").fill_in with: "xyzzy_no_match"
    expect(page).to have_css(".ts-dropdown-content .no-results", wait: 3)
    expect(page).to have_text("No materials found", wait: 3)
  end
end
```

The existing "editing the quote_price" and "materials setup banner" examples are unaffected and must continue to pass.

---

## Out of Scope

- Async (AJAX) search endpoint — deferred; client-side filtering is sufficient for the expected catalog size.
- Multi-select (adding multiple materials at once from a single combobox interaction) — the existing one-at-a-time UX is retained.
- Customizing Tom Select's visual theme beyond overriding it with Tailwind utility classes — default CDN styles are acceptable for now.
- Inline creation of a new material from within the combobox (`create: true`) — this is deliberately disabled; the "Create New" tab handles that flow.
- Removing the `?q=` and `@search_results` server-side search logic from the controller — it may be removed as a cleanup task but it is not required; removing it is not a breaking change for any other spec.
- Changes to the materials index page, edit page, or any other estimate_materials view.
- Mobile or touch-specific UX testing.

---

## Open Questions

| OQ | Question | Blocks progress? |
|----|---------|-----------------|
| OQ-A | Should the Tom Select CSS be added globally to `application.html.erb` or behind a `content_for :head` block used only on estimate-layout pages? It is ~3 KB and harmless globally, but a `content_for` keeps the base layout clean. Developer decides — either is acceptable. | No |
| OQ-B | The existing `?q=` search GET handler in `EstimateMaterialsController#new` can be left in place (harmless dead code) or removed. If left in, it should not regress any existing tests. Confirm with developer before removing. | No |
| OQ-C | Tom Select v2.4.3 is specified above as a concrete pinned version. The developer should verify this is the current stable release at implementation time and update the pin URL if a newer patch is available. | No |

---

## Dependencies

- SPEC-014 (Materials Rework) — done; this spec depends on the `materials` table, `Material.active` scope, `Material.active.order(:name)` query, and `EstimateMaterialsController` existing as implemented by SPEC-014.
- No other in-flight specs are affected. The `estimate_materials` create action is unchanged; all specs that POST to it continue to work.
