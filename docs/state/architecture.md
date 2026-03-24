# Architecture: Decisions in Force

> This document is rewritten each sprint by the sync ceremony.
> It reflects current reality — not history, not aspiration.
> If a decision changed, this sentence changed. Use git log for history.

---

## Platform identity

Sovereign is a fully self-hosted, zero-trust Kubernetes platform deployable by any developer
from a single `bootstrap.sh` invocation. The domain is a runtime variable — never hardcoded.
Every service is installed by ArgoCD from this repository. Nothing is clicked into existence.

---

## Delivery model

| Concern | Decision |
|---|---|
| GitOps engine | ArgoCD App-of-Apps. Root app watches `argocd-apps/`. All services are ArgoCD Applications. |
| Infrastructure composition | Crossplane with Helm + Kubernetes providers. Cloud resources are XRDs, not scripts. |
| Secret storage | Sealed Secrets for GitOps-safe at-rest encryption. OpenBao for runtime secret injection. |
| Bootstrapping | `bootstrap.sh` is the only manual step. It installs Phase 1 foundations; ArgoCD takes over. |
| Helm standards | Every chart templates `{{ .Values.global.domain }}` — no hardcoded domains in templates. Defaults in `values.yaml` may use the dogfood domain `sovereign-autarky.dev`. |
| ArgoCD apps | Every Application manifest must have `spec.revisionHistoryLimit: 3`. |

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

---

## Identity

Keycloak is the SSO provider. All user-facing services authenticate through Keycloak OIDC.
Realm: `sovereign`. The Keycloak URL is `https://auth.{{ .Values.global.domain }}`.

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
1. `helm lint charts/<name>/` — zero errors
2. `helm template | kubectl apply --dry-run=client` — zero errors
3. `helm template | grep PodDisruptionBudget` — must match ≥ 1 (≥ 1 per component for distributed-mode charts)
4. `helm template | grep podAntiAffinity` — must match ≥ 1
5. `grep replicaCount charts/<name>/values.yaml` — must be ≥ 2
6. `shellcheck` on all `.sh` files — zero errors
7. `yq e '.'` on all ArgoCD application manifests — valid YAML
8. `yq '.spec.revisionHistoryLimit' argocd-apps/<tier>/<name>-app.yaml` — must equal 3
9. `helm template charts/<name>/ | grep -i datasource` — required for all observability charts
10. Branch pushed to remote + PR merged to main — proof of work

---

## What this platform is not

- Not a managed service. No cloud provider controls any component.
- Not a monolith. Each service is independently deployed and upgradeable.
- Not a demo. Every component is production-grade or has a documented upgrade path.

Full scope definition: `docs/governance/scope.md`
