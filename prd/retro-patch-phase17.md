# Retro Patch: Phase 17 — restructure
Generated: 2026-03-29T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted (reviewed: true) | 3 | 5 pts |
| Implemented, unreviewed → returned to backlog | 1 | 1 pt |
| Killed | 0 | — |

**Note on KAIZEN-003:** This story reached `passes: true` (Ralph completed it) before the retro
ceremony ran, but the review ceremony had not yet run to confirm it. It is returned to backlog
with `passes: true` preserved — the review ceremony in the next sprint can accept it immediately
without re-implementation.

---

## 5 Whys: stories returned to backlog

### KAIZEN-003: Kaizen: Fix attempts field — initialize to 0, increment only on review re-open

**State at retro:** `passes: true, reviewed: false` — implemented, awaiting review.

- **Why 1:** Story reached `passes: true` just before retro fired → Ralph implemented it as the last story in the sprint queue
- **Why 2:** KAIZEN-003 had priority 14 — lowest in the sprint — so it was processed last, after the three RESTRUCTURE stories
- **Why 3:** The review ceremony never ran for KAIZEN-003 because retro was invoked immediately after Ralph's last iteration
- **Why 4:** The ceremonies pipeline does not automatically run review before retro for tail-of-sprint stories
- **Why 5:** The sprint included a low-priority kaizen story alongside high-priority structural work, guaranteeing the kaizen story would always land at the sprint boundary where review time is tightest

**Root cause:** Stories at the end of the sprint priority queue consistently end up in `passes: true, reviewed: false` purgatory at retro time. The ceremonies pipeline fires retro on wall-time or manual invocation — it does not wait for all `passes: true` stories to complete their review cycle. Low-priority stories added to feature sprints are the most vulnerable to this pattern.

**Decision:** Return to backlog with `passes: true` preserved. Review ceremony can accept it in the next sprint without re-implementation.

**Remediation story:** KAIZEN-004r — Add a pre-retro guard: before firing retro, check if any `passes: true, reviewed: false` stories exist and auto-invoke review on them first.

---

## Flow analysis

| Metric | Value |
|--------|-------|
| Sprint avg story size | 1.5 pts |
| Point distribution | {1: 2, 2: 2} |
| Oversized (> 8 pts) | 0 |
| Split candidates (5–8 pts) | 0 |

No flow issues. All stories well-sized. The unreviewed story is a ceremony sequencing issue, not a sizing issue.

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **The retro→review ordering gap.** When Ralph completes a story just before retro fires, the review ceremony hasn't had a chance to run. These stories are not "failed" — they are "done but unverified." Returning them to backlog with `passes: true` is the correct handling; they will be accepted in the next sprint's review ceremony immediately.
- **Low-priority stories in feature sprints always land at the sprint boundary.** Priority 14 in a 4-story sprint means it runs last. Last means it may miss the review window. If a kaizen story matters enough to be in a sprint, it should have priority ≤ 5.
- **Pre-retro should drain pending reviews.** A simple pre-retro guard (`if any passes:true reviewed:false → run review first`) would prevent the `advance.py` limbo error from blocking the pipeline.

---

## Quality gate improvements

- **ceremonies.sh pre-retro guard:** Before invoking retro, check for `passes: true, reviewed: false` stories. If found, run review ceremony first. This prevents the advance.py limbo error that requires manual retro intervention.
- **Planning ceremony rule:** Kaizen stories (identified by `id` prefix `KAIZEN-`) must have `priority <= 5` when added to a sprint. Otherwise they will always be stranded.

---

## Velocity

| Increment | Name | Points accepted | Stories accepted | First-pass rate |
|-----------|------|----------------|-----------------|-----------------|
| 17 | restructure | 5 pts | 3 / 4 stories fully accepted | 75.0% (3 of 4 with empty reviewNotes) |

*Prior increments stripped from manifest by advance.py — see git history for full velocity series.*

---

Retro patch → prd/retro-patch-phase17.md
