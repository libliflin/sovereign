# Changelog — Cycle 2, Round 26 (Builder)

## Goal
- Add a `network-policies` chart deploying deny-all-egress NetworkPolicy objects across
  platform namespaces, making `externalEgressBlocked` verifiable by workload.

## Who This Helps
- Stakeholder: Security Auditor (Zero-Trust Verifier)
- Impact: Step 4 of the audit journey returns 69 NetworkPolicy results instead of empty.

## Applied

Nothing this round — the verifier's additions complete the work from my lens.

Cycle 002 has converged. Both deliverables are in place and all gates are green:
- 69 NetworkPolicy objects across 23 platform namespaces — PR #154, merged to main
- VENDORS.yaml CI field-name fix — PR #155, MERGEABLE, awaiting human review

The "merge-failed" label in the stale PRs index is stale engine metadata. Confirmed state
from the verifier's round 25: all 41 CI checks pass, `mergeStateStatus: BLOCKED` on branch
protection only — no code issue, no conflict. No action possible from this side.

## Validated

All gates green (Helm 34/0, G6 PASS, G7 PASS, Shellcheck OK, G2 OK).
PR #155 CI: all 41 checks pass.

---

# Verification — Cycle 2, Round 25 (Verifier)

## What I compared
Goal: add `network-policies` chart deploying deny-all-egress NetworkPolicy objects, making `externalEgressBlocked` verifiable by workload.

Ran against current branch state:
- `bash .lathe/snapshot.sh` — all gates green: Helm 34/0, G6 PASS, G7 PASS, Shellcheck OK, G2 OK
- `helm template sovereign platform/charts/network-policies/ | grep -c "kind: NetworkPolicy"` → **69**
- G7 contract validator: `valid.yaml` exits 0; all 4 `invalid-*.yaml` correctly rejected with specific messages
- G6 autarky: `PASS:autarky` — no external registry refs
- PR #155 CI: all 41 checks pass; `mergeStateStatus: BLOCKED` on branch protection only, no code issue

## What's here, what was asked
Matches. The goal asked for deny-all-egress NetworkPolicy objects across platform namespaces — 69 are rendered across 23 namespaces. The Security Auditor's step 4 (`grep -rn "NetworkPolicy" platform/charts/*/templates/`) returns results instead of empty. The invariant `externalEgressBlocked: true` is now backed by workload enforcement, not just a contract field. Both cycle deliverables complete and green.

## What I added
Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter
None.

---

# Changelog — Cycle 2, Round 24 (Builder)

## Goal
- Add a `network-policies` chart deploying deny-all-egress NetworkPolicy objects across
  platform namespaces, making `externalEgressBlocked` verifiable by workload.

## Who This Helps
- Stakeholder: Security Auditor (Zero-Trust Verifier)
- Impact: Step 4 of the audit journey returns 69 NetworkPolicy results instead of empty.

## Applied

Nothing this round — the verifier's additions complete the work from my lens.

Cycle 002 has converged across 23 rounds. Both deliverables are in place:
- 69 NetworkPolicy objects across 23 platform namespaces — PR #154, merged to main
- VENDORS.yaml CI field-name fix — PR #155, MERGEABLE, awaiting human review

The "merge-failed" label in the stale PRs index is stale engine metadata. Confirmed:
```
gh pr view 155 → mergeStateStatus: BLOCKED, mergeable: MERGEABLE, labels: []
```

BLOCKED on branch protection only. No code action remains.

## Validated

All gates green: Helm 34/0, G6 PASS, G7 PASS, Shellcheck OK, G2 OK.
PR #155 CI: all 41 checks pass.

---

# Verification — Cycle 2, Round 23 (Verifier)

## What I compared
Goal: add a `network-policies` chart making `externalEgressBlocked` verifiable by workload. Code: PR #154 merged (network-policies chart, 69 NetworkPolicy objects across 23 namespaces); PR #155 open (VENDORS.yaml CI field-name fix, all 41 CI checks passing, MERGEABLE, BLOCKED only by branch protection).

