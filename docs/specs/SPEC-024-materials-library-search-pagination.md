# Spec: Materials Library Search and Pagination

**ID:** SPEC-024
**Status:** ready
**Priority:** medium
**Created:** 2026-05-27
**Author:** spec-agent

---

## Summary

As the global materials library grows, the flat list on `/materials` becomes hard to navigate. This spec adds search filtering and pagination (~20 rows per page) to the Materials index page. The implementation uses a plain GET form with query params for both search and page — no JavaScript or Turbo Frames required. Pagination is implemented with the Pagy gem, a new dependency.

Background: raised in a meeting on 2026-05-22 with Blake (estimator at TrimArt).

---

## User Stories

- As an estimator, I want to type a search term on the materials library page and see matching rows appear, so that I can locate a specific material without scrolling through the entire list.
- As an estimator, I want the search to match on both the material name and description, so that I can find materials by how I describe them as well as by their formal name.
- As an estimator, I want pagination on the materials list so that the page loads quickly and does not become slow as the library grows.
- As an estimator, I want to be able to clear my search and return to the full paginated list, so that I can reset state without reloading manually.

---

## Acceptance Criteria

AC-1: Given the materials index page (`/materials`), when it loads with no search query, then all active materials are displayed in pages of 20 rows, ordered by name ascending.

AC-2: Given the materials index page, when there are fewer than or equal to 20 active materials, then no pagination controls are rendered.

AC-3: Given the materials index page with more than 20 active materials, when the page loads, then pagination controls (previous/next page links and a page indicator) are rendered below the table.

AC-4: Given the materials index page, when the estimator types into the search input and submits the form, then the page reloads showing only materials whose `name` or `description` contains the search term (case-insensitive), and the `q` query parameter is set in the URL.

AC-5: Given a search term is active, when results are returned, then pagination is applied to the filtered result set (not to the total library). Navigation between pages preserves the active search term.

AC-6: Given a search term is active, when the estimator activates the clear link, then the full paginated list is restored via a full-page GET to `materials_path` with no `q` parameter.

AC-7: Given a search term is active, when the result set is empty, then an empty state message is displayed indicating no materials matched the search.

AC-8: Given the page header (title, subtitle, and "New Material" button) is outside the search/results area, when a search or page navigation request is made, then the page header remains visible and is not affected.

AC-9: Given an unauthenticated request to `/materials`, when the request is made, then the response redirects to the login page (existing behavior — must not regress).

AC-10: Given the estimator submits a search query, when the page loads, then the `q` query parameter is set in the URL so the filtered view is bookmarkable and shareable (browser back/forward works naturally with a standard GET request).

AC-11: Given `params[:page]` exceeds the total page count, when the controller processes the request, then it rescues `Pagy::OverflowError` and redirects to `materials_path(q: @query, page: @pagy.last)`.

---

## Technical Scope

### Dependency: Add Pagy

Pagy is not currently in the Gemfile. Add it:

```
gem "pagy", "~> 9.0"
```

Include the Pagy backend in `ApplicationController` (`include Pagy::Backend`) and the Pagy frontend in `ApplicationHelper` (`include Pagy::Frontend`). Use Pagy's default configuration (20 items per page) via an initializer at `config/initializers/pagy.rb`. Tailwind-compatible styling is applied via CSS class configuration in the initializer, not via a special helper variant.

No other pagination gems (Kaminari, will_paginate) should be added.

### `Material` model — nil/blank guard required

The existing scope:

```ruby
scope :search, ->(term) { active.where("name ILIKE :q OR description ILIKE :q", q: "%#{term}%") }
```

covers both `name` and `description`. However, calling `Material.search(nil)` or `Material.search("")` currently produces `q: "%"` and returns all active materials, which is incorrect. The scope must be updated to include a nil/blank guard as the first line:

```ruby
scope :search, ->(term) {
  return none if term.blank?
  active.where("name ILIKE :q OR description ILIKE :q", q: "%#{term}%")
}
```

Additionally, the `%` and `_` wildcard characters (and backslash) in the search term must be escaped before interpolation into the ILIKE query to prevent SQL wildcard injection:

```ruby
escaped = term.gsub(/[%_\\]/) { |c| "\\#{c}" }
active.where("name ILIKE :q OR description ILIKE :q", q: "%#{escaped}%")
```

This escaping logic can live directly in the scope lambda or in a private model method called by the scope.

The `category` column is a controlled enum (`sheet_good`, `hardware`) — matching it by substring adds no useful findability, so category is excluded from the search scope.

**Model changes required:** yes — nil/blank guard and wildcard escaping in `Material.search`.

### `MaterialsController#index`

