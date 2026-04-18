# Testing — How This Project Tests

Sovereign has no single test runner. Verification is multi-layer, and each layer catches a different class of failure.

---

## CI Gates (`.github/workflows/`)

### `validate.yml` — triggers on `pull_request` and `push` to main

This is the primary CI gate. Jobs:

| Job | What it checks |
|---|---|
| `helm-validate` | Per-chart: lint, PDB present, podAntiAffinity present, replicaCount ≥ 2, no `:latest` tags, no hardcoded external registry in image.repository |
| `shell-validate` | shellcheck -S error on all .sh files in cluster/, platform/, scripts/ralph/ |
| `vendor-audit` | VENDORS.yaml schema, recipe.yaml rollout/backup sections (runs only when platform/vendor/ changes) |
| `argocd-validate` | Every Application manifest has `spec.revisionHistoryLimit: 3` |
| `bootstrap-validate` | shellcheck on bootstrap.sh, assert --dry-run flag exists, no hardcoded IP addresses |

### `ha-gate.yml` — triggers on `pull_request` touching `platform/charts/**`

Runs the HA gate across all changed charts. Same checks as helm-validate but path-filtered.

---

## Local Quality Gates (run before pushing)

These match CI exactly. If they pass locally, CI should pass.

```bash
# Per-chart checks
helm dependency update platform/charts/<name>/ 2>/dev/null || true
helm lint platform/charts/<name>/
helm template sovereign platform/charts/<name>/ --set global.domain=sovereign-autarky.dev > /tmp/rendered.yaml

grep "kind: PodDisruptionBudget" /tmp/rendered.yaml   # must exist
grep "podAntiAffinity" /tmp/rendered.yaml              # must exist
grep "replicaCount" platform/charts/<name>/values.yaml # must be >= 2

# Resource limits (use check-limits.py — grep is not sufficient)
helm template platform/charts/<name>/ | python3 scripts/check-limits.py

# No external registry refs in templates
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "FAIL" || echo "PASS"

# Convenience: run all charts at once
bash scripts/ha-gate.sh
bash scripts/ha-gate.sh --dry-run   # list charts without running helm
```

---

## Contract Validator Tests

The contract validator uses fixture files in `contract/v1/tests/`:

```bash
# valid.yaml must pass (exit 0)
python3 contract/validate.py contract/v1/tests/valid.yaml

# invalid-*.yaml must fail (exit 1) — the validator rejects what it should
for f in contract/v1/tests/invalid-*.yaml; do
  python3 contract/validate.py "$f" && echo "FAIL (should have rejected): $f" || echo "PASS (correctly rejected): $f"
done
```

Key fixture: `invalid-egress-not-blocked.yaml` — tests that `autarky.externalEgressBlocked: false` is rejected. This is G7 (contract validator test suite passes).

---

## Python Unit Tests

Located in `scripts/ralph/tests/test_*.py`. Run individually (no test framework harness):

```bash
python3 scripts/ralph/tests/test_ceremonies.py
python3 scripts/ralph/tests/test_<name>.py
# Or run all:
for tf in scripts/ralph/tests/test_*.py; do python3 "$tf" && echo "PASS: $tf" || echo "FAIL: $tf"; done
```

---

## Shell Script Validation

```bash
shellcheck -S error cluster/kind/bootstrap.sh
shellcheck -S error platform/deploy.sh
find scripts/ralph -name "*.sh" -print0 | xargs -0 shellcheck -S error
```

---

## Constitutional Gates (evaluated by orient.py)

Defined in `prd/constitution.json`. Gates that must pass before new work begins:

| Gate | Check |
|---|---|
| G1 | Ceremony scripts compile without errors |
| G2 | Living state docs (`docs/state/`) exist and are current |
| G6 | Zero external registry references in chart templates |
| G7 | Contract validator test suite passes |

---

## Notes for the Champion

- **`check-limits.py` is authoritative for resource limits.** `grep -A5 resources:` misses initContainers. Always use the script.
- **HA exceptions are tracked in `platform/vendor/VENDORS.yaml`** under `ha_exception: true`. CI respects these; local gates do too if you run `bash scripts/ha-gate.sh`.
- **For distributed-mode charts** (Loki Simple Scalable, Tempo distributed), PDB count must equal the number of deployed components, not just ≥ 1. Use `grep -c PodDisruptionBudget`.
- **The validator uses stdlib only.** No pip installs required to run `contract/validate.py`.
- **CI snapshot in the snapshot.sh output** summarizes helm lint pass/fail, test pass/fail, contract pass/fail, and autarky gate — use these health signals, not raw output.
