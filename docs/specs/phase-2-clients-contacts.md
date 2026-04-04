# Spec: Phase 2 — Client and Contact Management

**ID:** SPEC-004
**Status:** ready
**Priority:** high
**Created:** 2026-04-04
**Author:** pm-agent

---

## Summary

This phase builds the shared client database that all estimators can access. A client record represents a company. Each client can have one or more named contacts (people). One contact per client may be designated as primary. Clients with existing estimates cannot be deleted, preserving estimate history. This phase establishes the CRUD patterns (controller structure, form partials, Turbo Frame conventions) that subsequent phases will follow.

## User Stories

- As an estimator, I want to see a list of all clients so that I can quickly find a client when starting a new estimate.
- As an estimator, I want to add a new client with their company name and contact details so that I can associate them with estimates.
- As an estimator, I want to edit an existing client record so that our client list stays accurate.
- As an estimator, I want to delete a client that was added by mistake, but not one that has estimates attached to it, so that our estimate history is preserved.

## Acceptance Criteria

1. Given at least one client exists, when an estimator navigates to the Clients page, they see a list of client company names sorted alphabetically.
2. Given no clients exist, when an estimator navigates to the Clients page, they see an empty state with a prompt to add the first client.
3. Given a valid company name is submitted, when an estimator submits the new client form, the client is saved and they are redirected to the client detail page.
4. Given a missing company name, when the new client form is submitted, a validation error is displayed and no record is saved.
5. Given a saved client, when an estimator navigates to the client detail page, they can add one or more contacts (first name, last name, title, email, phone).
6. Given multiple contacts on a client, when one is marked as primary, all other contacts for that client have their primary flag cleared in the same save operation.
7. Given multiple contacts on a client, at most one contact may have `is_primary = true` at any time. The database enforces this with a partial unique index.
8. Given an existing client, when an estimator updates any field and saves, the updated values are persisted and displayed.
9. Given a client with no associated estimates, when an estimator clicks Delete, the client and all its contacts are permanently removed.
10. Given a client with one or more associated estimates, when an estimator attempts to delete the client, the action is blocked, an error message is shown, and no records are deleted.
11. Given a saved contact, when an estimator edits and saves the contact, the updated values are reflected on the client detail page.
12. Given a saved contact, when an estimator deletes the contact, it is removed from the client detail page.

## Technical Scope

### Data / Models

- New model: `Client`
  - `id`, `company_name string not null`, `address string null`, `notes text null`, `created_at`, `updated_at`
  - Validates presence of `company_name`.
  - `has_many :contacts, dependent: :destroy`
  - `has_many :estimates, dependent: :restrict_with_error`
  - `has_one :primary_contact, -> { where(is_primary: true) }, class_name: "Contact"`
  - Index: `index_clients_on_company_name` (non-unique).

- New model: `Contact`
  - `id`, `client_id integer not null FK`, `first_name string not null`, `last_name string not null`, `title string null`, `email string null`, `phone string null`, `is_primary boolean not null default false`, `notes text null`, `created_at`, `updated_at`
  - Validates presence of `first_name` and `last_name`.
  - `belongs_to :client`
  - Before save callback: if `is_primary` is set to `true`, clear `is_primary` on all other contacts for the same client in the same transaction.
  - Index: `index_contacts_on_client_id`.
  - Partial unique index: `index_contacts_on_client_id_primary` on `(client_id) WHERE is_primary = TRUE` (PostgreSQL syntax).

### API / Logic

- `ClientsController`: `index`, `show`, `new`, `create`, `edit`, `update`, `destroy` — all require login.
  - `destroy`: check for associated estimates; if present, render an error flash and redirect (do not delete).
- `ContactsController`: nested under clients. Actions: `new`, `create`, `edit`, `update`, `destroy` — all require login.
- Routes: `resources :clients do; resources :contacts, only: [:new, :create, :edit, :update, :destroy]; end`

### UI / Frontend

- Client list (`/clients`): alphabetically sorted table of company names with links to detail pages. Empty state with "Add Client" CTA.
- Client detail page (`/clients/:id`): shows all client fields, a list of contacts with edit/delete links per contact, and an "Add Contact" button.
- Client form (new/edit): company name, address, notes fields.
- Contact form (new/edit): first name, last name, title, email, phone, is_primary checkbox. Can be rendered inline via Turbo Frame on the client detail page or as a separate form page — developer's choice, but the result must update the client detail page without a full page reload.
- Error states: inline validation messages on form fields. Flash notice for blocked deletion.

### Background Processing
- None.

## Test Requirements

### Unit Tests

- `Client`: validates presence of `company_name`.
- `Client`: `restrict_with_error` prevents deletion when estimates exist.
- `Contact`: validates presence of `first_name` and `last_name`.
- `Contact`: setting `is_primary = true` clears `is_primary` on sibling contacts.
- `Contact`: database-level partial unique index prevents two primary contacts for the same client.

### Integration Tests

- `GET /clients`: returns sorted list of clients.
- `POST /clients` with valid params: creates client, redirects to show.
- `POST /clients` without `company_name`: returns 422, shows error.
- `POST /clients/:id/contacts` with valid params: creates contact, appears on client detail.
- `DELETE /clients/:id` with no estimates: destroys client and contacts.
- `DELETE /clients/:id` with existing estimates: returns error, client record intact.

### End-to-End Tests

- Create a client with two contacts. Mark the second contact as primary. Confirm the first contact's primary flag is cleared.
- Attempt to delete a client with estimates. Confirm the block message appears and no deletion occurs.

## Out of Scope

- Soft-delete / archive for clients (flagged as post-MVP gap in data-model-review.md).
- Client address split into billing vs. job site (OQ-07 resolved: single address for MVP).
- Activity log or CRM-level contact history.
- Importing clients from a CSV or external system.

## Open Questions

- OQ-03 is resolved: deletion is blocked if estimates exist.
- OQ-07 is resolved: single address field.
- There are no blockers for this phase.

## Dependencies

- SPEC-003 (Phase 1 — Authentication) must be complete. The `require_login` concern must exist before any controller in this phase is built.
