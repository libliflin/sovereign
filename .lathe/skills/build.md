# Build Process

How this project's components are built, validated, and deployed. Non-obvious parts only.

---

## Local Development: kind cluster

The primary local path. No cloud account needed.

```bash
# Create 3-node kind cluster with Cilium CNI, cert-manager, sealed-secrets,
# local-path-provisioner, and MinIO pre-installed
./cluster/kind/bootstrap.sh

# Preview without creating
./cluster/kind/bootstrap.sh --dry-run

# HA control-plane variant (3 control-plane + 2 workers)
./cluster/kind/ha-bootstrap.sh

# Tear down
kind delete cluster --name sovereign-test
```

After bootstrap, the cluster has a working StorageClass (`local-path`), CNI, and certificate management. Platform charts can be installed against `kind-sovereign-test` context.

---

## Helm Chart Validation (must pass before any push)

Run these against the chart you touched — not the entire repo (pre-existing failures elsewhere don't count against you).

```bash
# 1. Lint
helm lint platform/charts/<name>/

# 2. HA gate (PDB, podAntiAffinity, replicaCount) — scoped to one chart
bash scripts/ha-gate.sh --chart <name>

# 3. Resource limits — every container and initContainer
helm template platform/charts/<name>/ | python3 scripts/check-limits.py

# 4. Autarky — no external registry refs in templates
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/<name>/templates/ && echo "FAIL" || echo "PASS"

# 5. Datasource registration (observability charts only)
helm template platform/charts/<name>/ | grep -i datasource

# 6. ArgoCD apps — YAML validity (CRDs not in kind — no kubectl dry-run)
python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())" \
  platform/argocd-apps/<tier>/<name>-app.yaml
# revisionHistoryLimit must be 3:
yq '.spec.revisionHistoryLimit' platform/argocd-apps/<tier>/<name>-app.yaml
```

**Critical:** For upstream wrapper charts (cilium, cert-manager, etc.), `helm dependency update <chart>/` must run before lint.

---

## Shell Script Validation

```bash
shellcheck -S error <script>.sh
```

Common pitfalls that will fail shellcheck:
- Unquoted variables: use `"$var"` not `$var`
- `local x=$(cmd)` → split: `local x; x=$(cmd)` (SC2155)
- `grep somepattern file` under `set -euo pipefail` without `|| true` when no match is expected

---

## Contract Validation

```bash
# Must pass
python3 contract/validate.py contract/v1/tests/valid.yaml

# Must fail (exit 1) — invalid config should be rejected
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml
echo "Exit code: $?"  # expect: 1
```

---

## Platform Deploy (VPS path)

```bash
# Smoke test before deploy
platform/deploy.sh --dry-run

# Full deploy
platform/deploy.sh
```

Deploy script supports both `--dry-run` and `--backup` flags (CI verifies both are present).

---

## Autarky Build Pipeline (vendor/)

This is the pipeline that builds all images from source into Harbor. It's not needed for local kind development.

```bash
platform/vendor/fetch.sh    # SHA-verified mirror of upstream into Forgejo
platform/vendor/build.sh    # builds distroless OCI images from patched source
platform/vendor/deploy.sh   # stages, smoke tests, promotes to production
platform/vendor/rollback.sh # reverts to last-known-good SHA
platform/vendor/backup.sh   # mirrors repos + images to secondary storage
```

All vendor scripts must support `--dry-run` AND `--backup` flags. CI validates this.

---

## Sovereign PM (Node.js/React)

```bash
cd platform/sovereign-pm
npm run typecheck   # TypeScript validation
npm run lint        # ESLint
npm test            # Jest tests (--forceExit)
npm run build       # Production build (vite + tsc)
```

Multi-stage Dockerfile: Vite builds the React frontend; tsc builds the Express backend; combined in a single distroless-style production image.

---

## CI Gates (GitHub Actions)

Three workflow files under `.github/workflows/`:

- `validate.yml` — Helm lint, HA gate, PDB, podAntiAffinity, replicaCount, resource limits, autarky, ArgoCD revisionHistoryLimit, network-policies coverage, shellcheck, vendor script flags, bootstrap script dry-run. Runs on every PR and push to main.
- `ha-gate.yml` — shellcheck + ha-gate.sh --dry-run on PRs touching `platform/charts/`.
- `release.yml` — release automation.

CI is the floor. Red CI means no stakeholder can have a good experience. Fix it before new work.
