# Build — How This Project Builds

Sovereign is not a compiled binary. The "build" is Helm chart rendering, script execution, and the vendor image pipeline. No `make`, no `cargo build`, no `go build` at the project root.

---

## Local Development: kind Cluster

The primary local development target is a 3-node kind cluster.

```bash
# Standard kind bootstrap (creates sovereign-test cluster)
./cluster/kind/bootstrap.sh

# Preview without creating anything
./cluster/kind/bootstrap.sh --dry-run

# HA variant (3 control plane + 2 worker nodes)
./cluster/kind/ha-bootstrap.sh
```

After bootstrap, the kind cluster has: Cilium CNI, cert-manager, sealed-secrets, local-path-provisioner (default StorageClass), and MinIO.

**Tear down:**
```bash
kind delete cluster --name sovereign-test
```

---

## Helm Chart Development

Charts live in `platform/charts/<service>/`. Bootstrap charts (kind-specific) live in `cluster/kind/charts/<service>/`.

```bash
# Update dependencies (required before lint if Chart.yaml has dependencies)
helm dependency update platform/charts/<name>/

# Lint
helm lint platform/charts/<name>/

# Render (required for HA gate checks)
helm template sovereign platform/charts/<name>/ \
  --set global.domain=sovereign-autarky.dev \
  > /tmp/rendered.yaml
```

**Required values in every chart:**
- `global.domain`: always `{{ .Values.global.domain }}` in templates, never hardcoded
- `global.storageClass`: always `{{ .Values.global.storageClass }}`
- `global.imageRegistry`: always `{{ .Values.global.imageRegistry }}/` prefix on images
- `replicaCount`: must be ≥ 2 in values.yaml defaults

---

## Vendor Image Pipeline

Sovereign never pulls from external registries after bootstrap. All images go through the vendor system:

1. `platform/vendor/VENDORS.yaml` — registry of all vendored components (name, upstream repo, git SHA, license, distroless status)
2. `platform/vendor/recipes/<name>/recipe.yaml` — rollout strategy, backup config
3. `platform/vendor/recipes/<name>/patches/` — any source patches applied before build
4. Images are built from source into distroless OCI images and pushed to the internal Harbor registry

**Image tag format:** `<upstream-version>-<source-sha>-p<patch-count>` (e.g., `v1.16.0-a3f8c2d-p3`). Never `:latest`, never bare `:<version>`.

**Rollback:**
```bash
platform/vendor/rollback.sh <service-name>  # reverts to last-known-good SHA
```

---

## Contract Validator

The cluster configuration contract is validated before any cluster is provisioned:

```bash
python3 contract/validate.py <cluster-values.yaml>
# Exit 0: valid. Exit 1: validation error with field and rule.
```

Uses Python stdlib only — no dependencies to install.

---

## ArgoCD Application Manifests

ArgoCD apps live in `argocd-apps/<tier>/<service>-app.yaml`. The root App-of-Apps watches `argocd-apps/`.

**Validation:** Use `yq e '.'` to validate YAML — not `kubectl apply --dry-run` (CRDs not installed locally).

Every Application manifest must have:
```yaml
spec:
  revisionHistoryLimit: 3
```

Domain-aware charts receive `global.domain` via `spec.source.helm.parameters`, not via valueFiles.

---

## Sprint/Ceremony System

The delivery pipeline is Python-based, not a build tool:

```bash
scripts/ralph/ceremonies.py    # ceremony runner
prd/manifest.json              # sprint state (source of truth)
prd/increment-N-<name>.json    # active sprint stories
prd/constitution.json          # constitutional gates
```

To check ceremony script health:
```bash
python3 scripts/ralph/ceremonies.py --help  # must not error (G1 gate)
for tf in scripts/ralph/tests/test_*.py; do python3 "$tf"; done
```

---

## Notes for the Champion

- **No root-level Makefile or build script.** Everything is either a helm command or a bash script.
- **`charts/` (root level) is empty and retired.** Do not create charts there.
- **The `platform/deploy.sh` script** is the production deployment path. It has shellcheck enforced in CI.
- **`scripts/check-limits.py`** validates that every container in a rendered chart has resource requests and limits. Run it via stdin: `helm template ... | python3 scripts/check-limits.py`.
- **`scripts/ha-gate.sh`** runs PDB, podAntiAffinity, and replicaCount checks across all charts in one pass. Use `--dry-run` to list charts without running helm.
