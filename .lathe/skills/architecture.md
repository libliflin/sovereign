# Architecture — Sovereign Platform

## Core Pattern: ArgoCD App-of-Apps

Everything after the initial bootstrap is managed by ArgoCD. The root app (`argocd-apps/root-app.yaml`) deploys all service apps. No manual `kubectl apply` after bootstrap — all changes go through Git. Each service app points at a Helm chart in `platform/charts/<service>/`.

## Chart Structure

```
platform/charts/<service>/
  Chart.yaml
  values.yaml        # defaults — domain, storageClass, imageRegistry all templated
  templates/         # Kubernetes manifests, all values via .Values
```

Every chart MUST have:
- `replicaCount: 2` minimum
- `podDisruptionBudget: { minAvailable: 1 }`
- `podAntiAffinity` (preferredDuringScheduling minimum)
- `readinessProbe` + `livenessProbe` on every container
- `resources.requests` + `resources.limits`

HA exceptions (architecturally single-instance) are declared in `platform/vendor/VENDORS.yaml` with `ha_exception: true` — the CI checks skip PDB/antiAffinity for those.

## Autarky: The Build Pipeline

After bootstrap, no external registry pulls. The vendor system (Gentoo-inspired):

1. `platform/vendor/fetch.sh` — SHA-verified mirror of upstream source into internal Forgejo
2. `platform/vendor/build.sh` — builds distroless OCI images from patched source
3. `platform/vendor/deploy.sh` — stages → smoke test → promote → production
4. `platform/vendor/rollback.sh` — revert to last-known-good image SHA (must complete < 2 minutes)
5. `platform/vendor/backup.sh` — CronJob that mirrors to secondary storage

Each vendored service has `platform/vendor/recipes/<name>/recipe.yaml` declaring rollout strategy and backup priority.

Image tag format: `<upstream-version>-<source-sha>-p<patch-count>` (e.g. `v1.16.0-a3f8c2d-p3`). Never `:latest`.

## The Contract

`contract/validate.py` enforces the sovereign cluster contract. A `cluster-values.yaml` must:
- Set `apiVersion: sovereign.dev/cluster/v1`
- Include all required fields (domain, imageRegistry, storage classes, network, PKI)
- Set `network.networkPolicyEnforced: true`, `autarky.externalEgressBlocked: true`, `autarky.imagesFromInternalRegistryOnly: true` — these are invariants, not configuration

The validator exits 0 for valid, exits 1 with specific violation messages for invalid. Test fixtures in `contract/v1/tests/`.

## Key Values Conventions

Never hardcode in templates:
- Domain → `{{ .Values.global.domain }}`
- Storage class → `{{ .Values.global.storageClass }}`
- Image registry → `{{ .Values.global.imageRegistry }}/`
- Passwords/secrets → Sealed Secrets or OpenBao refs

`values.yaml` defaults may use `sovereign-autarky.dev` as the dogfood domain — that is correct. Never put a literal domain in `templates/`.

## HA Architecture

```
etcd quorum:   requires odd node count, minimum 3 (1 failure tolerance)
Ceph quorum:   requires 3 OSDs
API server:    kube-vip floating VIP across all control plane nodes
CNI:           Cilium DaemonSet (inherently HA)
Storage:       Rook/Ceph replication factor 3
```

`bootstrap.sh` refuses to proceed with fewer than 3 nodes or an even node count. This is not configurable.

## Kind (Local Development)

`cluster/kind/bootstrap.sh` creates a 3-node kind cluster (`sovereign-test`). It:
- Accepts `--dry-run`, `--domain`, `--output`, `--cluster-name`
- Creates a 3-node cluster (1 control-plane + 2 workers) via `cluster/kind/kind-config.yaml`
- Emits `cluster-values.yaml` conforming to `contract/v1`
- Validates the emitted values file against the contract

Kind is for static analysis and local evaluation. CI never runs bootstrap in full execution.

## Security Layers

- **Istio STRICT mTLS** — all service-to-service traffic encrypted and authenticated
- **OPA/Gatekeeper** — policy enforcement at admission
- **Falco** — runtime threat detection
- **Trivy** — vulnerability scanning before admission
- **NetworkPolicy** — deny-all with explicit allows
- **Zero open ports** — Cloudflare Tunnel (default) or custom front door; no port 22

## State Files

- `prd/manifest.json` — source of truth for active sprint and increments
- `prd/backlog.json` — all future stories
- `prd/constitution.json` — themes and constitutional gates (G1, G2, G6, G7)
- `docs/state/agent.md` — live briefing, rewritten each sprint by sync ceremony
- `docs/state/architecture.md` — architecture decisions currently in force

## Constitutional Gates

- **G1** — Ceremony scripts compile without errors
- **G2** — `docs/state/agent.md` and `docs/state/architecture.md` exist and are current
- **G6** — Zero external registry references in chart templates
- **G7** — Contract validator test suite passes (valid.yaml passes, all invalid-*.yaml fail)
