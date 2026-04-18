# Builder round 1 notes

## Applied this round

- `docs/architecture.md` — replaced all 5 GitLab references with Forgejo:
  - Phase 4 table: `GitLab | SCM + CI + vendor mirrors` → `Forgejo | SCM + CI + vendor mirrors`
  - Phase 4 table: `GitLab CI Runners` → `Forgejo Actions Runners`
  - Namespace layout: `gitlab` → `forgejo`
  - Service URLs: `GitLab | https://gitlab.<domain>` → `Forgejo | https://forgejo.<domain>`
  - Autarky build system: `internal GitLab` → `internal Forgejo`

- `platform/vendor/VENDORS.yaml`:
  - Schema comment for `license_allows_vendor` corrected: was `false for BSL/SSPL/AGPL (blocked)`, now `false for BSL/SSPL (blocked); AGPL requires explicit review — see docs/governance/license-policy.md`
  - Added `license_review_note` to k6 entry documenting the AGPL review basis under the Deployment Platform Exception

## Validated

- `grep -n "GitLab\|gitlab" docs/architecture.md` → no output (clean)
- `grep -n "Forgejo\|forgejo" docs/architecture.md` → 5 matches, all correct

## PR

libliflin/sovereign#169

## For the verifier

Run the grep checks above. The doc fix is textual — no Helm or script gates affected.
The VENDORS.yaml change is schema + a new field; no structural change to existing entries.

## For the champion (next cycle)

Adjacent finding from the auditor journey, left for a future cycle:
`platform/charts/network-policies/` has `deny-all-egress` but no `deny-all-ingress`. East-west ingress control relies entirely on Istio STRICT mTLS; NetworkPolicy alone does not block unsolicited inbound. A deny-all-ingress policy with explicit allows would make the "no implicit trust" claim fully machine-checkable without depending on the mesh.

---

# Verifier round 1 notes

## What I compared

- Goal: Security Auditor walks architecture.md → runs G7 → paranoia satisfied.
- Builder fixed: all 5 GitLab→Forgejo in architecture.md, k6 AGPL note in VENDORS.yaml.
- Champion's journey named a third finding the builder did not address: contract validator duplicate key bypass.

## What I found

Confirmed the bypass is real:

```
autarky:
  externalEgressBlocked: false   # actual intent
  externalEgressBlocked: true    # appended to bypass last-value-wins parser
```

`python3 contract/validate.py` → `CONTRACT VALID: ...` — exit 0. G7 passes. Egress is actually not blocked. The auditor's paranoia is not satisfied: the constitutional gate they're supposed to trust can be bypassed with two lines.

## What I added (committed in libliflin/sovereign#170)

1. `contract/validate.py` — `parse_yaml_flat` now raises `ValueError` on duplicate dotpath. Surfaced as a contract error: `DUPLICATE KEY: 'autarky.externalEgressBlocked' appears more than once. Ambiguity in a sovereign contract is a violation.`

2. `contract/v1/tests/invalid-duplicate-key-bypass.yaml` — adversarial fixture; must exit 1.

3. `scripts/ralph/tests/test_contract_validator.py` — covers all 6 fixtures (valid + 5 invalid), including the bypass case. Runs with plain `python3`; emits `PASS:` lines; ends with `All tests passed.`

All G7 checks pass:
- `python3 contract/validate.py contract/v1/tests/valid.yaml` → exit 0
- `python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml` → exit 1
- `python3 contract/validate.py contract/v1/tests/invalid-duplicate-key-bypass.yaml` → exit 1, DUPLICATE KEY

## For the champion (next cycle)

Two adjacent findings remain unaddressed — both spotted during this cycle's scrutiny but out of scope to fix here:

1. **Governance docs still reference GitLab.** `docs/governance/scope.md` lines 26, 74, 83 name GitLab as the SCM. `docs/state/architecture.md` line 55 lists GitLab in the Tier 2 table. `docs/governance/sovereignty.md` has a sovereignty assessment row for GitLab (which is arguably correct — it shows the migration decision). The auditor who reads beyond architecture.md will find these. `scope.md` is the highest-priority: it explicitly names "Source control (GitLab)" as in-scope.

2. **No `deny-all-ingress` NetworkPolicy.** The "no implicit trust" claim is not fully machine-checkable from NetworkPolicy alone — it depends on Istio STRICT mTLS for east-west ingress control. Adding a deny-all-ingress policy with explicit allows would close this.
