# Spec: Phase 1 — Authentication and User Management

**ID:** SPEC-003
**Status:** done
**Priority:** high
**Created:** 2026-04-04
**Author:** pm-agent

---

## Summary

Every route in the application is protected. This spec covers the User model, session-based login/logout, and a basic user management interface that allows logged-in users to create additional accounts. There is no self-registration — only an authenticated user can create another user (see ADR-004). A seed user is provided for the initial login.

## User Stories

- As an estimator, I want to log in with my email and password so that my work is private and attributable to me.
- As a logged-in user, I want to log out so that my session is closed on shared devices.
- As an admin-level user, I want to create accounts for new team members so that only authorized staff can access the system.
- As a developer, I want all unauthenticated requests to redirect to the login page so that no data is exposed publicly.

## Acceptance Criteria

1. Given a registered user with correct credentials, when they submit the login form, they are redirected to the estimates dashboard.
2. Given a registered user with an incorrect password, when they submit the login form, an error message is shown and the session is not created.
3. Given an email that does not exist, when the login form is submitted, an error message is shown and the session is not created.
4. Given a logged-in user, when they click Log Out, their session is destroyed and they are redirected to the login page.
5. Given an unauthenticated request to any protected route, when the request is made, the browser is redirected to the login page.
6. Given a logged-in user, when they navigate to the Users section and submit a new user form with a name, valid email, and password, the user is created and appears in the user list.
7. Given a new user form with a missing name or missing email, when the form is submitted, a validation error is shown and no record is saved.
8. Given a new user form with a duplicate email, when the form is submitted, a validation error is shown and no record is saved.
9. Given the database has been seeded, when `db:seed` is run, at least one user record exists that can be used for the initial login.

## Technical Scope

### Data / Models

- New model: `User`
  - `id`, `name string not null`, `email string not null unique`, `password_digest string not null`, `created_at`, `updated_at`
  - Validates presence of name and email; validates uniqueness of email (case-insensitive); validates format of email.
  - Uses `has_secure_password` (requires bcrypt from SPEC-002).
- Migration: create `users` table with unique index on `email`.

### API / Logic

- `Authentication` concern on `ApplicationController`: `require_login` before action, `current_user` helper, `logged_in?` helper.
- `SessionsController`: `new` (login form), `create` (authenticate and set session), `destroy` (clear session).
- `UsersController`: `index`, `new`, `create`, `edit`, `update` — all require login. No `destroy` action for MVP (do not expose user deletion).
- Routes: `resource :session, only: [:new, :create, :destroy]`; `resources :users, only: [:index, :new, :create, :edit, :update]`.
- Seed: `db/seeds.rb` creates one initial user (name, email, password). The password must be documented in a comment in the seeds file for developer reference.

### UI / Frontend

- Login page: email field, password field, submit button. Accessible via `/session/new` (root route when unauthenticated).
- User list page: table of name and email for all users; link to add a new user.
- New/edit user form: name, email, password, password confirmation fields.
- Nav bar or layout header: shows current user's name and a Log Out link on all authenticated pages.

### Background Processing
- None.

## Test Requirements

### Unit Tests

- `User`: valid record saves with correct fields.
- `User`: `authenticate` returns the user for a correct password, `false` for an incorrect password.
- `User`: email uniqueness validation rejects a duplicate (case-insensitive).
- `User`: presence validations reject blank name and blank email.

### Integration Tests

- `POST /session` with valid credentials: returns redirect to dashboard, sets session cookie.
- `POST /session` with invalid credentials: returns 422, does not set session.
- `DELETE /session`: destroys session and redirects to login.
- `GET /estimates` (or any protected route) without a session: redirects to `/session/new`.
- `POST /users` with valid params: creates user and redirects to user list.
- `POST /users` with duplicate email: returns 422, shows error.

### End-to-End Tests

- Full login/logout flow: navigate to protected page, get redirected to login, log in, land on dashboard, log out, confirm redirect to login.

## Out of Scope

- Password reset / forgot password flow.
- Role-based access control.
- User avatar or profile image.
- Email delivery of any kind.
- OAuth or third-party login.

## Open Questions

- OQ-10 is resolved (ADR-004): no self-registration; any logged-in user may create other users.
- There is no blocker. This phase is ready to build.

## Dependencies

- SPEC-002 (Phase 0 — Foundation) must be complete. `bcrypt` must be in the bundle before `has_secure_password` will work.
