# Retro Patch: Increment 29 — pending-stub
Generated: 2026-03-29T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 4 | 5 pts |
| Incomplete → backlog | 5 | 6 pts |
| Killed | 0 | — |

## 5 Whys: incomplete stories

All 5 incomplete stories share a common root cause. Individual entries below reference the
shared analysis.

---

### CEREMONY-003: Rename retro-patch-phase*.md → retro-patch-increment*.md
- Why 1: Story was never started (0 attempts) → execute ceremony did not reach priority-3 work
- Why 2: Execute cycle was consumed by 4 already-accepted stories pulled into the sprint → pipeline exhausted before reaching new stories
- Why 3: Sprint was assembled with 4 stories that were already `passes:true, reviewed:true` — they needed no implementation, only confirmation
- Why 4: Plan ceremony treats already-accepted stories identically to implementation-pending ones in capacity math — both count as full story points
- Why 5: Capacity model has no concept of "pre-accepted" vs "needs implementation" — so a sprint can fill with near-zero-effort confirmations and crowd out real work

**Root cause**: Plan ceremony capacity model does not distinguish pre-accepted review-confirmation stories from new implementation work. Sprint 29 carried 4 already-reviewed stories (44% of capacity) that required no execution, leaving 5 new stories with zero effective execution slots.

**Decision**: Return to backlog as-is (story is well-defined and achievable — just needs execution capacity)

**Remediation story**: CEREMONY-011 — Plan ceremony: warn when >50% of sprint capacity is already-accepted stories

---

### DEVEX-007a: code-server chart: define toolchainInit values (image ref, workspace bin path)
- Why 1: Story was never started (0 attempts) → execute ceremony did not reach priority-4 work
- Why 2–5: Same as CEREMONY-003 above

**Root cause**: Same as CEREMONY-003 — sprint capacity crowded by pre-accepted stories.

**Decision**: Return to backlog as-is

**Remediation story**: CEREMONY-011 (shared)

---

### HA-006: Bootstrap cost-gate script validates chart resource requests fit within per-node budget
- Why 1: Story was never started (0 attempts) → execute ceremony did not reach priority-4 work
- Why 2–5: Same as CEREMONY-003 above

**Root cause**: Same as CEREMONY-003 — sprint capacity crowded by pre-accepted stories.

**Decision**: Return to backlog as-is

**Remediation story**: CEREMONY-011 (shared)

---

### CEREMONY-004: Remove legacy 'phase' field from backlog stories
- Why 1: Story was never started (0 attempts) → execute ceremony did not reach priority-4 work
- Why 2–5: Same as CEREMONY-003 above

**Root cause**: Same as CEREMONY-003 — sprint capacity crowded by pre-accepted stories.

**Decision**: Return to backlog as-is

**Remediation story**: CEREMONY-011 (shared)

---

### HA-007: GitHub Actions workflow: ha-gate.sh --dry-run runs on every PR touching platform/charts/
- Why 1: Story was never started (0 attempts) → execute ceremony did not reach priority-5 work
- Why 2–5: Same as CEREMONY-003 above

**Root cause**: Same as CEREMONY-003 — sprint capacity crowded by pre-accepted stories.

**Decision**: Return to backlog as-is

**Remediation story**: CEREMONY-011 (shared)

---

## Flow analysis (Heijunka check)

- Sprint avg story size: 1.2 pts
- Point distribution: {1: 7 stories, 2: 2 stories}
- Oversized (> 8 pts): 0
- Split candidates (5–8 pts): 0

No sizing issues. All stories were appropriately small. The failure mode was not oversized
stories but pre-accepted stories masquerading as new work capacity.

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Pre-accepted story crowding**: When stories with `passes:true, reviewed:true` are pulled
  into a sprint, they consume ceremony execution pipeline without requiring implementation work.
  If they make up a large fraction of the sprint, new implementation stories will never be
  reached. The plan ceremony should warn when pre-accepted stories exceed 50% of sprint capacity.

- **Capacity math vs. execution capacity**: Story points in a sprint file do not equal
  "things that need implementation." The plan ceremony must audit the mix of pre-accepted
  vs. implementation-pending stories before closing a sprint plan.

---

## Quality gate improvements

**Plan ceremony sprint composition check**: After assembling a sprint, compute the ratio of
already-accepted stories (passes:true, reviewed:true) to implementation-pending stories
(passes:false). If already-accepted stories make up > 50% of sprint points, emit a WARNING:
"Sprint contains N pre-accepted stories (X pts, Y% of capacity) that require no new work.
Consider removing them to free execution capacity for implementation stories."

This would have caught the sprint 29 pattern before execution began.

---

## Velocity

| Increment | Points | Stories Accepted | Pass Rate |
|-----------|--------|-----------------|-----------|
| 29 | 5 pts | 4 / 9 | 44.4% |

Sprint points accepted: 5 / 11 planned
First-review pass rate: 44.4% (4 of 9 — all 4 accepted stories passed on first attempt;
5 unstarted stories count against total)

Retro patch → prd/retro-patch-increment29.md
