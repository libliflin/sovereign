# Architecture

Key decisions visible in the code. These are decisions already made — not recommendations.

---

## Structural Layout

```
cluster/          — cluster provider scripts (kind bootstrap, eventually VPS)
  kind/           — kind-based local cluster (the development and testing path)
    bootstrap.sh  — creates sovereign-test kind cluster (~4 minutes)
    charts/       — charts installed at cluster-bootstrap time (cilium, cert-manager, sealed-secrets)
platform/         — everything deployed onto a running cluster
  charts/         — 30+ Helm charts for all platform services
  vendor/         — autarky build system (fetch, build, deploy, rollback, backup)
    recipes/      — per-service build recipes (one directory per vendor)
    VENDORS.yaml  — manifest of all vendored dependencies with license/distroless tracking
contract/         — cluster contract schema and validator
  v1/             — current contract version
  validate.py     — stdlib-only validator (no dependencies to install)
prd/              — sprint mechanics (manifest.json, increment files, backlog.json)
scripts/          — delivery tooling (ralph ceremonies, ha-gate.sh, check-limits.py)
  ralph/          — ceremony system (the autonomous delivery loop)
argocd-apps/      — ArgoCD Application manifests (tier-organized)
docs/             — governance docs, state docs, provider guides
  state/          — live briefing files rewritten each sprint
  governance/     — license policy, sovereignty policy, scope policy
```

The root `charts/` directory is retired and empty. Do not create charts there.

---

## Core Patterns

### App-of-Apps GitOps
ArgoCD watches this repo. The root app (`argocd-apps/`) deploys all service apps. Everything after bootstrap is ArgoCD-managed. No manual `kubectl apply` after bootstrap — all changes go through Git.

### Domain as a Variable
`{{ .Values.global.domain }}` is used everywhere in Helm templates. Never hardcoded. Default in `values.yaml` is `sovereign-autarky.dev` (the dogfood domain). This is correct — overridden at deploy time by the cluster operator.

```yaml
global:
  domain: "sovereign-autarky.dev"
  storageClass: "ceph-block"
  imageRegistry: "harbor.{{ .Values.global.domain }}/sovereign"
```

### Autarky
After bootstrap, the cluster never pulls from docker.io, quay.io, ghcr.io, gcr.io, or registry.k8s.io. The autarky chain:
1. `platform/vendor/fetch.sh` — SHA-verified mirror of upstream source into internal GitLab
2. `platform/vendor/build.sh` — builds distroless OCI images from patched source
3. `platform/vendor/deploy.sh` — stages → smoke test → promotes to production
4. `platform/vendor/rollback.sh` — reverts to last-known-good image SHA
5. `platform/vendor/backup.sh` — mirrors repos + images to secondary storage (CronJob)

G6 (constitutional gate) enforces this: any external registry reference in `platform/charts/*/templates/` fails the gate.

### Distroless Images
All container images use distroless base images. No shell, no package manager. Any service that cannot run distroless is marked deprecated in `VENDORS.yaml` with a `deprecated: true` flag and a migration path.

### HA Everywhere
Every chart must have:
- `replicaCount: 2` minimum (in `values.yaml`, configurable)
- `PodDisruptionBudget` with `minAvailable: 1`
- `podAntiAffinity` (preferredDuringScheduling minimum)
- `readinessProbe` and `livenessProbe` on every container
- `resources.requests` and `resources.limits` on every container

Enforced by `scripts/ha-gate.sh` locally and by the `ha-gate.yml` and `validate.yml` CI workflows.

Exception: `ha_exception: true` in `VENDORS.yaml` for a service skips the `replicaCount` check (documented when a service genuinely cannot run replicated).

### Cluster Contract (contract/v1/)
A structured YAML schema (`sovereign.dev/cluster/v1`) that cluster-values.yaml must conform to. Enforced by `contract/validate.py` (stdlib-only, no pip install required). The negative test (`contract/v1/tests/invalid-egress-not-blocked.yaml`) must *fail* validation — this is G7.

Required fields checked: runtime.domain, runtime.imageRegistry.internal, storage (block/file/object), network.ingressClass, pki.clusterIssuer.

Const-true fields: `network.networkPolicyEnforced`, `autarky.externalEgressBlocked`, `autarky.imagesFromInternalRegistryOnly` — these must be `true` and cannot be overridden to `false`.

---

## Constitutional Gates (prd/constitution.json → scripts/ralph/lib/gates.py)

Four gates that must all pass before ceremony work continues:

- **G1** — `scripts/ralph/ceremonies.py` and its lib imports compile without errors
- **G2** — `docs/state/agent.md` and `docs/state/architecture.md` exist and were modified in the last 14 days
- **G6** — Zero external registry references in `platform/charts/*/templates/`
- **G7** — `contract/validate.py` accepts `contract/v1/tests/valid.yaml` and rejects `contract/v1/tests/invalid-egress-not-blocked.yaml`

