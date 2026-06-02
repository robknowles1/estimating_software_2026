---
# Spec: Room Tracking on CSV Import

**ID:** SPEC-025
**Status:** ready
**Priority:** high
**Created:** 2026-05-27
**Author:** spec-agent

---

## Summary

When the estimator imports a CSV takeoff (SPEC-021), each line item row already carries a room name in column 1 of the CSV (e.g., "Room A", "Kitchen"). The importer currently discards that value. This spec captures the room name from the CSV and stores it as a plain string on each `line_item` record during import. The room name is then surfaced on the line item card so the estimator can verify assignments at a glance. A second import refinement — skipping rows whose category is "Finished Schedule" — is included here because it was identified alongside room tracking in the same user feedback session and touches the same `skip_row?` logic in the importer.

The stored room string is the primary data source the future Proposal/Bid Letter Wizard (SPEC-026) will use to build the "Specific Inclusions" section of a bid letter (rooms auto-populated from import; estimator adds bullet points and an optional photo per room).

---

## Key Findings from Code Inspection

**CSV column layout** (from `spec/fixtures/files/sample_import.csv`):
- col 0: category (e.g., "Base Cabinets")
- col 1: room name (e.g., "Room A", "Room B") — currently discarded
- col 2: additional location label (e.g., "Kitchen", "Living") — not in scope
- col 4: product number
- col 5: product name
- col 7: "Total" marker
- col 8: quantity
- col 9: unit

**"Finished Schedule" skip:** The existing `skip_row?` method already skips rows where col 0 starts with "z". "Finished Schedule" is a separate exact-match category confirmed in the 2026-05-22 meeting notes.

**No `room` column exists yet** on `line_items` (confirmed from schema.rb).

---

## User Stories

- As an estimator, I want each imported line item to record the room it came from, so that I do not have to re-tag line items manually when building the bid letter.
- As an estimator, I want to see the room name on each line item card on the estimate page, so that I can quickly verify the import assigned the correct room.
- As an estimator, I want "Finished Schedule" rows in the CSV skipped automatically during import, so that schedule-only rows do not appear as line items.

---

## Acceptance Criteria

**AC-1:** Given the `line_items` table, when a migration is applied, then a nullable `room` string column exists on `line_items`.

**AC-2:** Given a CSV row that is not skipped, when `LineItemCsvImporter` processes it, then the created `line_item.room` is set to the value of column 1 of the **first non-Total row** for that product group (`row[1].to_s.strip`), or `nil` if blank. For multi-row product groups where different detail rows have different col 1 values, the first non-Total row's value is used; subsequent rows' col 1 values are ignored.

**AC-3:** Given a CSV row whose column 1 is blank, when the importer processes it, then `line_item.room` is `nil` and no error is raised. Room is always optional.

**AC-4:** Given an existing line item imported without room data (room is `nil`), when the line item card is rendered on the estimate edit page, then no room badge or label is shown for that line item — the layout is unchanged for room-less items.

**AC-5:** Given a line item whose `room` is non-blank, when the line item card is rendered on the estimate edit page, then the room name is displayed as a secondary label beneath the description. The display must use the i18n key `t("line_items.card.room_label")`.

**AC-6:** Given a CSV row where column 0 equals `"Finished Schedule"` (exact, case-sensitive match), when `LineItemCsvImporter#skip_row?` evaluates that row, then `skip_row?` returns `true` and the row produces no line item. Note: The match is case-sensitive. If the takeoff software ever emits a differently-cased variant (e.g., `"finished schedule"`), those rows will not be skipped. This is accepted as a known limitation for v1 — the export label has been consistent across all observed CSVs. See OQ-2.

**AC-7:** Given a CSV where some rows have category `"Finished Schedule"` and other rows have normal categories, when the full CSV is imported, then only the normal-category rows produce line items; the "Finished Schedule" rows are silently skipped.

**AC-8:** Given the importer skips all rows (e.g., all are "Finished Schedule" or blank product numbers), when `LineItemCsvImporter#call` completes, then `result.error` is non-nil (the existing `ArgumentError` rescue path in `LineItemCsvImporter#call` returns this) and no line items are created.

**AC-9:** Given an unauthenticated request to any route modified by this spec, when the request is made, then the response redirects to the login page and no records are created or modified.

---

## Technical Scope

### Data / Models

**Migration:** `add_column :line_items, :room, :string` (nullable, no index).

