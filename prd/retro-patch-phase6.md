# Retro Patch: Phase 6 — observability
Generated: 2026-03-24T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 0 | 0 pts |
| Incomplete → backlog | 1 (025) | 2 pts |
| Killed | 1 (026) | 3 pts — superseded by 026a/b/c |

## 5 Whys: incomplete stories

### 025: Helm chart — kube-prometheus-stack
- Why 1: Story didn't pass → zero attempts; it was never implemented
- Why 2: No Ralph iterations ran against phase 6 before the retro was triggered
- Why 3: The retro ceremony was called immediately after phase 5 closed, without first running `ralph.sh` on phase 6
- Why 4: Ceremony orchestration (ceremonies.py / ralph.sh) does not enforce that at least one implementation attempt must occur before retro is allowed
- Why 5: The sprint lifecycle has no "minimum work attempted" guard — retro can fire on a brand-new sprint

**Root cause**: Retro ceremony has no guard preventing it from closing a sprint with zero implementation attempts. This is an orchestration gap, not a story-quality problem.
**Decision**: Return to backlog as-is. Story is well-formed (SMART scores 3–5, attempts=0). Pull into the next observability sprint.
**Remediation story**: none needed for this specific gap — the planning ceremony fix (037r) addresses the structural process issue.

---

### 026: Helm charts — Loki, Thanos, Tempo (composite)
- Why 1: Story didn't pass → zero attempts; never implemented
- Why 2: No Ralph iterations ran (same sprint-closed-early root cause as 025)
- Why 3: Story was pulled into the sprint despite SMART achievable score of 2, with explicit notes: "NOT READY — split into 026a, 026b, 026c"
- Why 4: The planning ceremony (or operator) did not enforce the achievable threshold; it pulled a score-2 story anyway
- Why 5: No hard gate exists in the planning ceremony that rejects achievable < 3; the SMART score is advisory-only

**Root cause**: The SMART achievable gate is advisory, not enforced. A story explicitly flagged as NOT READY (achievable=2) was pulled into a sprint. The split stories (026a, 026b, 026c) already existed in the backlog, making this a planning inconsistency — both the composite and the splits were present simultaneously.
**Decision**: Kill 026. The split stories (026a, 026b, 026c) are already in the backlog and supersede it.
**Remediation story**: `037r` — Planning ceremony: enforce SMART achievable threshold before sprint pull

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Retro on zero-attempt sprints**: The retro ceremony can fire on a sprint where zero implementation ran. Consider adding a guard: if all stories have `attempts: 0`, emit a warning and require `--force` to close. Closing a never-started sprint is information loss.
- **SMART achievable=2 means DO NOT PULL**: The achievable score is not a suggestion. If achievable < 3 and the SMART notes say "NOT READY", the planning ceremony must refuse the pull. Enforce this as a hard gate (exit non-zero) not a soft warning.
- **Backlog consistency**: When splitting a story, remove or kill the composite story from the backlog immediately. Having both 026 and 026a/b/c in the system causes confusion about which is authoritative.

## Quality gate improvements

- **Planning ceremony**: Add `achievable_threshold = 3`; reject stories with `smart.achievable < threshold` with exit code 1 and a message naming the story ID, score, and required action (split or rescore).
- **Retro ceremony**: Add a check: if `len([s for s in stories if s.get('attempts', 0) > 0]) == 0`, print "WARNING: No stories were attempted this sprint. Closing anyway — but verify this is intentional."

## Velocity

| Phase | Points completed | Stories accepted | Review pass rate |
|-------|-----------------|-----------------|-----------------|
| 0 (ceremonies) | 15 | 7 | 100% |
| 1 (bootstrap) | 14 | 6 | 100% |
| 2 (foundations) | 10 | 4 | 75% |
| 2h (ci-hardening) | 5 | 4 | 100% |
| 2i (integration) | 13 | — | 100% |
| 3 (gitops-engine) | 12 | 2 | 100% |
| 4 (autarky) | 13 | 5 | 80% |
| 5 (security) | 12 | 5 | 20% |
| **6 (observability)** | **0** | **0** | **0%** |

Sprint points accepted: 0 / 5 planned
First-review pass rate: 0% (0 of 2 — sprint closed before any attempts)

Retro patch → prd/retro-patch-phase6.md
