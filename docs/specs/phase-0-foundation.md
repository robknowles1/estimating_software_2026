# Spec: Phase 0 — Foundation

**ID:** SPEC-002
**Status:** done
**Priority:** high
**Created:** 2026-04-04
**Author:** pm-agent

---

## Summary

Before any feature work begins, the project environment must satisfy several hard prerequisites. This phase is not a user-visible feature — it is the scaffolding every other phase depends on. Skipping or partially completing any item here will cause later phases to fail at runtime or produce incorrect results.

## User Stories

- As a developer, I want the Gemfile to include all required gems, so that model features like password hashing and position management work correctly from day one.

## Acceptance Criteria

1. Given the Gemfile in the repo root, when `bundle install` is run, `bcrypt ~> 3.1.7` is present and resolves without error.
2. Given the Gemfile, when `bundle install` is run, `acts_as_list` is present and resolves without error.
3. Given `bundle install` has been run, when the Rails console is started, `BCrypt::Password` is available without a `LoadError`.
4. Given `bundle install` has been run, when the Rails console is started, `ActsAsList` is available without a `LoadError`.
5. Given the `docs/specs/` and `docs/architecture/` directories, when a developer opens the repo, both directories exist with all current documents committed.

## Technical Scope

### Data / Models
- No schema changes. This phase contains no migrations.

### API / Logic
- Uncomment `gem "bcrypt", "~> 3.1.7"` in `Gemfile`.
- Add `gem "acts_as_list"` to `Gemfile`.
- Run `bundle install` and commit the updated `Gemfile` and `Gemfile.lock`.

### UI / Frontend
- None.

### Background Processing
- None.

## Test Requirements

### Unit Tests
- None specific to this phase. Phase 1 tests will implicitly verify bcrypt is present.

### Integration Tests
- None.

### End-to-End Tests
- None.

## Out of Scope

- Any model, migration, controller, or view work.
- Resolving open questions with the shop owner (those are tracked per phase).

## Open Questions

- None blocking this phase.

## Dependencies

- None. This is the first spec in the build order.
