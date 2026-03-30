# Retro Patch: Phase 35 — pending-stub (HA hardening + backlog hygiene)
Generated: 2026-03-30T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 5 | 11 pts |
| Incomplete → backlog | 0 | — |
| Killed | 0 | — |

## 5 Whys: incomplete stories

None. All stories were accepted this sprint.

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- HA hardening stories are highly parallelisable when scoped to a single chart with purely static-verifiable ACs (helm lint + helm template). Five charts completed in one sprint with zero rework.
- Backlog hygiene (marking stale `status:open` entries as `status:complete`) must be an explicit story — the grooming ceremony flags but does not update lifecycle status. Repeat as needed each time stale entries accumulate.
- When a story's measurable AC uses "shows a value >= 2" (visual inspection) rather than a binary exit-code command, SMART measurable score is capped at 4. Future HA stories should use `grep -E 'replicaCount:[[:space:]]+[2-9]'` so the gate is self-verifying.

## Quality gate improvements

- The SMART ceremony's measurable dimension should explicitly ask: "Does each AC exit 0 on success and non-zero on failure, with no human interpretation required?" If the answer is no, score at most 4 and suggest a binary-exit reformulation.

## Velocity

Sprint points accepted: 11 / 8 planned (over-delivered — capacity was 12, planned was 8)
First-review pass rate: 100% (5 of 5 accepted on first review)

Prior increments (from manifest):
- Increment 34: 11 pts, 6 stories, 100% pass rate
