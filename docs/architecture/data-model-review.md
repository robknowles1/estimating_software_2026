# Data Model Review: Estimating Software MVP

**Date:** 2026-04-01
**Reviewer:** architect-agent
**Spec:** SPEC-001

---

## Overview

This document reviews the proposed data model from the MVP spec, identifies gaps, proposes corrections, and provides a complete recommended schema. It also flags architectural risks not captured in the spec's open questions log.

---

## Recommended Complete Schema

The following is the authoritative schema for MVP. Deviations from the spec sketch are called out inline.

### users

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | integer | PK | |
| name | string | not null | |
| email | string | not null, unique (case-insensitive) | |
| password_digest | string | not null | has_secure_password |
| created_at | datetime | not null | |
| updated_at | datetime | not null | |

**Indexes:** `index_users_on_email` (unique).

### clients

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | integer | PK | |
| company_name | string | not null | |
| address | string | null | OQ-07: single address for MVP |
| notes | text | null | |
| created_at | datetime | not null | |
| updated_at | datetime | not null | |

**Indexes:** `index_clients_on_company_name` (non-unique) — supports alphabetical list query.

**ADDED vs. spec:** None. Address kept as a single string per OQ-07 recommendation.

### contacts

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | integer | PK | |
| client_id | integer | not null, FK | |
| first_name | string | not null | |
| last_name | string | not null | |
| title | string | null | |
| email | string | null | |
| phone | string | null | |
| is_primary | boolean | not null, default false | |
| notes | text | null | |
| created_at | datetime | not null | |
| updated_at | datetime | not null | |

**Indexes:** `index_contacts_on_client_id`.

**CONCERN — is_primary uniqueness:** The spec allows multiple contacts but one "primary". The schema must enforce that only one contact per client can have `is_primary = true`. Do not rely on application-layer logic alone. Use a partial unique index: `CREATE UNIQUE INDEX index_contacts_on_client_id_primary ON contacts (client_id) WHERE is_primary = TRUE`. In a Rails migration: `add_index :contacts, :client_id, unique: true, where: "is_primary = TRUE"` (PostgreSQL syntax). Handle the toggle in a model callback or service: when a contact is set to primary, clear `is_primary` on all other contacts for that client in the same transaction.

### estimates

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | integer | PK | |
| client_id | integer | not null, FK | |
| created_by_user_id | integer | not null, FK | |
| title | string | not null | |
| estimate_number | string | not null, unique | e.g., EST-2026-0042 |
| status | string | not null, default 'draft' | enum: draft, sent, approved, lost, archived |
| job_start_date | date | null | OQ-08: use date range, two columns |
| job_end_date | date | null | |
| notes | text | null | |
| client_notes | text | null | Appears on client-facing PDF |
| created_at | datetime | not null | |
| updated_at | datetime | not null | |

**Indexes:**
- `index_estimates_on_client_id`
- `index_estimates_on_created_by_user_id`
- `index_estimates_on_estimate_number` (unique)
- `index_estimates_on_status`
- `index_estimates_on_updated_at` — supports default sort on dashboard

**CHANGES vs. spec:**
- `job_date` split into `job_start_date` / `job_end_date` per OQ-08 recommendation. Both nullable. A single-day job sets only `job_start_date`.
- `status` implemented as a Rails enum backed by a string column (not integer enum). String enums are more readable in SQL queries, more stable under code changes, and human-readable in the database. Define in model: `enum :status, { draft: "draft", sent: "sent", approved: "approved", lost: "lost", archived: "archived" }, default: "draft"`.

**CONCERN — estimate_number generation:** The spec correctly identifies concurrent-save risk. Recommended approach: use a PostgreSQL advisory lock or `SELECT FOR UPDATE` within a transaction. PostgreSQL supports row-level locking natively:

