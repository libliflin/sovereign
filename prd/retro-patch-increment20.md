# Retro Patch: Increment 20 — kind-integration
Generated: 2026-03-29T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 1 | 1 pt |
| Incomplete → backlog | 5 | 8 pts |
| Killed | 0 | — |

---

## 5 Whys: incomplete stories

### KAIZEN-007r: Plan ceremony — always queue a pending increment stub
- Why 1: Story not implemented → sprint closed (retro invoked manually) before Ralph ran this story
- Why 2: Ralph only completed the priority-0 ANDON story before retro was triggered externally
- Why 3: Manual retro invocation interrupted a sprint that was just beginning — only 1/6 stories had been iterated
- Why 4: No mechanism prevents retro from running when Ralph has barely started the sprint
- Why 5: The pre-retro guard (KAIZEN-004r) that would block premature retro invocation is itself unimplemented

**Root cause**: Retro ceremony was invoked before the sprint cycle could run to completion. The ANDON fix was merged, but the remaining 5 stories received zero Ralph iterations.
**Decision**: Return to backlog as-is (already present; well-specified 2-pt story)
**Remediation story**: None needed — root cause is operational (manual retro), not systemic in the story itself.

---

### KAIZEN-004r: Pre-retro guard — auto-run review before retro if passes:true stories exist
- Why 1: Story not implemented → same as KAIZEN-007r (sprint closed early)
- Why 2: Story has SMART concern: AC2 hard-codes `increment-17-restructure.json` as test target — a completed sprint — making the gate untestable in the current environment
- Why 3: SMART review flagged this (specific=4, measurable=4) but the story was pulled into sprint without fixing the AC
- Why 4: The plan ceremony doesn't require SMART scores ≥4 across all dimensions before pulling a story
- Why 5: No AC fixup gate exists between SMART scoring and sprint planning

**Root cause**: AC2 references a wrong sprint file, making the story's measurability gate broken at source. Story also didn't get iterated due to early retro.
**Decision**: Return to backlog — update AC2 to use a temp fixture, not `increment-17`
**Remediation**: Backlog story updated in-place (KAIZEN-004r AC2 fixed below in backlog changes).

---

### KIND-001: kind cluster bootstrap produces a valid cluster-values.yaml
- Why 1: Story not implemented → sprint closed before Ralph iterated it (priority 2, below priority-0/1 items)
- Why 2: Even if Ralph had iterated, SMART achievable=3 flags 8 integration points in a single story
- Why 3: Story bundles: bootstrap.sh authoring, 3-node kind cluster, Cilium install, cert-manager, sealed-secrets, MinIO, local-path-provisioner, contract/validate.py — eight distinct deliverables
- Why 4: Grooming ceremony pulled KIND-001 in as-is despite achievable=3 flag, without splitting
- Why 5: Grooming ceremony lacks a hard gate: "if achievable < 4, split before pulling"

**Root cause**: KIND-001 was accepted into the sprint with a known achievability concern (score 3). Eight integration points exceed a single Ralph iteration budget. Story needs splitting before it can realistically be delivered.
**Decision**: Split → KIND-001a (bootstrap + cluster + contract) and KIND-001b (Cilium + cert-manager + sealed-secrets + MinIO)
**Remediation stories**: KIND-001a and KIND-001b added to backlog. KIND-001 marked as superseded in backlog.

---

### KAIZEN-005: Rename retro-patch-phase*.md → retro-patch-increment*.md
- Why 1: Story not implemented → sprint closed before iteration (priority 3)
- Why 2: Priority ordering is correct — below ANDON and process-fix stories
- Why 3: Sprint closed before Ralph could reach priority-3 items
- Why 4: The sprint was effectively ended after 1/6 stories
- Why 5: See KAIZEN-007r / KAIZEN-004r root cause

**Root cause**: Normal prioritisation; sprint closed before reaching this story. Story is valid and ready.
**Decision**: Return to backlog as-is (already present, 1 pt, SMART=5)

---

### KAIZEN-006: Remove legacy 'phase' field from backlog stories
- Why 1: Story not implemented → sprint closed before iteration (lowest priority: 4)
- Why 2: Priority 4 is the last story worked in any sprint — correct ordering
- Why 3: Sprint closed before reaching it
- Why 4–5: Same as KAIZEN-005

**Root cause**: Normal prioritisation; sprint closed before reaching this story. Story is valid and ready.
**Decision**: Return to backlog as-is (already present, 1 pt, SMART=5)

---

## Flow analysis (Heijunka check)

- Sprint avg story size: **1.5 pts** — well-sized overall
- Point distribution: `{1: 4, 2: 1, 3: 1}` — healthy, no bloat
- Oversized (>8 pts): **0** — planning gate held
- Split candidates (5–8 pts): **0**
- KIND-001 (3 pts) is not formally a split candidate by the threshold, but SMART achievable=3 is the de-facto split signal — grooming should have caught it

**Finding**: The grooming ceremony does not enforce a hard split gate when achievable < 4. Add a check: if `achievable < 4`, story cannot enter sprint until split or achievable score justified with mitigations.

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Manual retro invocation before Ralph cycles through the sprint is the #1 sprint velocity killer.** Implement the pre-retro guard (KAIZEN-004r) before the next sprint to prevent this.
- **SMART achievable < 4 = split signal, not advisory.** Stories with achievable < 4 should be blocked at grooming, not flagged-and-pulled. Add a hard gate to the plan ceremony.
- **AC references to named completed sprint files (e.g. increment-17) must use fixture files instead.** Testable ACs must reference files that exist in a predictable test state, not specific completed increments.

---

## Quality gate improvements

- **Plan ceremony**: add hard gate — if any story has `smart.achievable < 4`, reject from sprint until split or achievable concern is documented with a concrete mitigation
- **Retro ceremony**: add pre-check — if `sprintHistory` already contains this increment, print "retro already ran for increment N — skipping" and exit 0 (idempotency guard already in ceremony spec but verify it works)
- **KAIZEN-004r**: after implementation, add to ceremony smoke tests: run retro with a limbo story present, confirm review runs first

---

## Velocity

| Increment | Points completed | Stories accepted | Review pass rate |
|-----------|-----------------|------------------|-----------------|
| 20        | 1               | 1 / 6            | 100%            |

Sprint points accepted: **1 / 9 planned**
First-review pass rate: **100%** (1 of 1 accepted stories passed on first review)
