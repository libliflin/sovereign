# Architecture: Key Decisions in Force

Stable decisions that shape every implementation choice. Read `docs/state/architecture.md` for the authoritative version — this file captures the champion-relevant subset with enough context to understand *why*.

---

## The Core Pattern: ArgoCD App-of-Apps

After `bootstrap.sh` runs, the cluster is self-managing via ArgoCD. The root app (`platform/argocd-apps/`) watches this repo and deploys all service Applications. No manual `kubectl apply` after bootstrap. All changes go through Git → PR → CI → merge → ArgoCD sync.

**Why this matters for the champion:** A service that's "deployed" but not wired into ArgoCD is a half-finished service. The operator can't trust it, and the developer can't trust its availability.

---

## Chart Locations (non-obvious)

| Type | Location |
|---|---|
| Platform services (Grafana, Loki, Backstage, etc.) | `platform/charts/<service>/` |
| Kind cluster bootstrap charts | `cluster/kind/charts/<service>/` |
| Root `charts/` | **Empty and retired — never use** |

**ArgoCD apps** live in `platform/argocd-apps/<tier>/`. Every Application must have `spec.revisionHistoryLimit: 3`.

---

## The Autarky Invariant (G6)

After bootstrap, the cluster never pulls from external registries (`docker.io`, `quay.io`, `ghcr.io`, `gcr.io`, `registry.k8s.io`). Chart templates must not reference external registries. The `imageRegistry` flows through `{{ .Values.global.imageRegistry }}`.

**Exception:** The kind path uses upstream images during kind bootstrap (before the internal Harbor registry exists). This is intentional and documented.

**Gate:** `grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/*/templates/` must return nothing.

---

## HA: Non-Negotiable (G-HA)

Every chart with a Deployment or StatefulSet must have:
- `replicaCount: >= 2` in `values.yaml`
- `PodDisruptionBudget` in templates
- `podAntiAffinity` in the Deployment spec

**Exception path:** Services that architecturally cannot scale (SonarQube CE, MailHog) must have `ha_exception: true` + `ha_exception_reason` in `platform/vendor/VENDORS.yaml`, AND `replicaCount: 1` with a comment in `values.yaml` pointing to the VENDORS.yaml entry.

**Gate:** `bash scripts/ha-gate.sh` runs PDB + podAntiAffinity + replicaCount checks across all charts.

---

## Resource Limits on Every Container (G6b)

Every container and initContainer must have `resources.requests` AND `resources.limits`. Use `helm template platform/charts/<name>/ | python3 scripts/check-limits.py` — grep is not sufficient (it misses individual containers).

---

## Domain Injection

- In templates: always `{{ .Values.global.domain }}` — never a hardcoded domain.
- In `values.yaml` defaults: `sovereign-autarky.dev` is the dogfood domain — correct and expected.
- ArgoCD apps inject domain via `spec.source.helm.parameters`, not `valueFiles`.

---

## Secret Handling

- **GitOps secrets:** Sealed Secrets (encrypted YAML committed to repo).
- **Runtime secrets:** OpenBao (Apache 2.0 Vault fork). Referenced via Helm values, never committed in plaintext.
- Never commit a secret. Ever. Stop and use the blocker protocol if you're about to.

---

## The Contract Layer (G7)

`contract/v1/` defines the platform configuration schema. `contract/validate.py` enforces:
- `externalEgressBlocked: true`
- `imageRegistry` present
- `storageClass` present

Before provisioning any cluster, `contract/validate.py <config>` must pass. The test fixtures are at `contract/v1/tests/valid.yaml` (must pass) and `contract/v1/tests/invalid-egress-not-blocked.yaml` (must fail with exit 1).

---

## Storage

Rook/Ceph provides all storage (block, filesystem, object). StorageClass flows through `{{ .Values.global.storageClass }}` everywhere. Ceph is a *provider* — it creates StorageClasses and does not consume one itself.

---

## Network Policies

The `network-policies` chart enforces per-namespace egress baselines. Every deployed namespace must be in `platform/charts/network-policies/values.yaml`. CI validates this via the `network-policies-coverage` job. Missing a namespace here means workloads are unprotected.

---

## Service Mesh (Istio)

mTLS STRICT everywhere inside the cluster. OPA/Gatekeeper enforces admission policy. Falco for runtime detection. These three are the zero-trust enforcement stack — if any is missing from a namespace, that namespace is not zero-trust.

---

## Developer Experience Services (current state)

| Service | State |
|---|---|
| code-server | Chart exists; toolchain initContainer copies kubectl/helm/k9s; workspace PVC at `/home/coder`; autarky G6 passes |
| Backstage | Chart + ArgoCD app exist; autarky G6 passes; full Keycloak OIDC plugin config pending |
| SonarQube | Chart deployed; ha_exception:true; ArgoCD app exists |
| ReportPortal | Chart deployed; multi-component PDB; ArgoCD app exists |
| Sovereign PM | Node.js/Express + React; multi-stage Dockerfile; deployed at `pm.<domain>` |

---

## The Ceremony Loop (Ralph)

The delivery system lives in `scripts/ralph/`. Ceremonies are Markdown prompts that run in sequence: orient → constitution-review → epic-breakdown → backlog-groom → plan → preflight → smart → execute → smoke → proof → review → retro → sync → advance.

The sprint state lives in:
- `prd/manifest.json` — source of truth for active increment and sprint file path
- `prd/increment-N-<name>.json` — the active sprint's stories
- `prd/backlog.json` — all future work

The word `phase` is retired from code and data. Use `increment`. Encountering `phase` in new code is a bug.