---

## Service Map

### Platform Services (platform/charts/)
ArgoCD manages all of these after bootstrap.

| Service | Chart | Purpose |
|---|---|---|
| ArgoCD | `argocd` | GitOps controller — the root of everything |
| GitLab | `forgejo` (replacement) | SCM, CI, internal git mirrors |
| Harbor | `harbor` | Internal OCI registry (autarky anchor) |
| Keycloak | `keycloak` | SSO/OIDC for all services |
| OpenBao | `openbao` | Secrets management (Apache 2.0 Vault fork) |
| Backstage | `backstage` | Developer portal and service catalog |
| code-server | `code-server` | Browser-based VS Code for developers |
| Istio | `istio` | mTLS service mesh (STRICT mode) |
| OPA/Gatekeeper | `opa-gatekeeper` | Policy enforcement |
| Falco | `falco` | Runtime security detection |
| Trivy Operator | `trivy-operator` | Continuous vulnerability scanning |
| Prometheus Stack | `prometheus-stack` | Metrics collection |
| Grafana | (via prometheus-stack) | Dashboards |
| Loki | `loki` | Log aggregation |
| Tempo | `tempo` | Distributed tracing |
| Thanos | `thanos` | Long-term metrics retention |
| Crossplane | `crossplane` | Infrastructure compositions (namespaces, RBAC) |
| Sealed Secrets | `sealed-secrets` | GitOps-safe encrypted secrets |
| cert-manager | `cert-manager` | TLS certificate management |
| Cilium | `cilium` | CNI + NetworkPolicy enforcement |
| Rook/Ceph | (not in platform/charts yet) | Block, file, object storage |
| Chaos Mesh | `chaos-mesh` | Chaos engineering |
| k6 | `k6`, `k6-operator` | Load testing |
| Selenium Grid | `selenium-grid` | Browser automation |
| WireMock | `wiremock` | API mocking |

### Cluster Bootstrap Charts (cluster/kind/charts/)
Installed by `cluster/kind/bootstrap.sh` before ArgoCD takes over:
- `cert-manager`
- `cilium`
- `sealed-secrets`

---

## Zero Open Ports Design
Default front door: Cloudflare Tunnel + Zero Trust Access. VPS firewall drops everything except Cloudflare's published IP ranges. Port 22 is never open — SSH goes through `cloudflare access ssh`. The front door is pluggable: implement the 5-hook interface in `bootstrap/frontdoor/` to swap it out.

---

## Delivery Machine (scripts/ralph/)
The ralph ceremony system orchestrates sprint delivery:
- `ceremonies.py` — main entry point, routes to ceremony implementations
- `ceremonies/` — one file per ceremony (orient, plan, execute, verify, retro, sync, advance...)
- `lib/orient.py` — state assessment (reads prd/ files, evaluates gates)
- `lib/gates.py` — constitutional gate evaluation

The ceremony loop: orient → constitution-review → epic-breakdown → backlog-groom → plan → preflight → smart → execute → smoke → proof → review → retro → sync → advance.

Story lifecycle in sprint files: `passes: false, reviewed: false` → `passes: true, reviewed: false` → `passes: true, reviewed: true`. The agent marks `passes: true`. Only the review ceremony marks `reviewed: true`.

---

## Image Tag Convention
Format: `<upstream-version>-<source-sha>-p<patch-count>` (e.g., `v1.16.0-a3f8c2d-p3`). Never `:latest`. Never just `:<version>`.

---

## Key Non-Obvious Things

1. **`platform/vendor/VENDORS.yaml` vs. chart templates**: The VENDORS.yaml tracks what's been vendored and its license/distroless status. It's not one-to-one with `platform/charts/` — a chart might be defined before the vendor recipe exists.

2. **`ha_exception` in VENDORS.yaml**: Some services (e.g., single-instance CronJobs) can't run replicated. The CI HA replicaCount check is skipped if `ha_exception: true` is set for that vendor entry.

3. **G2 tracks staleness, not correctness**: The gate checks that `docs/state/agent.md` was modified recently, not that its content is accurate. A sprint sync ceremony that touches the file but writes stale content passes G2.

4. **`contract/validate.py` uses stdlib only**: No `pip install`. Intentional — the validator must run in any environment without dependency management. Do not add external imports.

5. **ArgoCD `revisionHistoryLimit: 3`**: All ArgoCD Application manifests must have this set to 3. Enforced by the `argocd-validate` CI job. Missing this fails CI.

6. **Distributed-mode charts have multiple PDBs**: Loki Simple Scalable, Tempo distributed deploy one PDB per component (ingester, distributor, querier, etc.). The HA gate counts PDBs — for these charts, count must be >= number of deployed components.