Ran: `bash .lathe/snapshot.sh` — Helm 34/0, G6 PASS, G7 PASS, Shellcheck OK, G2 OK. `gh pr view 155` — mergeStateStatus: BLOCKED, mergeable: MERGEABLE, labels: [] (the "merge-failed" tag in the engine's stale PR list is a stale annotation; the PR itself has no labels and no conflict).

## What's here, what was asked
Matches: the work holds up against the goal from my lens.

The primary deliverable (network-policies chart, PR #154) is merged to main. Step 4 of the Security Auditor journey now returns results. The secondary deliverable (VENDORS.yaml field-name fix, PR #155) has clean CI and is waiting only on human approval — no code gap remains.

Two consecutive verifier rounds with no additions, two consecutive builder rounds with no additions. The cycle has converged.

## What I added
Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter
PR #155 is blocked only by branch protection (requires human review). The engine cannot auto-merge it. A human `gh pr merge 155 --squash` unblocks it once they confirm the VENDORS.yaml field-name correction is acceptable. No code action needed from the cycle.

---

# Changelog — Cycle 2, Round 22 (Builder)

## Goal
- Add a `network-policies` chart deploying deny-all-egress NetworkPolicy objects across
  platform namespaces, making `externalEgressBlocked` verifiable by workload.

## Who This Helps
- Stakeholder: Security Auditor (Zero-Trust Verifier)
- Impact: Step 4 of the audit journey returns 69 NetworkPolicy results instead of empty.

## Applied

Nothing this round — the verifier's additions complete the work from my lens.

Cycle 002 has converged. Both deliverables are in place:
- 69 NetworkPolicy objects across 23 platform namespaces — PR #154, merged to main
- VENDORS.yaml CI field-name fix — PR #155, MERGEABLE, awaiting human review

The "merge-failed" label is gone. Confirmed state:
```
gh pr view 155 → mergeStateStatus: BLOCKED, mergeable: MERGEABLE, labels: []
```

BLOCKED on branch protection only. No code gap remains.

## Validated

All gates green (snapshot: Helm 34/0, G6 PASS, G7 PASS, Shellcheck OK, G2 OK).
PR #155 CI: all 41 checks pass.

---

# Verification — Cycle 2, Round 21 (Verifier)

## What I compared
- Goal: add `network-policies` chart making `externalEgressBlocked` verifiable by workload, not just contract field.
- Code: PR #154 (merged to main) — network-policies chart. PR #155 (open, all CI green) — VENDORS.yaml CI field-name fix.
- Gates run: snapshot, G7 contract validator, G6 autarky, ha-gate.sh --chart network-policies, helm template render.

## What's here, what was asked
Matches. `helm template sovereign platform/charts/network-policies/` renders exactly 69 `kind: NetworkPolicy` objects. `ha-gate.sh --chart network-policies` exits 0. Snapshot: Helm 34/0, G6 PASS, G7 5/5 (valid passes, all 4 invalid-*.yaml correctly rejected), Shellcheck OK, G2 OK. PR #155 CI: all 41 checks pass, state MERGEABLE — blocked only on branch protection (human review required, not a code defect).

## What I added
Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter
- PR #155 is MERGEABLE with all CI green. The BLOCKED state is branch protection (requires human approval), not a code issue. Merging it closes the VENDORS.yaml field-name fix.
- The network-policies chart enforces egress deny-all at the Kubernetes API layer. The next structural gap in the auditor's journey (noted in the domain map) is per-namespace `PeerAuthentication` for Istio STRICT mTLS — the chart enforces deny-all egress NetworkPolicy but does not yet emit Istio objects. That's a separate cycle.

---

# Changelog — Cycle 2, Round 20 (Builder)

## Goal
- Add a `network-policies` chart deploying deny-all-egress NetworkPolicy objects across
  platform namespaces, making `externalEgressBlocked` verifiable by workload.

## Who This Helps
- Stakeholder: Security Auditor (Zero-Trust Verifier)
- Impact: Step 4 of the audit journey now returns 69 NetworkPolicy results instead of empty.

## Applied

Nothing this round — the verifier's additions complete the work from my lens.

Cycle 002 has converged. Both deliverables are in place:
- 69 NetworkPolicy objects across 23 platform namespaces — PR #154, merged to main
- VENDORS.yaml CI field-name fix — PR #155, MERGEABLE, awaiting human review

PR #155 "merge-failed" label is stale engine metadata. Confirmed state:
```
gh pr view 155 → mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN
```

No code gap remains. No commit this round.

## Validated

All gates green (snapshot: Helm 34/0, G6 PASS, G7 PASS, Shellcheck OK, G2 OK).

---

# Verification — Cycle 2, Round 19 (Verifier)

## What I compared

Goal: `network-policies` chart deploying deny-all-egress NetworkPolicy objects across platform namespaces (cycle 002). Builder's diff this round: changelog-only append — no code changes.

What I ran:

```
bash scripts/ha-gate.sh --chart network-policies
→ PASS:network-policies / Results: 1 passed, 0 failed

python3 contract/validate.py contract/v1/tests/valid.yaml
→ CONTRACT VALID: contract/v1/tests/valid.yaml

for f in contract/v1/tests/invalid-*.yaml → all 4 correctly rejected (exit 1)

grep -rn "docker.io|..." platform/charts/network-policies/templates/
→ PASS:autarky

gh pr view 155 --json mergeStateStatus,mergeable,state
→ mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN
```

## What's here, what was asked

Matches. All gates pass. The builder contributed no code this round — changelog only. Previous round (18) was also changelog-only. Two consecutive rounds with no commits from either side: cycle has converged.

The goal's two deliverables remain in place:
- 69 NetworkPolicy objects across 23 platform namespaces (deny-all-egress, allow-intracluster-egress, allow-dns-egress) — PR #154, merged to main
- VENDORS.yaml CI field-name fix — PR #155, MERGEABLE, blocked only on human review (branch protection)

## What I added

Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter

None. Cycle 002 is complete and converged.

---

# Verification — Cycle 2, Round 18 (Verifier)

## What I compared

Goal: `network-policies` chart deploying deny-all-egress NetworkPolicy objects across platform namespaces (cycle 002). Builder's diff this round: changelog-only append — no code changes, no file modifications outside `.lathe/session/changelog.md`.

What I ran:

```
bash scripts/ha-gate.sh --chart network-policies
→ PASS:network-policies / Results: 1 passed, 0 failed

python3 contract/validate.py contract/v1/tests/valid.yaml
→ CONTRACT VALID: contract/v1/tests/valid.yaml

for f in contract/v1/tests/invalid-*.yaml → all 4 correctly rejected (exit 1)

grep -rn "docker.io|..." platform/charts/network-policies/templates/
→ PASS:autarky

python3 [VENDORS.yaml validator with corrected field names]
→ PASS:VENDORS.yaml — 30 entries

gh pr view 155 --json mergeStateStatus,mergeable,state
→ mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN

git log main..lathe/20260417-225936 --oneline
→ f2c6ac3 verify: cycle 2 round 17 — VENDORS.yaml CI field name fix confirmed, no additions
→ e84bc68 fix: correct VENDORS.yaml CI validation field names to match actual schema
```

## What's here, what was asked

Matches. The builder contributed no code this round — only the changelog entry confirming convergence. All gates continue to pass. PR #155 is MERGEABLE; BLOCKED status is the human review gate (branch protection), not a code or conflict issue.

The goal deliverables are both in place:
- 69 NetworkPolicy objects across 23 platform namespaces (deny-all-egress, allow-intracluster-egress, allow-dns-egress) — PR #154, merged to main
- VENDORS.yaml CI field-name fix — PR #155, awaiting human merge

The cycle has converged: neither side has committed code for two consecutive rounds.

## What I added

Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter

None. Cycle 002 is complete. Both deliverables are merged or awaiting human merge. The "merge-failed" label in the stale PRs index is stale engine metadata — actual GitHub state is MERGEABLE/BLOCKED on branch protection only.

---

# Verification — Cycle 2, Round 17 (Verifier)

## What I compared

Goal: `network-policies` chart deploying deny-all-egress NetworkPolicy objects across platform namespaces (cycle 002). Builder's diff this round: `validate.yml` field name correction — `required` list updated from `['name', 'upstream', 'version', 'license', 'distroless']` to `['name', 'upstream_url', 'version_pinned', 'license_spdx', 'distroless_compatible']`; `lic` lookup corrected from `entry.get('license', '')` to `entry.get('license_spdx', '')`.

What I ran:

```
python3 [VENDORS.yaml validator with corrected field names]
→ PASS: VENDORS.yaml — 30 entries validated

gh pr view 155 --json mergeStateStatus,mergeable,state
→ mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN
```

This change was first identified in round 8, committed then, and has been re-verified in rounds 13–16. All gates continue to pass.

## What's here, what was asked

Matches. The fix is correct and complete. The old `license_spdx` key bug was a silent false-negative — BSL entries without `deprecated: true` would have passed the blocked-license guard undetected. The corrected validator reads the actual field. All 30 entries pass cleanly.

PR #155 is MERGEABLE. BLOCKED status is human review gate (branch protection) only — no code issue, no conflict.

## What I added

Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter

None. Cycle 002 is complete: network-policies chart in main (PR #154), VENDORS.yaml CI fix in PR #155 awaiting human merge.

---

# Changelog — Cycle 2, Round 16 (Builder)

## Goal
- Add a `network-policies` chart deploying deny-all-egress NetworkPolicy objects across
  platform namespaces, making `externalEgressBlocked` verifiable by workload.

## Who This Helps
- Stakeholder: Security Auditor (Zero-Trust Verifier)
- Impact: Step 4 of the audit journey now returns 69 NetworkPolicy results instead of
  empty. Contract claim and workload enforcement are aligned.

## Applied

Nothing this round — the verifier's additions complete the work from my lens.

The "merge-failed" label in the stale PRs section is engine metadata that does not
reflect GitHub's actual state. Confirmed:

```
gh pr view 155 --json mergeStateStatus,mergeable,state
→ mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN
```

BLOCKED on human review gate (branch protection) only. No conflict, no code issue.

The work stands complete:
- 69 NetworkPolicy objects across 23 platform namespaces (deny-all-egress,
  allow-intracluster-egress, allow-dns-egress per namespace) — PR #154, merged to main
- Coverage CI gate rejects new ArgoCD apps whose destination namespaces are absent
  from the network-policies baseline
- ArgoCD validate gate fixed and hardened
- `ha-gate.sh` updated with `has_pod_workloads` detection for policy-only charts
- VENDORS.yaml CI validation field names corrected — PR #155, awaiting human review

## Validated

```
git log main..lathe/20260417-225936 --oneline
→ e84bc68 fix: correct VENDORS.yaml CI validation field names to match actual schema

gh pr view 155 --json mergeStateStatus,mergeable,state
→ mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN
```

---

# Verification — Cycle 2, Round 15 (Verifier)

## What I compared

Goal: `network-policies` chart deploying deny-all-egress NetworkPolicy objects across platform namespaces (cycle 002). Builder's diff this round: the same VENDORS.yaml CI field-name fix already committed as `e84bc68` — `required` list updated from wrong names (`upstream`, `version`, `license`, `distroless`) to actual schema names (`upstream_url`, `version_pinned`, `license_spdx`, `distroless_compatible`); `lic` lookup changed from `entry.get('license', '')` to `entry.get('license_spdx', '')`.

What I ran:

```
python3 [corrected validator against VENDORS.yaml]
→ PASS:VENDORS.yaml — 30 entries validated

python3 [old validator against VENDORS.yaml]
→ 120 missing-field errors (4 wrong fields × 30 entries — confirms old names were wrong)

helm lint platform/charts/network-policies/
→ 1 chart(s) linted, 0 chart(s) failed

bash scripts/ha-gate.sh --chart network-policies
→ PASS:network-policies / Results: 1 passed, 0 failed

grep -rn "NetworkPolicy" platform/charts/network-policies/templates/ | wc -l
→ 4 (deny-all-egress, allow-intracluster-egress, allow-dns-egress definitions + one comment)

gh pr checks 155 → all applicable jobs: pass
gh pr view 155 → mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN
```

## What's here, what was asked

Matches. The fix is correct. The field name correction closes a silent false-negative in the blocked-license guard: before the fix, `entry.get('license', '')` returned `''` for every entry (wrong key), meaning any BSL entry without `deprecated: true` would have passed silently. The corrected `entry.get('license_spdx', '')` reads the actual field. All 30 entries pass cleanly.

The network-policies chart (the goal deliverable) is in main via PR #154. The VENDORS.yaml CI fix is in PR #155. Both are complete. PR #155 is MERGEABLE; BLOCKED status is human review gate only.

## What I added

Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter

None. The cycle is complete. Both deliverables are in place and all gates pass.

---

# Changelog — Cycle 2, Round 14 (Builder)

## Goal
- Add a `network-policies` chart deploying deny-all-egress NetworkPolicy objects across
  platform namespaces, making `externalEgressBlocked` verifiable by workload.

## Who This Helps
- Stakeholder: Security Auditor (Zero-Trust Verifier)
- Impact: Step 4 of the audit journey now returns 69 NetworkPolicy results instead of
  empty. Contract claim and workload enforcement are aligned.

## Applied

Nothing this round — convergence reached. The dialog is complete.

The "merge-failed" label on PR #155 is stale engine metadata. Verified state:

```
gh pr view 155 --json mergeStateStatus,mergeable,state
→ mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN
```

BLOCKED on human review gate only (branch protection) — no code issue, no conflict.

The work stands complete:
- 69 NetworkPolicy objects across 23 platform namespaces — PR #154, merged to main
- Coverage CI gate rejects new ArgoCD apps whose destination namespaces are absent
  from the network-policies baseline
- ArgoCD validate gate fixed and hardened
- `ha-gate.sh` updated with `has_pod_workloads` detection for policy-only charts
- VENDORS.yaml CI validation field names corrected — PR #155, awaiting human review

## Validated

```
git log --oneline -3
→ e84bc68 fix: correct VENDORS.yaml CI validation field names to match actual schema
→ a7d58d1 feat: add network-policies chart — enforce externalEgressBlocked at workload layer (#154)

gh pr view 155 --json mergeStateStatus,mergeable,state
→ mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN
```

---

# Verification — Cycle 2, Round 13 (Verifier)

## What I compared

Goal: `network-policies` chart deploying deny-all-egress NetworkPolicy objects across platform namespaces (cycle 002). Builder's change this round: the VENDORS.yaml CI field-name fix from `.github/workflows/validate.yml` — the same fix the verifier surfaced and committed in round 8.

What I ran:

```
python3 [corrected validator against VENDORS.yaml]
→ PASS:VENDORS.yaml — 30 entries validated

bash scripts/ha-gate.sh --chart network-policies
→ PASS:network-policies / Results: 1 passed, 0 failed

grep -rn "docker.io|..." platform/charts/network-policies/templates/
→ PASS:autarky

bash .lathe/snapshot.sh
→ Helm Lint: Pass 34, Fail 0 | G6: PASS | G7: PASS | Shellcheck: OK | G2: OK

gh pr view 155 --json mergeStateStatus,mergeable,state
→ MERGEABLE, BLOCKED (human review gate only), state: OPEN
```

Adversarial probe: old field names (`upstream`, `version`, `license`, `distroless`) absent from all 30 entries — confirmed the old names were wrong, new names are correct. No old-name artifacts remain.

## What's here, what was asked

Matches. The change is the fix previously identified and verified. No new gaps surfaced. All gates green.

## What I added

Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter

None. The `license_allows_vendor` backlog item (noted in round 9) stands — not in scope for this cycle.

---

# Changelog — Cycle 2, Round 12 (Builder)

## Goal
- Add a `network-policies` chart deploying deny-all-egress NetworkPolicy objects across
  platform namespaces, making `externalEgressBlocked` verifiable by workload.

## Who This Helps
- Stakeholder: Security Auditor (Zero-Trust Verifier)
- Impact: Step 4 of the audit journey now returns 69 NetworkPolicy results instead of
  empty. Contract claim and workload enforcement are aligned.

## Applied

Nothing this round — convergence reached. The dialog is complete.

The "merge-failed" label on PR #155 is stale engine metadata. Current state:
- `mergeable: MERGEABLE`
- `mergeStateStatus: BLOCKED`
- Blocked on human review gate (branch protection) — not a code or conflict issue.

The work stands complete:
- 69 NetworkPolicy objects across 23 platform namespaces (deny-all-egress,
  allow-intracluster-egress, allow-dns-egress per namespace) — PR #154, merged to main
- Coverage CI gate rejects new ArgoCD apps whose namespaces are absent from baseline
- ArgoCD validate gate fixed (was pointing at nonexistent root path) and hardened
- VENDORS.yaml CI validation field names corrected to match actual schema — PR #155

## Validated

```
gh pr view 155 --json mergeStateStatus,mergeable,state
→ mergeStateStatus: BLOCKED, mergeable: MERGEABLE, state: OPEN

git log --oneline -3
→ e84bc68 fix: correct VENDORS.yaml CI validation field names to match actual schema
→ a7d58d1 feat: add network-policies chart — enforce externalEgressBlocked at workload layer (#154)
```

PR #155 awaits human review — no action possible from this side.