Update the `index` action to:
1. Accept a `q` query param.
2. Assign `@query = params[:q].to_s`.
3. Build the base scope: if `@query.present?`, apply `Material.search(@query)`; otherwise use `Material.active`.
4. Apply `.order(:name)` to the scoped relation.
5. Paginate the ordered relation with Pagy: `@pagy, @materials = pagy(scoped_relation, limit: 20)`.
6. Rescue `Pagy::OverflowError` and redirect to `materials_path(q: @query, page: @pagy.last)`.

The controller must remain thin — no filtering logic in the view.

### Routes

No routing changes required. The search and page params are query string params on the existing `GET /materials` route.

### UI / Frontend

#### Search form

Above the table, render a search form using a plain GET form that performs a full-page navigation:

```erb
<%= form_with url: materials_path, method: :get, data: { turbo: false } do |f| %>
  ...
<% end %>
```

The form must include:
- A text input with `name: :q`, `value: @query`, and an accessible label (visually hidden is acceptable). Use i18n key `t(".search_placeholder")` for the placeholder and `t(".search_label")` for the label.
- A submit button or the form may rely on Enter key submission.
- A clear/reset link that navigates to `materials_path` (no `q` param) when the search is active (`@query.present?`). Use `t(".clear_search")` for the link text.

No Turbo Frame, `data-turbo-frame`, or `data-turbo-action` attributes are used. The `data: { turbo: false }` convention is consistent with all other forms in this codebase.

#### Page layout

The page header (`<h1>`, subtitle, and "New Material" button) must remain above the search form and results area. No Turbo Frame wrapper is required; this is a standard full-page request/response cycle.

#### Pagination controls

Render Pagy's `pagy_nav` helper below the table. Do not use `pagy_tailwind_nav` — it does not exist in Pagy 9.x. Tailwind styling is applied via CSS class configuration in `config/initializers/pagy.rb`.

Navigation links must include the current `q` param so the search term is preserved across pages. Set `@pagy.vars[:params] = { q: @query }` before calling `pagy_nav(@pagy)`, or use `pagy_url_for(@pagy, n, params: { q: @query })` when constructing individual links.

#### Archive button

The existing `button_to` archive control in `index.html.erb` requires no changes. The prior concern about `button_to` being mis-targeted by a Turbo Frame is eliminated because this spec does not use Turbo Frames.

#### i18n keys

All new user-facing strings must be added to `config/locales/en.yml` under the `materials.index` namespace:

| Key | Example value |
|-----|---------------|
| `materials.index.search_placeholder` | `"Search by name or description…"` |
| `materials.index.search_label` | `"Search materials"` |
| `materials.index.clear_search` | `"Clear"` |
| `materials.index.empty_search_title` | `"No materials matched your search."` |
| `materials.index.empty_search_description` | `"Try a different term or clear the search to see all materials."` |

### Background Processing

None. Search and pagination are synchronous controller operations. At realistic library sizes (hundreds of materials) an ILIKE query with a B-tree index on `name` is adequate.

### Database

No migration required. The `materials` table already has `name`, `description`, and `discarded_at` columns. No new index is added by this spec; if query performance becomes a concern on a large catalog, a trigram index on `name` can be added in a follow-up.

---

## Test Requirements

### Unit Tests

**`Material` model (`spec/models/material_spec.rb` — additions):**
- `Material.search("maple")` returns materials whose `name` contains "maple" (case-insensitive).
- `Material.search("maple")` returns materials whose `description` contains "maple" (case-insensitive).
- `Material.search("maple")` does not return materials where neither `name` nor `description` contains "maple".
- `Material.search("maple")` does not return archived (discarded) materials even if the name matches.
- `Material.search("")` returns no results (nil/blank guard returns `none`).
- `Material.search(nil)` returns no results (nil/blank guard returns `none`).
- `Material.search("%")` returns only materials whose name or description literally contains "%" (wildcard is escaped, does not match all rows).

### Request Tests

**`MaterialsController` (`spec/requests/materials_spec.rb` — additions):**

- `GET /materials` (no params) — returns 200; renders all active materials ordered by name; does not render pagination when count <= 20.
- `GET /materials?q=maple` — returns 200; rendered response body includes materials matching "maple" and excludes non-matching materials.
- `GET /materials?q=nomatch` — returns 200; renders the empty search state message.
- `GET /materials?q=maple&page=2` — returns 200 (assuming enough records exist); rendered body includes page 2 results.
- `GET /materials?page=9999` — redirects to the last valid page (Pagy::OverflowError rescue).
- `GET /materials` unauthenticated — redirects to login (regression guard for AC-9).

### System Tests

**`spec/system/materials_search_spec.rb` (new file):**

AT1 (covers AC-1, AC-2, AC-3): Given fewer than 20 active materials exist, when the estimator visits `/materials`, then all rows are visible and no pagination controls appear. Add 21 materials via factory, reload the page, and confirm pagination controls now appear and only 20 rows are shown on page 1.

