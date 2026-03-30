# Retro Patch: Phase 27 — pending-stub
Generated: 2026-03-29T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 3 | 4 pts |
| Incomplete → backlog | 1 | 2 pts |
| Killed | 0 | — |

Accepted stories: KIND-001a, KAIZEN-001, KAIZEN-002

## 5 Whys: incomplete stories

### QUALITY-005: SonarQube and ReportPortal Helm charts pass HA gate

- **Why 1:** Story failed second review → AC `helm template platform/charts/reportportal/ | grep -c PodDisruptionBudget returns 1` failed; actual output was `2`
- **Why 2:** The ReportPortal chart has two deployable components (API and UI), so the correct HA implementation emits one PDB per component — two PDBs total
- **Why 3:** The AC was written with an exact count assertion (`== 1`) instead of a minimum count assertion (`>= 1`), without accounting for multi-component charts
- **Why 4:** The story description used singular framing ("a PodDisruptionBudget") which anchored the AC author to single-instance thinking, rather than "at least one PDB per component"
- **Why 5:** The SMART measurable check scored this story at 3/5 and flagged missing HA gate script coverage, but did not flag that exact-count assertions are brittle for multi-component charts — the prompt has no rule distinguishing `== N` from `>= N`

**Root cause:** Exact-count assertions in ACs are brittle for multi-component charts. The implementation was correct; the AC was wrong. The SMART measurable scoring prompt does not include guidance on count assertion types (exact vs. minimum), so this class of defect passes grooming unchallenged.

**Decision:** Return to backlog with corrected AC (`returns at least 1`)

**Remediation story:** QUALITY-005r — SMART gate: flag exact count assertions for multi-component charts

## Flow analysis (Heijunka)

- Sprint avg story size: 1.5 pts
- Point distribution: {1: 2, 2: 2}
- Oversized (> 8 pts): 0
- Split candidates (5–8 pts): 0

No flow pathologies. Sprint was well-sized; the single failure was an AC precision error, not a scoping problem.

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Count assertions in ACs must use "at least N" not "== N" for resources that scale with component count** (PDBs, Services, Deployments per component). Exact counts are only valid when the architecture guarantees a fixed number.
- **Multi-component charts (charts with separate API/UI/worker deployments) need one HA resource per deployable component** — a single PDB covering all components is not sufficient for independent disruption control.
- **The SMART measurable prompt should explicitly ask:** "For count-based ACs, does the assertion use `at least` rather than an exact count, unless the exact count is architecturally guaranteed?"

## Quality gate improvements

The SMART measurable scoring prompt in `scripts/ralph/ceremonies/smart.md` (or equivalent) should add:

> **Count assertions:** If an AC uses `grep -c` or similar count checks, verify the assertion uses `at least N` rather than `== N` unless the exact count is guaranteed by architecture. Multi-component charts (separate API, UI, worker pods) will have multiple PDBs, Services, etc.

This would have caught the QUALITY-005 defect at the SMART gate, before any implementation work was done.

## Velocity

| Phase | Stories Accepted | Points |
|-------|-----------------|--------|
| 27 (this sprint) | 3 / 4 | 4 / 6 pts planned |

First-review pass rate: 75.0% (3 of 4 stories accepted on first attempt; QUALITY-005 failed review twice due to AC defect, not implementation defect)

## Returned stories

- **QUALITY-005** → backlog, AC corrected: `returns 1` → `returns at least 1` on both PDB grep checks

## Remediation stories added to backlog

- **QUALITY-005r**: SMART gate: flag exact count assertions for multi-component charts (1 pt, priority 1)

Retro patch → `prd/retro-patch-increment27.md`
