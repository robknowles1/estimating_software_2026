---
# Spec: Asana Material Price Sync

**ID:** SPEC-028
**Status:** draft — blocked on Asana API key and field mapping from Blake (TrimArt); sync frequency TBC
**Priority:** medium
**Created:** 2026-05-27
**Author:** spec-agent

---

## Summary

TrimArt tracks material prices — including vendor info and date last updated — in Asana. Estimators currently maintain prices in both Asana and the app manually, which causes drift. This spec introduces a background sync job (`AsanaMaterialSyncJob`) that pulls material pricing data from a nominated Asana project via the Asana REST API and upserts matching records in the app's Materials catalog. Asana is the source of truth; the app is read-only relative to Asana pricing data.

---

## User Stories

- As an estimator, I want material prices in the app to stay current with what is recorded in Asana, so that I do not have to update prices in two places.
- As an estimator, I want to see the date a material's price was last updated (from Asana), so that I can judge whether a price is stale before building an estimate.
- As an estimator, I want vendor information from Asana stored on each material, so that I can refer to the source without switching to Asana.
- As a developer/admin, I want the sync to run automatically on a schedule, so that no manual trigger is required during normal operations.

---

## Acceptance Criteria

**AC-1:** Given the Asana REST API is reachable and a valid PAT is configured, when `AsanaMaterialSyncJob` runs, then for each task returned by the Asana project endpoint:
- a. If a `Material` record with a matching `asana_task_gid` exists, it is updated with the latest name, price, vendor, and `price_updated_at` from Asana.
- b. If no `Material` record with that `asana_task_gid` exists, a new `Material` record is created using the data from Asana.
- c. No `Material` record is deleted during a sync run — removed Asana tasks result only in the local record becoming stale (no automatic discard).

**AC-2:** Given the sync job runs successfully, when a material is upserted, then the following fields are populated from Asana task data:
- `name` — from the Asana task name field (see OQ-C for exact field mapping)
- `default_price` — from the Asana custom field mapped to price (see OQ-C)
- `vendor` — from the Asana custom field mapped to vendor (see OQ-C); stored as a plain string
- `price_updated_at` — from the Asana custom field mapped to date last price update (see OQ-C); stored as a `datetime`
- `asana_task_gid` — the stable Asana task GID; used as the identity key for upserts

**AC-3:** Given a `Material` record was last upserted from Asana and an estimator has since manually edited `default_price` directly in the app, when the sync job next runs, then the Asana value for that field overwrites the manual edit. Asana is the source of truth for all synced fields. (See OQ-D for whether a "manual override" protection flag is in scope.)

**AC-4:** Given the Asana API returns an HTTP error (4xx or 5xx), when `AsanaMaterialSyncJob` runs, then the job raises an error, is retried by Solid Queue according to its default retry policy, and an error is logged. No partial writes are committed from a failed API call.

**AC-5:** Given the sync job runs, when Asana returns tasks whose Asana-side status is marked complete or deleted (i.e., the task no longer appears in the project), then those materials are not automatically discarded. They remain active in the catalog.

**AC-6:** Given valid credentials, when `AsanaMaterialSyncJob` is enqueued and runs, then the job completes without raising and logs a summary line: `"Asana sync complete: X upserted, Y unchanged"`.

**AC-7:** Given the Asana PAT is absent (ENV var / credential not set), when `AsanaMaterialSyncJob` runs, then the job raises a descriptive `ConfigurationError`, does not attempt an API call, and does not modify any `Material` records.

**AC-8:** Given the recurring schedule is configured in `config/recurring.yml`, when Solid Queue's dispatcher runs, then `AsanaMaterialSyncJob` is enqueued automatically at the configured interval (daily or hourly — see OQ-A). No manual trigger is required for normal operations.

**AC-9:** Given an admin or developer needs to trigger a manual sync, when they enqueue `AsanaMaterialSyncJob.perform_later` from the Rails console, then the job runs with the same logic as the scheduled run.

---

## Technical Scope

### Data / Models

