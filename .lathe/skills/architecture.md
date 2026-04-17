# Architecture

Key decisions visible in the code that every cycle needs to understand.

---

## GitOps Engine: ArgoCD App-of-Apps

After bootstrap, everything is managed by ArgoCD. The root app (`argocd-apps/root-app.yaml`) deploys all service apps. No manual `kubectl apply` after bootstrap. Every change goes through Git.

**ArgoCD Application invariants:**
- Every Application manifest must have `spec.revisionHistoryLimit: 3` (enforced by `argocd-validate` job in CI)
- Domain injection uses `spec.source.helm.parameters`, not `valueFiles`
- ArgoCD CRDs are not in the kind cluster — validate Application manifests with `python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())"`, not `kubectl apply --dry-run`

## Chart Locations

- `platform/charts/<service>/` — platform service charts (Istio, OpenBao, Harbor, Backstage, etc.)
- `cluster/kind/charts/<service>/` — kind bootstrap charts (cert-manager, cilium, sealed-secrets)
- Root `charts/` is empty and retired — do not create charts there

## HA: Non-Negotiable

Every chart must render with:
- `replicaCount >= 2` in values.yaml (or `ha_exception: true` in `platform/vendor/VENDORS.yaml`)
- `PodDisruptionBudget` (minAvailable: 1)
- `podAntiAffinity` in rendered output (values-level alone is insufficient)
- `resources.requests` and `resources.limits` on every container and initContainer

Enforced by:
- `scripts/ha-gate.sh` — local check across all charts
- `scripts/check-limits.py` — verifies resource limits exhaustively
- `.github/workflows/validate.yml` — runs on every PR
- `.github/workflows/ha-gate.yml` — runs when `platform/charts/**` changes

HA exceptions (single-instance upstreams) require both:
1. `ha_exception: true` in `platform/vendor/VENDORS.yaml`
2. `replicaCount: 1` with a comment `# ha_exception: see vendor/VENDORS.yaml` in values.yaml

## Autarky: Zero External Registry References

After bootstrap, the cluster never pulls from docker.io, quay.io, ghcr.io, gcr.io, or registry.k8s.io.

**In chart templates:** All image references must use `{{ .Values.global.imageRegistry }}/` — never a hardcoded registry.

**In values.yaml:** `global.imageRegistry: "harbor.{{ .Values.global.domain }}/sovereign"` is the convention.

**Image tag format:** `<upstream-version>-<source-sha>-p<patch-count>` (e.g., `v1.16.0-a3f8c2d-p3`). Never `:latest`.

Enforced by:
- G6 constitutional gate (checks `platform/charts/*/templates/`)
- `autarky-validate` job in `validate.yml`
- `grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/*/templates/`

The build pipeline (`platform/vendor/`) handles the vendor lifecycle: fetch → patch → build distroless → push to Harbor → deploy via ArgoCD.

## Zero Trust: mTLS Everywhere

Istio operates in STRICT PeerAuthentication mode (enforced by G8). All service-to-service traffic is authenticated and encrypted. deny-all NetworkPolicy with explicit allows. OPA/Gatekeeper for policy enforcement. Falco for runtime detection.

## Domain Variability

Domain is always a variable: `{{ .Values.global.domain }}` in templates. `values.yaml` defaults may use `sovereign-autarky.dev`. Never hardcode a domain in `templates/`.

Same pattern: `{{ .Values.global.storageClass }}` for storage class, `{{ .Values.global.imageRegistry }}` for registry.

## Cluster Contract

`contract/validate.py` enforces sovereignty invariants on `cluster-values.yaml` before any cluster is provisioned. Three invariants are non-negotiable (`const: true`):
- `network.networkPolicyEnforced: true`
- `autarky.externalEgressBlocked: true`
- `autarky.imagesFromInternalRegistryOnly: true`

Contract schema: `contract/v1/`. Test suite: `contract/v1/tests/` (valid.yaml must pass, invalid-egress-not-blocked.yaml must fail). Enforced by G7.

## Bootstrap Paths

**Kind (local, no cloud account):**
- `cluster/kind/bootstrap.sh` — creates 3-node kind cluster named `sovereign-test`
- Installs: Cilium CNI, cert-manager, sealed-secrets, local-path-provisioner, MinIO
- `cluster/kind/ha-bootstrap.sh` — 3 control-plane nodes HA variant

**VPS:**
- `bootstrap/config.yaml` — domain, provider, node count (must be odd, >= 3)
- `.env` — provider credentials
- `bootstrap/bootstrap.sh --estimated-cost` / `--confirm-charges`

## Delivery Machine: Ralph Ceremony Loop

`scripts/ralph/ceremonies.py` runs the full sprint cycle: orient → constitution-review → epic-breakdown → backlog-groom → plan → preflight → smart → execute → smoke → proof → review → retro → sync → advance.

Sprint state: `prd/manifest.json` (active sprint pointer), `prd/increment-N-<name>.json` (stories), `prd/backlog.json` (future work), `prd/constitution.json` (themes + gates).

Story lifecycle: `passes: false, reviewed: false` → implement → `passes: true, reviewed: false` → review ceremony → `passes: true, reviewed: true`.

## Security Scanning Pipeline

Runs continuously against all mirrored source in Forgejo Actions: SAST (Semgrep), SCA (Trivy), license audit, secret detection. CVE findings create Forgejo issues. Patches land in `platform/vendor/recipes/<name>/patches/`.

## Vendor Lifecycle

`platform/vendor/VENDORS.yaml` — catalog of all vendored services with license, distroless status, ha_exception.
`platform/vendor/recipes/<name>/` — build recipe per service.

Scripts: `fetch.sh`, `build.sh`, `deploy.sh`, `rollback.sh`, `backup.sh`. All vendor scripts must support `--dry-run` and `--backup` (enforced by CI).
