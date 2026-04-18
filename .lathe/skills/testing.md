# Testing — Sovereign Platform

## What Passes as "CI Green"

Sovereign has no unit test suite in the traditional sense. "Tests passing" means all CI jobs pass:

1. **Helm validate** — `helm lint` + `helm template` + assertions: PDB, podAntiAffinity, replicaCount >= 2, no :latest tags, no external registry in values.yaml. Runs on every chart discovered via `ls platform/charts/*/Chart.yaml` and `ls cluster/kind/charts/*/Chart.yaml`.

2. **Shell validate** — `shellcheck -S error` on all `.sh` files in `cluster/`, `platform/`, `scripts/`. Also asserts vendor scripts handle `--dry-run` and `--backup`.

3. **Contract validator** — `python3 contract/validate.py contract/v1/tests/valid.yaml` must exit 0; all `contract/v1/tests/invalid-*.yaml` must exit 1. This is G7.

4. **Autarky** — No external registry references (`docker.io`, `quay.io`, `ghcr.io`, `gcr.io`, `registry.k8s.io`) in `platform/charts/*/templates/`. This is G6.

5. **ArgoCD validate** — All `Application` manifests have `revisionHistoryLimit: 3`.

6. **Bootstrap validate** — `shellcheck` on `cluster/kind/bootstrap.sh` and `platform/deploy.sh`; `--dry-run` flag present; no hardcoded IPs.

7. **README chart path validate** — Every `helm install/lint/template` path in README.md must exist as a directory.

8. **Vendor audit** (conditional) — Runs only when `platform/vendor/` changes: `vendor/audit.sh`, VENDORS.yaml schema check, recipe.yaml rollout/backup validation.

## Running Checks Locally

```bash
# Snapshot (all gates at once, summarized):
bash .lathe/snapshot.sh

# Helm lint all charts:
for chart in platform/charts/*/; do helm lint "$chart"; done

# Scoped HA gate for one chart:
bash scripts/ha-gate.sh --chart <name>

# Contract validator:
python3 contract/validate.py contract/v1/tests/valid.yaml     # must pass
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml  # must fail

# Autarky:
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ cluster/kind/charts/*/templates/ && echo FAIL || echo PASS

# Shellcheck:
find cluster platform scripts -name "*.sh" | xargs shellcheck -S error
```

## ha-gate.sh Scope

`bash scripts/ha-gate.sh --chart <name>` checks only the named chart and exits 0/1 based on that chart only. This prevents pre-existing failures in other charts from blocking a contributor's unrelated PR. The CI HA Gate workflow uses this scoped mode on changed charts.

## Integration Testing (kind)

Bootstrap scripts are tested statically only (shellcheck + bash -n). Never run `bootstrap.sh` in full execution during a cycle — those are manual steps for real infrastructure. kind is the local integration environment, but kind cluster creation is a manual step, not automated in CI.

## What "No Test Suite" Means for the Champion

When the snapshot shows all green, the floor is clear. But "all green" does not mean stakeholder journeys work end-to-end — it means the static checks passed. The champion's job is to walk the actual journeys and find where the green checks miss real friction.
