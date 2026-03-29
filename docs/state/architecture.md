# Architecture: Decisions in Force

> This document is rewritten each sprint by the sync ceremony.
> It reflects current reality — not history, not aspiration.
> If a decision changed, this sentence changed. Use git log for history.

---

## Platform identity

Sovereign is a fully self-hosted, zero-trust Kubernetes platform deployable by any developer
from a single `bootstrap.sh` invocation. The domain is a runtime variable — never hardcoded.
Every service is installed by ArgoCD from this repository. Nothing is clicked into existence.
User-facing documentation lives in `docs/quickstart.md`, `docs/architecture.md`, and
`docs/providers/`.

---

## Vocabulary (unified model)

| Term | Definition |
|---|---|
| **Theme** | A strategic outcome (T1 Sovereignty, T2 Zero Trust, T3 Developer Autonomy, T4 Observability, T5 Resilience). Themes never complete — they accrete value. |
| **Epic** | A capability cluster owned by one theme. Has a `targetIncrement` that says which increment delivers it. |
| **Story** | A sprint-sized unit of work (≤ 8 points). Belongs to an epic. Sequencing is via `epicId → targetIncrement`. |
| **Increment** | The execution container for a sprint. Named after capability milestones. Stored in `prd/manifest.json` under `increments[]`. |
| **Sprint file** | `prd/increment-N-<name>.json` — the active story list for one increment. |
| **currentIncrement** | `manifest.json` field: the ID of the currently active increment. |
| **activeSprint** | `manifest.json` field: path to the active sprint file. |

The word "phase" is retired from code and data. If you see it in Python or JSON, it is a bug.

---

## Delivery model

| Concern | Decision |
|---|---|
| GitOps engine | ArgoCD App-of-Apps. Root app watches `argocd-apps/`. All services are ArgoCD Applications. |
| Infrastructure composition | Crossplane with Helm + Kubernetes providers. Cloud resources are XRDs, not scripts. |
| Secret storage | Sealed Secrets for GitOps-safe at-rest encryption. OpenBao for runtime secret injection. |
| Bootstrapping | `cluster/kind/bootstrap.sh` (kind) and `bootstrap/bootstrap.sh` (VPS) are the only manual steps. Everything after is ArgoCD. |
| Helm charts | Platform-level service charts in `platform/charts/<service>/`. Kind cluster bootstrap charts in `cluster/kind/charts/<service>/`. The root `charts/` directory is empty and retired. |
| Contract validation | `contract/v1/` defines the platform configuration schema. `contract/validate.py` enforces autarky invariants (externalEgressBlocked=true) before any cluster is provisioned. |
| Helm standards | Every chart templates `{{ .Values.global.domain }}` — no hardcoded domains in templates. Defaults in `values.yaml` may use the dogfood domain `sovereign-autarky.dev`. |
| ArgoCD apps | Every Application manifest must have `spec.revisionHistoryLimit: 3`. Validate with `yq e '.'` — not `kubectl apply --dry-run` (CRDs not installed locally). |

---

## Sovereignty policy

Two-tier: Tier 1 (CNI, storage, PKI, GitOps, service mesh, policy, observability) must be
CNCF/ASF/LF governed. Tier 2 (GitLab, Keycloak, Harbor, Backstage) must be Apache 2.0 / MIT / BSD.
A single vendor controlling a Tier 1 component's roadmap is grounds for replacement, not accommodation.
Full policy: `docs/governance/sovereignty.md`

---

## Network and security

| Concern | Decision |
|---|---|
| CNI | Cilium — also provides network policy enforcement and Hubble observability |
| Service mesh | Istio — mTLS everywhere inside the cluster |
| Policy engine | OPA/Gatekeeper — admission control |
| Runtime security | Falco |
| Vulnerability scanning | Trivy Operator (continuous) + OWASP ZAP (web) |
| Certificate authority | cert-manager — self-signed bootstrap, Let's Encrypt production |

---

## Storage

Rook/Ceph provides block, filesystem, and object storage. All stateful services use Ceph
storage classes. StorageClass names flow through `{{ .Values.global.storageClass }}` — never
hardcoded. Ceph encryption at rest is required.