#### `materials` table — new columns

Add three columns to the existing `materials` table:

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `asana_task_gid` | string | yes | Stable Asana task GID; used as the upsert key. Index with a unique partial index on non-null values. |
| `vendor` | string | yes | Free-text vendor name or identifier sourced from Asana. |
| `price_updated_at` | datetime | yes | Date the price was last updated in Asana; sourced from an Asana custom field. |

Migration: three `add_column` calls on `:materials`.

Index: `add_index :materials, :asana_task_gid, unique: true, where: "asana_task_gid IS NOT NULL"`.

**`Material` model updates:**

No new validations required (all columns nullable). All sync logic lives in the service, not the model.

### Background Jobs

#### `AsanaMaterialSyncJob` — `app/jobs/asana_material_sync_job.rb`

- Inherits `ApplicationJob`.
- Queue: `default`.
- Retry behaviour: Solid Queue default (3 retries with exponential backoff).
- Calls `AsanaMaterialSyncService.new.call` and logs the result summary.

#### Recurring schedule — `config/recurring.yml`

Add an entry for the new job:

```yaml
production:
  asana_material_price_sync:
    class: AsanaMaterialSyncJob
    queue: default
    schedule: <FREQUENCY>   # see OQ-A — daily or hourly
```

Replace `<FREQUENCY>` with the confirmed value once OQ-A is resolved.

The entry must be nested under `production:` (matching the existing format used by `clear_solid_queue_finished_jobs`). Add a matching entry under `development:` if local testing of the schedule is desired.

### API Integration

#### `AsanaMaterialSyncService` — `app/services/asana_material_sync_service.rb`

Constructor: reads the Asana PAT from `ENV["ASANA_ACCESS_TOKEN"]`. Raises `ConfigurationError` immediately if the PAT is blank.

Public method: `call`

1. Build the Asana REST API URL: `GET https://app.asana.com/api/1.0/projects/<PROJECT_GID>/tasks?opt_fields=gid,name,<custom_field_gids>&limit=100`.
   - Project GID and custom field GIDs stored in ENV vars or credentials (see OQ-B).
   - Handle pagination: follow `next_page.offset` cursor until `next_page` is null. The `offset` value is an opaque string token, not a numeric offset. It is passed as a query parameter (`?offset=<token>`) in subsequent requests. Do not treat it as a page number or record count.
2. HTTP via `Net::HTTP` (stdlib — no Faraday/HTTParty dependency).
   - Set `Authorization: Bearer <PAT>` header.
   - 30-second read timeout, 10-second open timeout.
3. Parse JSON response. For each task in `data`:
   - Extract `gid`, `name`, and custom field values (see OQ-C).
   - Skip tasks where name is blank or price is unparseable (log a warning per skipped task).
4. For each valid task, call `Material.find_or_initialize_by(asana_task_gid: gid)` (see Edge Cases for scoping note) and assign `name`, `default_price`, `vendor`, `price_updated_at`. For any `new_record?` material, call `material.category = 'sheet_good'` before calling `save!`. This is required because `category` is NOT NULL with an inclusion validation; new Asana-sourced materials default to `sheet_good`. Track OQ-F if a different category mapping is later needed, but do not leave it unset.
5. Wrap all upserts in a single `ActiveRecord::Base.transaction`. If any `save!` raises, roll back the entire batch, log the exception prominently via `Rails.logger.error` before re-raising, then re-raise so that Solid Queue's retry policy is triggered. The all-or-nothing transaction is intentional — a partial sync that updates some materials but not others could cause inconsistent pricing across an estimate. A future improvement could add per-record error handling.
6. Return a result struct `{ upserted: Integer, unchanged: Integer }`.

### i18n

No user-facing strings are introduced — sync is a background process with no UI. Log messages use English literals in the service class.

---

## Edge Cases

