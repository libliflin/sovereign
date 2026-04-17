# Build

Non-obvious build processes in this project.

---

## Kind Cluster Bootstrap (~4 minutes)

```bash
./cluster/kind/bootstrap.sh              # creates sovereign-test cluster
./cluster/kind/bootstrap.sh --dry-run   # preview only
```

Installs in order: 3-node kind cluster → Cilium CNI → cert-manager → sealed-secrets → local-path-provisioner → MinIO. These are the platform foundation components that other charts depend on.

**Kind context:** `kind-sovereign-test`

**Kind storage:** local-path (RWO only — no RWX). This is acceptable for local testing. Production uses Rook/Ceph.

**Kind HA variant:** `cluster/kind/ha-bootstrap.sh` + `cluster/kind/kind-ha-config.yaml` (3 control-plane nodes).

After bootstrap, `cluster-values.yaml` is the contract file for this cluster. Validate it:
```bash
python3 contract/validate.py cluster-values.yaml
```

## Helm Chart Dependency Update

When `Chart.yaml` has `dependencies:`, run before lint:
```bash
helm dependency update platform/charts/<name>/
```

Then lint:
```bash
helm lint platform/charts/<name>/
```

## Autarky Build Pipeline (vendor system)

The full vendor lifecycle — only partially implemented, but the structure is present:

```
platform/vendor/
├── fetch.sh        # SHA-verified mirror upstream source into internal Forgejo
├── build.sh        # build distroless OCI images from patched source
├── deploy.sh       # stage → smoke test → promote to production
├── rollback.sh     # revert to last-known-good image SHA
├── backup.sh       # mirror repos + images to secondary storage (runs as CronJob)
├── audit.sh        # audit vendor catalog
├── VENDORS.yaml    # catalog: name, upstream, version, license, distroless, ha_exception
└── recipes/
    └── <name>/
        ├── recipe.yaml          # rollout.strategy, rollout.max_unavailable, backup.priority
        └── patches/             # security patches applied during build
```

All vendor scripts must support `--dry-run` and `--backup` (CI-checked).

**Image tag format:** `<upstream-version>-<source-sha>-p<patch-count>` (e.g., `v1.16.0-a3f8c2d-p3`). Never `:latest`.

## VENDORS.yaml Schema

Required fields per entry: `name`, `upstream`, `version`, `license`, `distroless`.

Blocked licenses: BSL, SSPL. If present, entry must be `deprecated: true`.

HA exception (single-instance upstreams):
```yaml
- name: sonarqube
  ha_exception: true
  ha_exception_reason: "SonarQube CE is architecturally single-instance"
```

## ArgoCD Application Build

Applications in `argocd-apps/<tier>/<service>-app.yaml`. Validate YAML:
```bash
python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())"
yq '.spec.revisionHistoryLimit' argocd-apps/<tier>/<name>-app.yaml   # must be 3
```

Domain injection pattern:
```yaml
spec:
  source:
    helm:
      parameters:
        - name: global.domain
          value: sovereign-autarky.dev
```

## VPS Provisioning (bootstrap)

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
# Edit: domain (Cloudflare-managed), provider (hetzner/do/vultr), nodes.count (odd >= 3)
cp .env.example .env
# Edit: HETZNER_TOKEN, CLOUDFLARE_API_TOKEN, etc.
source .env
./bootstrap/bootstrap.sh --estimated-cost    # no charges
./bootstrap/bootstrap.sh --confirm-charges   # provisions real servers
./bootstrap/verify.sh                        # post-provision check
```

## Sovereign PM Webapp Build (Node.js + React)

Multi-stage Dockerfile: `vite build` (React frontend) → `tsc` (Express/Node backend) → combined into distroless production image. Located in `platform/charts/sovereign-pm/`.

## Ceremony Loop

```bash
python3 scripts/ralph/ceremonies.py   # run the full sprint ceremony
```

The loop reads `prd/manifest.json` → finds active sprint → runs ceremonies in order. G1 gate catches syntax errors AND broken imports before the loop attempts to run.
