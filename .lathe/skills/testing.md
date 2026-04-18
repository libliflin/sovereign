# Testing Conventions

How this project tests — test runner, conventions, fixture locations.

---

## Test Types and Locations

| What | Where | How |
|---|---|---|
| Helm chart validation | CI (`validate.yml`) | helm lint + template + PDB/antiAffinity/limits checks |
| HA gate script | `scripts/ha-gate.sh` | PDB, podAntiAffinity, replicaCount across all charts |
| Contract validator | `contract/validate.py` + `contract/v1/tests/` | Python, validates YAML against schema |
| Ceremony unit tests | `scripts/ralph/tests/` | Python unittest |
| Chaos/PDB test fixtures | `test/chaos/` | YAML fixtures for kubectl drain simulation |
| Kind smoke test | `kind/smoke-test/rolling-update.sh` | Verifies zero-pod-unavailability during helm upgrade |
| Kind HA fixtures | `kind/fixtures/` | PDB drain validation fixture |
| Sovereign PM | `platform/sovereign-pm/` | Jest (npm test) |

---

## Contract Validator

```bash
# Must pass (exit 0) — valid config accepted
python3 contract/validate.py contract/v1/tests/valid.yaml

# Must fail (exit 1) — invalid config rejected
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml
echo "Exit: $?"  # expect 1
```

The test corpus at `contract/v1/tests/` includes invariants for `externalEgressBlocked`, `imageRegistry`, and `storageClass`. These are the G7 constitutional gate tests.

---

## HA Gate

```bash
# All charts (including E13 testing charts)
bash scripts/ha-gate.sh

# Scoped to one chart — exits 0/1 based only on that chart
bash scripts/ha-gate.sh --chart <name>

# List what would be checked (no helm run)
bash scripts/ha-gate.sh --dry-run
```

---

## Resource Limits Gate

```bash
helm template platform/charts/<name>/ | python3 scripts/check-limits.py
```

Exhaustively checks every container and initContainer spec. **Do not use `grep -A5 resources:` as a substitute** — it misses individual containers that lack limits.

---

## Ceremony Unit Tests

```bash
cd scripts/ralph
python3 -m pytest tests/
# or individual test:
python3 -m pytest tests/test_retro_guard.py
```

These tests run without a live cluster — they test ceremony Python logic with mock data.

---

## Kind Integration Tests

The kind cluster must exist (`kind get clusters` shows `sovereign-test`) before running these.

```bash
# Kind smoke test: rolling update with zero unavailability
./kind/smoke-test/rolling-update.sh

# PDB drain validation: kubectl drain should be blocked when last pod would be evicted
kubectl apply -f kind/fixtures/pdb-test.yaml --context kind-sovereign-test
# Then attempt drain per the fixture README
```

---

## Sovereign PM Tests

```bash
cd platform/sovereign-pm
npm test -- --forceExit     # Jest
npm run typecheck            # TypeScript
npm run lint                 # ESLint
```

---

## CI Coverage

What CI actually runs (from `validate.yml` + `ha-gate.yml`):

- Helm lint on every chart
- HA gate (PDB, podAntiAffinity, replicaCount) on every chart
- Resource limits check (`check-limits.py`) on every chart
- No `:latest` image tags in values.yaml
- No hardcoded external registry in `image.repository`
- Shellcheck on all `.sh` files under `cluster/`, `platform/`, `prd/`, `scripts/ralph/`, `platform/vendor/`
- Vendor scripts have `--dry-run` and `--backup` flags
- ArgoCD Applications have `revisionHistoryLimit: 3`
- Network-policies egress baseline covers all deployed namespaces
- Contract validator: valid.yaml passes, invalid-egress-not-blocked.yaml fails
- README chart paths exist in repo
- bootstrap.sh has `--dry-run` flag

---

## Test Writing Conventions

**ACs must be runnable, not aspirational.** Write the exact command with the exact expected output. Never assert "shows a value >= 2" when you can write `grep -E 'replicaCount:[[:space:]]+[2-9]'` which exits 0/1.

**Count assertions use "at least N"**, not "== N", for resources that scale with component count (PDBs per component in distributed charts like Loki, Tempo).

**Vendor API field values must be version-pinned.** If an AC asserts a CRD phase name or status string, cite the upstream docs for that pinned chart version. Unverified constants fail review even when implementation is correct (e.g., chaos-mesh v2.6.3 uses `AllRecovered=True` not `Finished`).

**CRD-backed resources use YAML-only validation**, not `kubectl apply --dry-run=client` (CRDs not installed in kind-sovereign-test):
```bash
python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())" <file>.yaml
```
