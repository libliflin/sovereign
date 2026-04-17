# Verification — Cycle 2, Round 1

## What was checked

**Builder's diff:** Exclusively `.lathe/` documentation files — `goal.md`, `builder.md`, `verifier.md`, `snapshot.sh`, `brand.md`, all five skills files, `alignment-summary.md`, and init logs. This is a lathe reinit. No changes to `platform/charts/`, scripts, contract, or sprint files.

**Goal:** Merge PR #137. Close PRs #134, #135, #136 as superseded.

**Gate sequence run from clean state:**
```
G1 PASS — ceremonies.py compiles, imports resolve
G6 PASS — no external registries in chart templates
G7 PASS — contract validator enforces sovereignty invariants
  valid.yaml → exit 0, CONTRACT VALID
  invalid-egress-not-blocked.yaml → exit 1, AUTARKY VIOLATION
Helm Lint FAIL — 1/33 charts: platform/charts/perses (same violation as cycle 1)
Shellcheck PASS — all scripts clean
Unit tests PASS — test_retro_guard.py: 3/3 passed
HA gate FAIL — 26/33 charts (pre-existing, not introduced by builder)
```

**PR status:**
- PR #137 (`fix: resolve all 7 helm-validate CI failures`): all CI checks SUCCESS, `mergeStateStatus: BLOCKED`, `mergeable: MERGEABLE`, `reviews: []`
- PR #139 (`fix: resolve all 6 helm-validate CI failures`): all CI checks SUCCESS, same BLOCKED state
- PRs #134, #135, #136: still open, not closed

## Findings

**Builder did not accomplish the goal.** The diff contains zero changes outside `.lathe/`. The perses chart still fails `helm lint` with the identical error: `at '': additional properties 'replicaCount', 'affinity', 'podDisruptionBudget', 'security' not allowed`.

**Root cause of the block:** PR #137 has `mergeable: MERGEABLE` and all CI checks green, but `mergeStateStatus: BLOCKED` with `reviews: []`. Branch protection requires at least one human review before merge. The lathe cannot self-approve — that is a self-certification violation per CLAUDE.md.

**PR #139 is also CI-green** and contains equivalent perses fixes (confirmed via `gh pr diff`). It is also BLOCKED for the same reason.

**The builder cannot close this goal autonomously.** Merging requires a human reviewer to approve either PR #137 or #139. This is not a bug in the lathe — it is a deliberate branch protection invariant.

## Fixes applied

None. The block is structural (branch protection + self-certification prohibition), not a code gap the verifier can close.

The current branch (`lathe/20260417-185747`) contains only `.lathe/` reinit changes. A PR should be created for it to land the doc refresh, but that does not address the goal.

## Confidence

Gate sequence output (key lines):
```
G1 PASS — ceremonies.py compiles, imports resolve
G6 PASS — no external registries in chart templates
G7 PASS — contract validator enforces sovereignty invariants
Helm Lint FAIL — platform/charts/perses (floor still violated)
Shellcheck PASS
```

PR #137 status: all 39 CI checks SUCCESS. Blocked by branch protection requiring human review.

The fix is done and verified. It cannot land without a human approving PR #137 (or #139). This is the correct outcome — the lathe system should not bypass branch protection to merge its own work.

VERDICT: NEEDS_WORK
