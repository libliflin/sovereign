# Testing

How this project validates correctness. Run these before marking any story `passes: true`.

---

## CI Workflows

Three GitHub Actions workflows in `.github/workflows/`:

### `validate.yml` — main CI (runs on push to main, PRs to main)
Jobs:
1. **Helm Validate** — matrix across all charts in `platform/charts/` and `cluster/kind/charts/`: `helm lint`, `helm template`, assert PDB present, assert podAntiAffinity present, assert replicaCount >= 2, assert no `:latest` tags, assert image.repository doesn't hardcode an external registry
2. **Shell Validate** — `shellcheck -S error` on all `.sh` files in `cluster/`, `platform/`, `scripts/ralph/`; also checks that vendor scripts implement `--dry-run` and `--backup` flags
3. **Vendor Audit** — runs only when `platform/vendor/` changes: `platform/vendor/audit.sh`, VENDORS.yaml schema validation, recipe.yaml rollout/backup section validation
4. **ArgoCD Validate** — asserts `revisionHistoryLimit: 3` on all ArgoCD Application manifests
5. **Bootstrap Validate** — shellcheck on `cluster/kind/bootstrap.sh` and `platform/deploy.sh`; asserts `--dry-run` flag exists; asserts no hardcoded IPs

### `ha-gate.yml` — runs when `platform/charts/**` changes (PRs only)
- Shellchecks `scripts/ha-gate.sh`
- Runs `bash scripts/ha-gate.sh --dry-run`
- Asserts resource limits on changed charts (using `check-limits.py`)

### `release.yml` — release automation (contents vary)

---

## Local Quality Gates

Run these before pushing. They mirror CI exactly.

### Helm chart (any chart change):
```bash
helm lint platform/charts/<name>/
helm template platform/charts/<name>/ | grep PodDisruptionBudget   # must have result
helm template platform/charts/<name>/ | grep podAntiAffinity        # must have result
grep replicaCount platform/charts/<name>/values.yaml                # must be >= 2
helm template platform/charts/<name>/ | python3 scripts/check-limits.py
```

Convenience runner across all charts:
```bash
bash scripts/ha-gate.sh
bash scripts/ha-gate.sh --dry-run   # lists charts without running helm
```

### Shell scripts:
```bash
shellcheck -S error <script.sh>
```

### Contract validator (G7):
```bash
python3 contract/validate.py contract/v1/tests/valid.yaml           # must exit 0
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml  # must exit 1
```

### Autarky check (G6):
```bash
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "FAIL" || echo "PASS"
```

### Ceremony compile (G1):
```bash
python3 -c "from scripts.ralph.lib import orient, gates"
python3 -m py_compile scripts/ralph/ceremonies.py
```

---

## Integration Tests

### kind cluster integration
`cluster/kind/` contains integration tests that deploy to a real kind cluster:
- `cluster/kind/bootstrap.sh` — the main integration test: creates the cluster and validates it comes up
- `scripts/test/` — smoke test scripts for the kind cluster
- `kind/smoke-test/` and `kind/fixtures/` — kind HA fixtures and smoke test tooling

These are not run in CI automatically (they require Docker and are slow). Run manually:
```bash
./cluster/kind/bootstrap.sh                       # creates sovereign-test cluster
./cluster/kind/bootstrap.sh --dry-run             # preview without running
kind delete cluster --name sovereign-test         # teardown
```

### Contract validator tests
Located in `contract/v1/tests/`:
- `valid.yaml` — must pass validation (exit 0)
- `invalid-egress-not-blocked.yaml` — must fail validation (exit non-zero)

These are the definitive test fixtures for the contract. G7 runs both.

---

## `scripts/check-limits.py`

Validates that every container in a rendered Helm template has both `requests` and `limits` set for CPU and memory. `grep -A5 resources:` is insufficient — it passes even when one initContainer is missing limits. Always use check-limits.py.

```bash
helm template platform/charts/<name>/ | python3 scripts/check-limits.py
```

Output: lists every container with missing limits. Exit 0 = all containers have limits. Exit 1 = violations found.

---

## `scripts/ha-gate.sh`

Runs PDB, podAntiAffinity, and replicaCount checks across all charts in a single pass.

```bash
bash scripts/ha-gate.sh              # full check across all charts
bash scripts/ha-gate.sh --dry-run    # lists charts, doesn't run helm
```

---

## Vendor Recipe Tests

Recipes in `platform/vendor/recipes/<name>/recipe.yaml` are validated by the `vendor-audit` CI job:
- `rollout.strategy` must be present
- `rollout.max_unavailable` must be present
- `backup.priority` must be present

---

## What "Passes" Means

A story is marked `passes: true` only after:
1. All relevant quality gates above pass locally
2. Changes are pushed to a branch and a PR is open
3. CI passes on the PR
4. The PR is squash-merged to main

`passes: true` without a green CI run is a self-certification violation (CLAUDE.md: "Never self-certify").

---

## Test Gaps (as of this init)

- No kind-based CI integration: CI runs only static analysis. `cluster/kind/bootstrap.sh` can't be run in GitHub Actions without a large runner. The kind integration path is local-only.
- `scripts/test/` smoke tests existence: `kind/smoke-test/` has some scaffolding (per sprint history referencing HA-005a), but completeness is unknown — verify against current sprint state.
- No behavioral tests for the ceremony system: G1 checks that ceremonies compile, but doesn't run them or verify their output.
