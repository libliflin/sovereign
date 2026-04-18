# Contributing to Sovereign

Fork the repo. Create a feature branch. Run the gates below before you push. Open a PR — CI validates the same checks automatically.

---

## Before You Push

Run these against the chart or script you touched. Pre-existing failures in other charts don't count against you.

### Helm charts

```bash
# 1. Lint
helm lint platform/charts/<name>/

# 2. HA gate — PDB, podAntiAffinity, replicaCount, and resource limits
#    Scoped: exits 0/1 based only on this chart
bash scripts/ha-gate.sh --chart <name>

# 3. Autarky — no external registry references in templates
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/<name>/templates/ && echo "FAIL" || echo "PASS"

# 4. No :latest image tags in values.yaml
grep -n ":\s*latest" platform/charts/<name>/values.yaml && echo "FAIL" || echo "PASS"
```

For upstream wrapper charts (cilium, cert-manager, bitnami subcharts), run `helm dependency update platform/charts/<name>/` before lint.

### ArgoCD Application manifests

`kubectl apply --dry-run=client` does not work here — ArgoCD's CRDs are not installed in kind-sovereign-test. Use YAML-only validation:

```bash
python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())" \
  platform/argocd-apps/<tier>/<name>-app.yaml
```

Every Application must have `spec.revisionHistoryLimit: 3`. CI will reject anything else.

### Shell scripts

```bash
shellcheck -S error <script>.sh
```

Common pitfalls: unquoted variables (`"$var"` not `$var`); `local x=$(cmd)` must be split to `local x; x=$(cmd)` (SC2155); `grep pattern file` under `set -euo pipefail` needs `|| true` when no match is expected.

### Contract validator (when touching `contract/`)

```bash
python3 contract/validate.py contract/v1/tests/valid.yaml       # must pass
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml
echo "Exit: $?"   # expect 1
```

---

## HA Requirements

Every chart with a Deployment or StatefulSet must have:

- `replicaCount: 2` (or higher) in `values.yaml`
- A `PodDisruptionBudget` in `templates/pdb.yaml`
- `podAntiAffinity` in the Deployment spec

**Single-instance exception:** Some services cannot scale (MailHog, Mailpit). These require:

1. An entry in `platform/vendor/VENDORS.yaml` with `ha_exception: true` and `ha_exception_reason`.
2. `replicaCount: 1` in `values.yaml` with a comment pointing to the VENDORS.yaml entry.

Without both, CI fails. Do not try to add a PDB to a service that architecturally cannot have multiple replicas — add the VENDORS.yaml exception entry instead.

**Resource limits exception:** Some upstream charts have init containers whose resource limits are not configurable via `values.yaml`. When a non-configurable container prevents full limits coverage, add `limits_exception: true` and `limits_exception_reason: "<reason>"` to the service's VENDORS.yaml entry. The HA gate skips the resource limits check for that chart. All configurable containers must still have limits set.

---

## Autarky Invariant

Chart templates must never reference external registries (`docker.io`, `quay.io`, `ghcr.io`, `gcr.io`, `registry.k8s.io`). Images flow through `{{ .Values.global.imageRegistry }}`. This is G6 — non-negotiable. CI rejects violations.

---

## Commit Message Format

```
type: description — enforcement target
```

Types: `feat`, `fix`, `docs`, `test`, `chore`, `refactor`. The em-dash names what the change enforces — use it when it applies.

Examples:
```
feat: add loki chart — enforce log aggregation at cluster layer
fix: correct replicaCount in prometheus-stack values.yaml
docs: add hetzner provider setup guide
```

---

## CI Gates

CI runs on every PR. The checks it runs are defined in `.github/workflows/validate.yml`. They cover: Helm lint, PDB, podAntiAffinity, replicaCount, no `:latest` tags, no hardcoded external registry in `image.repository`, shellcheck, vendor script flags, ArgoCD `revisionHistoryLimit`, network-policies egress coverage, bootstrap `--dry-run` flag, and README chart path existence.

`scripts/ha-gate.sh --chart <name>` covers the HA checks and resource limits in a single local command. Run it before pushing — CI surface for resource limits is narrower than what the gate checks.

If CI fails on your PR, the failure message names the check and the file. Fix the specific failure; don't work around it.