**E-1 — Soft-deleted material matched by Asana GID.**
The `Material` model uses a manual soft-delete pattern (`discarded_at` column, `scope :active`). `Material.find_or_initialize_by(asana_task_gid: gid)` must be called unscoped — not `Material.active.find_or_initialize_by` — so that previously soft-deleted materials are matched. If a soft-deleted material is found by GID, the sync updates its data fields (`name`, `default_price`, `vendor`, `price_updated_at`) but does **not** clear `discarded_at`. The material remains soft-deleted after the sync. This is the correct behavior: restoring a discarded material is a deliberate admin action, not an automatic sync side-effect.

---

## Out of Scope

- Admin UI to trigger or monitor sync runs
- Writing data back to Asana from the app (sync is one-directional: Asana → app)
- Syncing any entities other than materials
- Stale-price alerting (v2 feature — see Future Work)
- Automatic discard of materials removed from Asana
- Support for multiple Asana workspaces or projects in a single sync run
- OAuth-based Asana authentication (PAT only)
- Webhook-based real-time sync (polling only)

---

## Open Questions

| OQ | Question | Status |
|----|----------|--------|
| OQ-A | Sync frequency — daily (e.g., 2 am) or hourly? | **Unresolved.** Confirm with Blake. |
| OQ-B | Where should Asana PAT and project GID be stored — ENV vars, Rails encrypted credentials, or both? | **Unresolved.** Recommend ENV vars for CI/staging parity. |
| OQ-C | What are the exact Asana field names / custom field GIDs for price, vendor, and date last price update? | **Blocked — no API key or field mapping received yet.** Primary blocker for implementation. |
| OQ-D | Should the sync always overwrite local manual edits, or is a per-material "lock sync" toggle needed? | **Unresolved.** Current spec: Asana always overwrites. |
| OQ-E | Retry behaviour and alerting on repeated sync failures? | **Unresolved.** Solid Queue default (3 attempts) assumed. |
| OQ-F | What `category` value should be assigned to new materials created by sync? | **Resolved for v1:** new materials created by sync default to `category: 'sheet_good'`. Revisit if Asana field mapping reveals category data (OQ-C). |

---

## Dependencies

- SPEC-014 (Materials Rework) — `materials` table and `Material` model must exist. Status: done.
- Asana PAT from Blake (TrimArt) — required before implementation can begin.
- **IMPLEMENTATION BLOCKER — OQ-C (Asana API key + field mapping from Blake):** AC-2 is entirely unimplementable until OQ-C is resolved. No developer should begin implementation until this dependency is satisfied.
- Asana project GID and custom field GIDs — required before implementation can begin (OQ-C).
- Solid Queue recurring scheduler — present in `config/recurring.yml`.

---

## Future Work (v2)

**Stale-price alerting:** When a material's `price_updated_at` is older than a configurable threshold (e.g., 1 week), the system auto-compiles a list of those materials and sends an email to the vendor asking for updated pricing. The purchaser is CC'd so replies go directly to them. The `price_updated_at` column introduced in this spec is intentionally designed to support this feature.

---

## Implementation Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-27 | Use `Net::HTTP` rather than Faraday | Faraday is not in the Gemfile; no new gem dependency for a single integration |
| 2026-05-27 | `asana_task_gid` as the stable upsert key | Task names in Asana can be renamed; GIDs cannot |
| 2026-05-27 | Transaction wraps all upserts in a single sync run | Prevents a half-applied sync from leaving the catalog in an inconsistent state |
| 2026-05-27 | Asana always overwrites local edits on synced fields | Keeps Asana as the single source of truth; avoids conflict resolution logic until OQ-D is resolved |

---

## Change Log

| Date | Change | Affected IDs | Rationale |
|------|--------|-------------|-----------|
| 2026-05-27 | Initial draft | All | Created from Blake (TrimArt) feedback session 2026-05-22 |
| 2026-05-27 | Review fixes applied | AC-4, AC-8, E-1 (new), OQ-F, Dependencies | Fix recurring.yml format to environment-namespaced form; make category assignment a firm requirement; add soft-delete edge case E-1; clarify pagination offset token; add transaction failure logging requirement; elevate OQ-C as implementation blocker; close OQ-F |