Rook/Ceph is a storage **provider** — it creates StorageClasses, it does not consume a
pre-existing StorageClass for its own StatefulSet PVs. The standard HA acceptance criterion
"volumeClaimTemplates reference global.storageClass" does not apply to the rook-ceph chart.
For mon/mgr storage, add a CephCluster CR template with `spec.storage.storageClassDeviceSets`
referencing `{{ .Values.global.storageClass }}`.

---

## Identity

Keycloak is the SSO provider. All user-facing services authenticate through Keycloak OIDC.
Realm: `sovereign`. The Keycloak URL is `https://auth.{{ .Values.global.domain }}`.
In-cluster applications must declare `KEYCLOAK_URL` explicitly in their Helm values — do not
rely on DNS resolution working before Keycloak is fully provisioned.

---

## Developer experience

| Service | Role |
|---|---|
| Sovereign PM | Self-hosted AI-native project management web app (Node.js/Express + React). Deployed at `pm.{{ .Values.global.domain }}`. Theme/Epic/Story UI, prd.json generation, Ralph run history. |
| code-server | Browser-based VS Code IDE for agents and developers. Helm chart and ArgoCD Application deployed. |
| Backstage | Service catalog — `platform/charts/backstage/` and ArgoCD Application (`argocd-apps/devex/backstage-app.yaml`) exist. |
| SonarQube | Static analysis history — `platform/charts/sonarqube/` deployed. CE is single-instance (`ha_exception: true` in `vendor/VENDORS.yaml`). Ingress at `sonar.{{ .Values.global.domain }}`. ArgoCD Application deployed. |
| ReportPortal | Test result history — `platform/charts/reportportal/` deployed. Ingress at `reports.{{ .Values.global.domain }}`. ArgoCD Application deployed. |

Sovereign PM uses a multi-stage Dockerfile: Vite builds the React frontend, tsc builds the
Express backend, combined in a single production image. Database: bitnami/postgresql subchart
(quick-start); Crossplane XRC is the production path once foundations are running.

---

## Observability stack

| Signal | Tool |
|---|---|
| Metrics | Prometheus (kube-prometheus-stack) + Alertmanager |
| Dashboards | Grafana with Keycloak OIDC |
| Logs | Loki (simple scalable mode, Ceph object storage) |
| Long-term metrics | Thanos (sidecar mode, Ceph object storage) |
| Traces | Tempo distributed (Ceph object storage) |

All observability charts register their data sources in Grafana via a ConfigMap in the chart's
`templates/` directory. No manual datasource configuration.

---

## Quality gates (non-negotiable)

Every story must pass before `reviewed: true`:

1. `helm lint platform/charts/<name>/` — zero errors
2. `helm template | kubectl apply --dry-run=client` — zero errors (core K8s resources only)
3. `helm template | grep PodDisruptionBudget` — must match ≥ 1 (≥ 1 per component for distributed-mode charts)
4. `helm template | grep podAntiAffinity` — must match ≥ 1
5. `grep replicaCount platform/charts/<name>/values.yaml` — must be ≥ 2. **Exception**: if `vendor/VENDORS.yaml` has `ha_exception: true` for this service with a documented `ha_exception_reason`, then `replicaCount: 1` is acceptable — but only if the chart has a top-level `replicaCount: 1` with a comment referencing the VENDORS.yaml exception entry. Undocumented `replicaCount: 1` always fails.
6. `helm template platform/charts/<name>/ | python3 scripts/check-limits.py` — every container and initContainer must have `resources.requests` AND `resources.limits`. Use `check-limits.py`, not `grep -A5 resources:` — grep misses individual containers that lack limits even when others have them.
7. `shellcheck` on all `.sh` files — zero errors
8. **ArgoCD Application and CRD-backed manifests**: `python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())"` — not `kubectl apply --dry-run=client` (CRDs not installed in kind-sovereign-test). Core K8s resources (Deployment, Service, Ingress, PDB) still use `kubectl apply --dry-run=client`.
9. `yq e '.'` on all YAML files touched — valid YAML
10. `yq '.spec.revisionHistoryLimit' argocd-apps/<tier>/<name>-app.yaml` — must equal 3
11. `helm template platform/charts/<name>/ | grep -i datasource` — required for all observability charts
12. Branch pushed to remote + PR merged to main — proof of work

---

## What this platform is not

- Not a managed service. No cloud provider controls any component.
- Not a monolith. Each service is independently deployed and upgradeable.
- Not a demo. Every component is production-grade or has a documented upgrade path.

Full scope definition: `docs/governance/scope.md`
