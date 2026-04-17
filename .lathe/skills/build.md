# Build

Non-obvious things about how this project builds and deploys.

---

## Helm Chart Dependencies

Some charts have upstream chart dependencies declared in `Chart.yaml`. These require an explicit dependency update step before linting or templating:

```bash
helm dependency update platform/charts/<name>/
helm lint platform/charts/<name>/
```

The `validate.yml` CI job runs `helm dependency update` before `helm lint`. The downloaded sub-charts land in `platform/charts/<name>/charts/` and are cached in CI by `Chart.lock` hash. Locally, if `helm lint` complains about missing dependencies, run `helm dependency update` first.

---

## Vendor Build Pipeline

The autarky build pipeline operates in five stages. Each stage is a standalone script that can be run independently:

```bash
# 1. Fetch: SHA-verified source mirror into internal GitLab
platform/vendor/fetch.sh [--dry-run] [--backup]

# 2. Build: compile distroless OCI images from patched source
platform/vendor/build.sh [--dry-run] [--backup]

# 3. Deploy: staging → smoke test → promote to production
platform/vendor/deploy.sh [--dry-run] [--backup]

# 4. Rollback: revert to last-known-good image SHA
platform/vendor/rollback.sh <service-name>

# 5. Backup: mirror repos + images to secondary storage (runs as CronJob)
platform/vendor/backup.sh [--dry-run] [--backup]
```

All vendor scripts must handle `--dry-run` and `--backup` flags (enforced by CI in `shell-validate` job).

### Recipe structure
Each vendor has a recipe at `platform/vendor/recipes/<name>/`:
- `recipe.yaml` — rollout strategy, max_unavailable, backup priority, build instructions
- `patches/` — security or compatibility patches applied to the upstream source

### VENDORS.yaml
`platform/vendor/VENDORS.yaml` is the manifest of all vendored dependencies. Required fields per entry:
```yaml
- name: <chart-name>
  upstream: <upstream-repo-url>
  version: <pinned-version>
  license: "Apache-2.0"   # blocked: BSL, SSPL
  distroless: true        # must be true or deprecated: true
  ha_exception: false     # set true only for genuinely single-instance services
```

CI validates the schema. Any entry with a BSL or SSPL license that isn't marked `deprecated: true` fails CI.

---

## Image Tag Format

`<upstream-version>-<source-sha>-p<patch-count>` — e.g., `v1.16.0-a3f8c2d-p3`

- `upstream-version`: the upstream release tag (e.g., `v1.16.0`)
- `source-sha`: the first 7 chars of the git SHA that was mirrored
- `patch-count`: number of patches in `vendor/recipes/<name>/patches/`

Never `:latest`. Never just the version. This format allows Harbor to deduplicate builds and `rollback.sh` to identify a last-known-good SHA.

---

## kind Bootstrap

`cluster/kind/bootstrap.sh` creates the `sovereign-test` kind cluster (~4 minutes):
1. Validates prerequisites (kind, kubectl, helm, Docker running)
2. Creates the kind cluster using the config in `cluster/kind/`
3. Installs bootstrap charts in order: cilium → cert-manager → sealed-secrets
4. Verifies the cluster health

Flags:
```bash
./cluster/kind/bootstrap.sh           # full bootstrap
./cluster/kind/bootstrap.sh --dry-run # preview intended actions without executing
```

Teardown:
```bash
kind delete cluster --name sovereign-test
```

---

## VPS Bootstrap

`bootstrap/bootstrap.sh` provisions real VPS nodes and installs the cluster:
```bash
./bootstrap/bootstrap.sh --estimated-cost   # preview monthly cost before provisioning
./bootstrap/bootstrap.sh --confirm-charges  # actual provisioning (creates real servers)
./bootstrap/verify.sh                       # post-deploy verification
```

Config files:
- `bootstrap/config.yaml` (from `bootstrap/config.yaml.example`) — domain, provider, frontDoor, node count
- `.env` (from `.env.example`) — API tokens for Hetzner, Cloudflare, etc.

---

## Sprint/Delivery Build

The delivery system isn't a build artifact — it's Python scripts. But there's a compile-time gate:

```bash
# G1: all ceremony scripts compile and can be imported
python3 -m py_compile scripts/ralph/ceremonies.py
python3 -c "from scripts.ralph.lib import orient, gates"
```

The `scripts/ralph/` directory uses Python package structure (`__init__.py` etc.) so the import path matters. Run ceremony scripts from the repo root.

---

## Node.js / package.json

There's a `package.json` in the root (from the `sovereign-pm` increment). This is the Sovereign PM web app:
- Backend: Node.js/Express
- Frontend: React
- Helm chart: `platform/charts/sovereign-pm/`

Build:
```bash
npm install
npm run build    # or npm start for development
```

This is one of the few non-shell, non-Python components. Its chart follows the same HA and autarky conventions as all others.

---

## ArgoCD Application Manifests

After bootstrap, ArgoCD watches `argocd-apps/` and deploys everything automatically. To add a new service:
1. Create `platform/charts/<name>/` with all required chart files
2. Add an ArgoCD Application manifest in `argocd-apps/` with:
   - `revisionHistoryLimit: 3` (required by CI)
   - `spec.source.repoURL` pointing to this repo
   - `spec.destination.namespace` set to the service's dedicated namespace

The root App-of-Apps pattern means: merge to main → ArgoCD detects the new Application manifest → deploys the chart automatically.

---

## deploy.sh

`platform/deploy.sh` is the manual deployment script (for charts not yet in ArgoCD, or emergency deploys). Shellchecked by CI. Must have no hardcoded IP addresses.

---

## Common Build Gotchas

1. **Helm dependency update required**: If `helm lint` fails with "no chart found for <name>", run `helm dependency update` first.

2. **Distroless means no shell**: Images built by the vendor pipeline use distroless bases. If a service needs shell access (debugging), it needs a debug variant — not a switch to a non-distroless base.

3. **`{{ .Values.global.imageRegistry }}` not `harbor.*`**: All image repository references in chart templates must use the global variable, not a hardcoded harbor URL. The harbor URL itself includes the domain variable.

4. **G6 checks templates/, not values.yaml**: The autarky gate (`grep` for external registry refs) only scans `platform/charts/*/templates/`. A hardcoded `docker.io/...` in `values.yaml` (as an image tag default) bypasses G6. The CI `helm-validate` job has a separate assertion for this (`Assert image.repository uses global.imageRegistry`).

5. **`check-limits.py` vs. `grep`**: Never use grep to check resource limits — it misses initContainers. Always use `helm template ... | python3 scripts/check-limits.py`.
