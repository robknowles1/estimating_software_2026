# Specs Index

| ID | Title | Status | Priority | Created |
|---|---|---|---|---|
| SPEC-001 | [Estimating Software MVP](./estimating_software_mvp.md) | draft | high | 2026-04-01 |
| SPEC-002 | [Phase 0 — Foundation](./phase-0-foundation.md) | done | high | 2026-04-04 |
| SPEC-003 | [Phase 1 — Authentication and User Management](./phase-1-authentication.md) | done | high | 2026-04-04 |
| SPEC-004 | [Phase 2 — Client and Contact Management](./phase-2-clients-contacts.md) | done | high | 2026-04-04 |
| SPEC-005 | [Phase 3 — Estimate Scaffold and Sections](./phase-3-estimates-sections.md) | ready | high | 2026-04-04 |
| SPEC-006 | [Phase 4 — Line Items and Real-Time Totals](./phase-4-line-items-totals.md) | ready | high | 2026-04-04 |
| SPEC-007 | [Phase 5 — Catalog and Line Item Autocomplete](./phase-5-catalog-autocomplete.md) | draft | medium | 2026-04-04 |
| SPEC-008 | [Phase 6 — Document Output](./phase-6-document-output.md) | draft | medium | 2026-04-04 |
| SPEC-009 | [Phase 7 — Polish and Hardening](./phase-7-polish.md) | draft | low | 2026-04-04 |

---

## Build Order and Dependencies

```
SPEC-002 (Phase 0: Foundation)
  └── SPEC-003 (Phase 1: Auth)
        └── SPEC-004 (Phase 2: Clients)
              └── SPEC-005 (Phase 3: Estimates + Sections)
                    └── SPEC-006 (Phase 4: Line Items + Totals)  ← core loop
                          ├── SPEC-007 (Phase 5: Catalog + Autocomplete)
                          └── SPEC-008 (Phase 6: Document Output)
                                └── SPEC-009 (Phase 7: Polish)
```

## Status Key

| Status | Meaning |
|---|---|
| draft | Written but open questions remain or acceptance criteria need refinement |
| ready | All AC are unambiguous, test requirements are complete, no blocking open questions — developer can start |
| in-progress | Active development |
| done | All acceptance criteria met and tests passing |

## Blocked Items

| Spec | Blocker |
|---|---|
| SPEC-007 (Phase 5) | OQ-02: Estimator validation session must confirm Pattern C (freeform + autocomplete) UX before autocomplete Stimulus controller is built |
| SPEC-008 (Phase 6) | OQ-05 and OQ-09 should be confirmed with shop owner before shipping (not hard blockers — placeholders exist) |