**LineItem model:** No validation changes. `room` is always optional.

### Controllers / Routes

No new routes or controller actions. The import action signature is unchanged.

### Service — `LineItemCsvImporter`

**`parse_csv`** — add `room: row[1].to_s.strip.presence` to the `current_group` hash when starting a new group. Room is captured from the first non-Total, non-skipped row in each product group.

**`persist`** — add `line_item.room = group[:room]` alongside the existing description/quantity/product_id assignments. `line_item.room = group[:room]` must be assigned to the line item **before `line_item.save!`** and **before or after `matcher.match(line_item)` is called** (the two assignments are independent — `matcher.match` only writes to material FK columns and reads `line_item.description`; it does not read or write `room`).

**`skip_row?`** — insert `return true if category_cell == "Finished Schedule"` before the existing `start_with?("z")` check:

```ruby
def skip_row?(row)
  return false if row[7].to_s.strip == "Total"

  category_cell = row[0].to_s.strip
  product_num   = row[4].to_s.strip

  return true if category_cell == "Finished Schedule"
  return true if category_cell.start_with?("z")
  return true if product_num.blank? || product_num == "0"

  false
end
```

### Views

In `app/views/line_items/_line_item.html.erb`, inside the description container, add:

```erb
<% if line_item.room.present? %>
  <p class="text-xs text-slate-400"><%= t("line_items.card.room_label") %>: <%= line_item.room %></p>
<% end %>
```

### i18n

Add to `config/locales/en.yml` under `line_items.card`:

```yaml
en:
  line_items:
    card:
      needs_review: "Needs review"   # added by SPEC-022
      room_label: "Room"             # added by this spec
```

### Out of Scope

- Room field on the line item edit form
- Grouping or filtering line items by room
- A separate `rooms` table or model
- Proposal/Bid Letter Wizard (SPEC-026)
- Clarification/exclusion row auto-detection from CSV

---

## Open Questions

| OQ | Question | Status |
|----|----------|--------|
| OQ-1 | For a multi-room product group, should all room values be stored? | Resolved: first-row room is used for v1 (see AC-2 and Implementation Decisions). SPEC-026 will revisit if multi-room storage per group is required. |
| OQ-2 | Should "Finished Schedule" be a configurable skip pattern? | Deferred — hardcoded is sufficient for v1 |

---

## Test Requirements

**Unit (additions to `spec/services/line_item_csv_importer_spec.rb`):**
- Non-blank col 1 → `line_item.room` is set (whitespace-stripped)
- Blank col 1 → `line_item.room` is `nil`, no error
- `"Finished Schedule"` category row → skipped, no line item
- Only "Finished Schedule" rows → `result.error` non-nil, zero line items
- Mix of "Finished Schedule" and normal rows → only normal rows produce line items

**Request specs:**
- POST import with room value → `line_item.room` set correctly
- POST import with "Finished Schedule" rows → only non-schedule line items created
- Unauthenticated POST → redirects to login

**System spec (`spec/system/room_tracking_spec.rb`):**
1. Import CSV with "Room A" and "Room B" → both cards show room label
2. Import CSV with "Finished Schedule" row + normal row → only one line item appears
3. Line item with `room: nil` → no room label rendered

---

## Dependencies

- SPEC-021 (CSV Import for Estimate Line Items) — `LineItemCsvImporter` extended. Status: done.
- SPEC-022 (Material Short Code and Auto-Population) — also modifies `LineItemCsvImporter`; `group` hash and `persist` must incorporate `room` alongside SPEC-022 additions. Status: in progress.
- SPEC-026 (Proposal/Bid Letter Wizard) — downstream consumer of `room` data.

---

## Implementation Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-27 | Room as plain string on `line_items`, not a separate table | Sufficient for v1; avoids join complexity until the Proposal Wizard spec needs room-level photo attachments |
| 2026-05-27 | "Finished Schedule" skip is exact, case-sensitive | Takeoff software exports a consistent label; partial/case-insensitive match risks false positives |
| 2026-05-27 | First-row room used for multi-room product groups | Total row consolidates quantity; first-row room is the simplest deterministic choice pending SPEC-026 requirements |

---

## Change Log

| Date | Change | Affected IDs | Rationale |
|------|--------|-------------|-----------|
| 2026-05-27 | Initial spec authored | All | Created from Blake (TrimArt) feedback session 2026-05-22 |