AT2 (covers AC-4, AC-6): Given several materials with names "Maple Plywood" and "Oak Veneer" exist, when the estimator types "maple" into the search input and submits, then only "Maple Plywood" appears in the table (full-page reload with `?q=maple` in the URL). When the estimator activates the clear link, all materials reappear.

AT3 (covers AC-5): Given 25 materials matching "plywood" exist, when the estimator searches "plywood" and navigates to page 2, then page 2 shows the remaining results and the search term is preserved in the input.

AT4 (covers AC-7): Given no material name or description contains "zzznotfound", when the estimator types "zzznotfound" into the search input and submits, then the empty state message is displayed and the table is absent.

AT5 (covers AC-8): Given the page has a header with the "New Material" button, when the estimator submits a search query, then the "New Material" button remains visible on the page.

AT6 (covers AC-10): Given the estimator searches for "maple" and the page loads, then the URL contains `?q=maple` and reloading or sharing that URL shows the same search results.

AT7 (covers AC-11): Given the estimator navigates to `materials_path(page: 9999)` directly, when the page loads, then they are redirected to the last valid page rather than receiving an error.

---

## Out of Scope

- Filtering by category (category is a two-value enum; a dropdown filter can be added later if needed).
- Sorting by columns other than name (column-sort headers are a separate feature).
- Real-time debouncing via a Stimulus controller (auto-submit on keystroke). This can be layered on later with no spec changes.
- Archived/discarded materials browser or restore functionality.
- Server-side caching of search results.
- Full-text search indexes (e.g., `pg_trgm`, `tsvector`). Plain ILIKE is sufficient for the expected library size.
- Any changes to the per-estimate price book (`/estimates/:id/estimate_materials`).
- Turbo Frame partial-page updates for search (the full-page GET approach is intentional and consistent with the rest of the codebase).

---

## Dependencies

- SPEC-014 (Materials Rework) — `Material` model with `active` scope and `discarded_at` column must exist. Status: done.
- SPEC-015 (Searchable Material Combobox) — The existing `Material.search` scope was introduced here (or earlier); this spec modifies it. Status: done.

---

## Open Questions

| OQ | Question | Decision |
|----|----------|----------|
| OQ-A | Should the search form auto-submit on keystroke (Stimulus debounce) or only on form submit? | Spec targets form-submit only (Enter key or submit button). Keystroke auto-submit can be added via a Stimulus controller in a follow-up with no spec changes required. |
| OQ-B | Which Pagy navigation helper should be used? | Use `pagy_nav` (plain HTML). `pagy_tailwind_nav` does not exist in Pagy 9.x — Tailwind styling is applied via CSS class configuration in the Pagy initializer. |

---

## Implementation Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-27 | Use Pagy as new gem dependency | Lightweight, zero dependencies, Rails-idiomatic. Kaminari and will_paginate are heavier. |
| 2026-05-27 | Exclude category from search scope | Category is a two-value enum; substring matching ("sheet" matches "sheet_good") would be misleading. A dedicated filter control is the correct UX for category. |
| 2026-05-27 | Full-page GET form used for search (not Turbo Frame) | Consistent with all other forms in the codebase which opt out of Turbo with `data: { turbo: false }`. No existing `turbo_frame_tag` usages exist in this app. |
| 2026-05-27 | Nil/blank guard added to `Material.search` scope | Calling the scope with a blank term previously returned all active materials (`q: "%"`), which is incorrect and could bypass the controller's `present?` gate in future callers. |
| 2026-05-27 | Wildcard escaping required in search scope | `%` and `_` characters in the search term must be escaped before ILIKE interpolation to prevent them from acting as SQL wildcards. |
| 2026-05-27 | `button_to` archive control needs no changes | The prior concern about `button_to` being mis-targeted by a Turbo Frame is eliminated because this spec uses a standard full-page GET form, not Turbo Frames. |

---

## Change Log

| Date | Change | Affected IDs | Rationale |
|------|--------|-------------|-----------|
| 2026-05-27 | Initial spec authored | All | New feature from Blake/TrimArt meeting notes |
| 2026-05-27 | Revised per review findings | AC-4, AC-6, AC-7, AC-8, AC-10, AC-11; Technical Scope; AT2, AT5, AT6, AT7; Implementation Decisions | Replaced Turbo Frame approach with full-page GET form (consistent with app convention); added nil/blank guard and wildcard escaping requirements to `Material.search`; replaced `pagy_tailwind_nav` with `pagy_nav`; specified correct Pagy 9.x param propagation pattern; added AC-11 and AT7 for `Pagy::OverflowError` handling; removed `button_to` Turbo Frame concern (not applicable without frames) |