```ruby
# In Estimate model, before_validation on: :create
def assign_estimate_number
  return if estimate_number.present?
  Estimate.transaction do
    year = Date.current.year
    last = Estimate.where("estimate_number LIKE ?", "EST-#{year}-%")
                   .order(:estimate_number)
                   .lock("FOR UPDATE")
                   .last
    next_seq = last ? last.estimate_number.split("-").last.to_i + 1 : 1
    self.estimate_number = "EST-#{year}-#{next_seq.to_s.rjust(4, '0')}"
  end
end
```

The `FOR UPDATE` lock on PostgreSQL prevents concurrent transactions from reading the same last estimate number simultaneously. The unique index on `estimate_number` is the real safety net; the locking strategy is defense-in-depth. For a 2–5 user system this pattern is more than sufficient.

### estimate_sections

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | integer | PK | |
| estimate_id | integer | not null, FK | |
| name | string | not null | |
| position | integer | not null, default 0 | |
| default_markup_percent | decimal(5,2) | not null, default 0.0 | Added — see ADR-001 |
| created_at | datetime | not null | |
| updated_at | datetime | not null | |

**Indexes:**
- `index_estimate_sections_on_estimate_id`
- `index_estimate_sections_on_estimate_id_and_position` (composite) — supports ordered section queries efficiently

**ADDED vs. spec:** `default_markup_percent` — see ADR-001.

### line_items

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | integer | PK | |
| estimate_section_id | integer | not null, FK | |
| catalog_item_id | integer | null, FK | Optional link to catalog source — see ADR-005 |
| description | string | not null | |
| quantity | decimal(10,4) | not null, default 0 | 4 decimal places for fractional quantities (e.g., 12.375 LF) |
| unit | string | null | e.g., LF, SF, EA, HR |
| unit_cost | decimal(10,2) | not null, default 0 | |
| markup_percent | decimal(5,2) | not null, default 0 | |
| position | integer | not null, default 0 | |
| notes | text | null | |
| created_at | datetime | not null | |
| updated_at | datetime | not null | |

**Indexes:**
- `index_line_items_on_estimate_section_id`
- `index_line_items_on_estimate_section_id_and_position` (composite)
- `index_line_items_on_catalog_item_id`

**CHANGES vs. spec:**
- `quantity` precision increased to 4 decimal places. Millwork quantities are often fractional (12.375 linear feet).
- `catalog_item_id` added as nullable FK — see ADR-005.
- `unit_cost` precision: `decimal(10,2)`. Sheet goods, specialty hardware, and engineered lumber can have high per-unit costs; 10 digits of precision is safe.

**CONCERN — no stored total columns:** The spec correctly keeps `extended_cost` and `sell_price` as computed values. Do not add them as columns. The calculation must live in the model as methods, not in a migration. See ADR-001.

### catalog_items

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | integer | PK | |
| description | string | not null | |
| default_unit | string | null | |
| default_unit_cost | decimal(10,2) | null | |
| category | string | null | |
| created_at | datetime | not null | |
| updated_at | datetime | not null | |

**Indexes:**
- `index_catalog_items_on_description`
- `index_catalog_items_on_category`

---

## Association Map

```
User
  has_many :estimates, foreign_key: :created_by_user_id

Client
  has_many :contacts, dependent: :destroy
  has_many :estimates, dependent: :restrict_with_error  ← OQ-03: block deletion if estimates exist
  has_one  :primary_contact, -> { where(is_primary: true) }, class_name: "Contact"

Contact
  belongs_to :client

Estimate
  belongs_to :client
  belongs_to :created_by, class_name: "User", foreign_key: :created_by_user_id
  has_many   :estimate_sections, dependent: :destroy, -> { order(:position) }
  has_many   :line_items, through: :estimate_sections

EstimateSection
  belongs_to :estimate
  has_many   :line_items, dependent: :destroy, -> { order(:position) }

LineItem
  belongs_to :estimate_section
  belongs_to :catalog_item, optional: true

CatalogItem
  has_many :line_items, dependent: :nullify
```

---

## Gaps and Concerns Not in the Spec

### Gap 1: No soft-delete / archive mechanism for Clients or Users

The spec says block client deletion if estimates exist (OQ-03), but offers no way to "retire" a client who is no longer active. A `discarded_at` timestamp (Discard gem pattern) or a simple `active` boolean would allow clients to be hidden from the active list without deleting history. Flag for post-MVP.

### Gap 2: The Excel template has cost categories the spec flattens away

The Excel template's COGS structure separates: Materials, Engineering, Shop Labor, Install Labor, Sub-Install, Countertops, Sub-Other. The spec's `LineItem` model has a single `unit_cost` and `markup_percent`. This means a labor line item and a material line item are structurally identical in the proposed schema — they are distinguished only by description text.

For MVP this is acceptable (the shop wants to move fast). But it means the app cannot automatically break out a labor vs. material cost summary report without parsing description text. If the shop wants cost-category reporting in the future, a `cost_type` enum on `LineItem` will be needed. Consider adding it as a nullable column from day one with no UI to set it — it costs nothing and preserves the upgrade path.

```
line_items
  cost_type  string  null  # values: material, labor, subcontract, equipment, other
```

### Gap 3: Estimate versioning / change order path

Changing an approved estimate is not addressed in the spec. Currently, a status of "approved" does not prevent edits. For MVP this is acceptable — the shop is replacing an Excel file and has no workflow controls at all today. However, if an estimator edits an approved estimate, the original figures are lost. At minimum, consider a model validation warning (not a hard block) when a user attempts to edit an estimate in "approved" status. Flag for post-MVP.

### Gap 4: Estimate number is year-scoped but the spec doesn't address year rollover

`EST-2026-0042` resets to `EST-2027-0001` at year boundary. This is likely the intended behavior (matches how shops number quotes) but should be confirmed with the shop owner (OQ-12). The implementation in the Implementation Notes of this review handles this correctly.

### Gap 5: No audit trail

The spec does not require tracking who edited an estimate or when a status changed. For a shared multi-user tool, this gap will be felt quickly once two estimators modify the same estimate. `updated_at` on the estimate tells you when but not who. At minimum, the `Estimate` model should track `last_modified_by_user_id`. Flag for post-MVP; this is a schema change.

### Gap 6: Line item ordering — position column management

Both `EstimateSection` and `LineItem` have a `position` integer for drag-and-drop ordering. The spec does not specify how `position` is assigned on create or maintained on reorder. Recommended approach: use the `acts_as_list` gem, which handles `position` management (insert, reorder, delete gap-fill) automatically. The gem is lightweight, widely used, and eliminates a class of off-by-one bugs.

```ruby
# Gemfile
gem "acts_as_list"

# EstimateSection model
acts_as_list scope: :estimate

# LineItem model
acts_as_list scope: :estimate_section
```

### Gap 7: Currency and locale

The spec does not mention currency. The shop is presumably USD. All `decimal` monetary columns should be treated as USD dollars. The view layer should format them with `number_to_currency` (Rails helper). If the app is ever used for international jobs with different currencies, this will require a significant schema change. For MVP, no currency column is needed — USD is implicit.

### Gap 8: image_processing gem is in Gemfile but not used

The default Rails 8 Gemfile includes `image_processing ~> 1.2` (for Active Storage variants). Since the MVP spec makes no mention of file uploads, this gem adds unnecessary boot weight. It can be left in but should be flagged as cleanup if Active Storage is never used.

---

## Summary of Schema Additions vs. Spec

| Table | Addition | Reason |
|-------|----------|--------|
| estimate_sections | `default_markup_percent decimal(5,2)` | ADR-001: section-level markup default |
| estimates | `job_date` split into `job_start_date` / `job_end_date` | OQ-08: support date ranges |
| estimates | status as string enum (not integer) | Readability and stability |
| line_items | `catalog_item_id integer null` | ADR-005: track catalog origin |
| line_items | `cost_type string null` | Gap 3: forward compatibility |
| line_items | quantity as `decimal(10,4)` not `decimal` | Fractional millwork quantities |
| All tables | Composite indexes on (parent_id, position) | Query performance for ordered children |
| contacts | Partial unique index on (client_id) WHERE is_primary | Enforce single primary contact |
