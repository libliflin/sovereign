# Architecture — Key Decisions in Force

Architectural decisions visible in the code that the champion needs to understand before walking a stakeholder journey.

---

## App-of-Apps GitOps Pattern

Everything after bootstrap is an ArgoCD Application. The root app watches `platform/argocd-apps/`. Adding a service means:
1. Create `platform/charts/<service>/` — Helm chart.
2. Create `platform/argocd-apps/<tier>/<service>-app.yaml` — ArgoCD Application manifest.
3. ArgoCD auto-syncs. No `kubectl apply` after bootstrap.

All ArgoCD app manifests require `spec.revisionHistoryLimit: 3`. CI rejects anything else.

---

## Domain is a Variable

`{{ .Values.global.domain }}` flows through every chart. Never hardcode a domain name, registry URL, or storage class. The three global values that must thread through every chart:

```yaml
global:
  domain: "sovereign-autarky.dev"       # injected by parent
  storageClass: "ceph-block"            # injected by parent
  imageRegistry: "harbor.{{ .Values.global.domain }}/sovereign"
```

Ingress hostnames: `<service>.{{ .Values.global.domain }}` always.

---

## Autarky — No External Registries at Runtime

After bootstrap, the cluster never pulls from `docker.io`, `quay.io`, `ghcr.io`, `gcr.io`, or `registry.k8s.io`. Images flow through Harbor (`harbor.<domain>/sovereign/<name>`). Constitutional gate G6 enforces this in CI. Every chart template image reference must use `{{ .Values.global.imageRegistry }}/`.

The vendor pipeline that makes autarky possible:
1. `vendor/fetch.sh` — SHA-verified mirror of upstream source into internal Forgejo.
2. `vendor/build.sh` — builds distroless OCI image, pushes to Harbor.
3. `vendor/deploy.sh` — stages → smoke test → promote.
4. `vendor/rollback.sh` — reverts to last-known-good SHA.

Image tag format: `<upstream-version>-<source-sha>-p<patch-count>` (e.g. `v1.16.0-a3f8c2d-p3`). Never `:latest`. Never just `:<version>`.

---

## HA — Mandatory, Not Optional

Every chart with a Deployment or StatefulSet must have:
- `replicaCount: 2` minimum (default in `values.yaml`)
- `PodDisruptionBudget` in `templates/pdb.yaml` with `minAvailable: 1`
- `podAntiAffinity` in the Deployment spec
- `readinessProbe` and `livenessProbe` on every container
- `resources.requests` and `resources.limits` on every container

Constitutional gate G9 enforces this across all charts. `scripts/ha-gate.sh --chart <name>` checks a single chart locally.

**Single-instance exception:** Services that architecturally cannot scale (MailHog, Mailpit) require a `ha_exception: true` entry in `platform/vendor/VENDORS.yaml`. Without this, CI fails.

**kind vs. production:** `podAntiAffinity: requiredDuringScheduling` prevents pods from scheduling on a single-node kind cluster. Charts use `preferredDuringScheduling` for anti-affinity to remain testable on kind. The HA gate checks for the presence of anti-affinity, not the scheduling mode.

---

## Zero Trust — Istio STRICT mTLS

Istio enforces mutual TLS between all in-cluster services (`PeerAuthentication` with `mode: STRICT`). The Istio chart's `values.yaml` has a `peerAuthentication.mode` field. Constitutional gate G8 verifies the rendered helm template — not just the values — to catch both mode drift and `enabled: false` bypass.

Known gap: G8 only checks the default namespace policy in `istio-system`. Per-namespace overrides in individual service charts are not checked by any gate.

---

## Contract Validator

`contract/validate.py` is the machine-enforced sovereignty gate. It reads a cluster contract YAML and enforces:
- `autarky.externalEgressBlocked: true` is present and true.
- `imageRegistry` field points to an internal registry.
- `storageClass` field is set.

Constitutional gate G7 runs the test suite: `contract/v1/tests/valid.yaml` must pass; `contract/v1/tests/invalid-egress-not-blocked.yaml` must be rejected with exit 1.

---

## Bootstrap Sequence

Strict dependency order. Each phase must complete before the next:
- **Phase 0** — VPS/bare-metal provisioned, K3s installed (3-node HA, kube-vip floating VIP).
- **Phase 1** — Cluster foundations: Cilium, Crossplane, cert-manager, Sealed Secrets.
- **Phase 2** — Identity and secrets: OpenBao, Keycloak.
- **Phase 3** — Storage: Rook/Ceph (block, filesystem, object). Replication factor 3, encryption at rest required.
- **Phase 4** — GitOps engine: Forgejo (note: README says GitLab in some places — Forgejo is the current SCM), Harbor, ArgoCD.
- **Phase 5+** — Security (Istio, OPA/Gatekeeper, Trivy, Falco), Observability (Prometheus, Grafana, Loki, Thanos, Tempo), Developer Experience (Backstage, code-server).

`bootstrap.sh` refuses to proceed with fewer than 3 nodes or an even node count.

---

## Ceremony System (ralph)

The delivery loop is managed by `scripts/ralph/ceremonies.py`. Ceremonies in order:
`orient → constitution-review → epic-breakdown → backlog-groom → plan → preflight → smart → execute → smoke → proof → review → retro → sync → advance`

Constitutional gate G1 verifies `ceremonies.py` compiles and its imports resolve. A broken import in `scripts/ralph/lib/orient.py` or `gates.py` stalls the loop.

Sprint state lives in `prd/manifest.json` (source of truth) and `prd/increment-<N>-<name>.json` (per-sprint stories). The active sprint is `manifest.json`.`activeSprint`.

Story lifecycle:
- `passes: false, reviewed: false` → needs implementation.
- `passes: true, reviewed: false` → implemented, awaiting review ceremony.
- `passes: true, reviewed: true` → accepted (done).

The champion marks `passes: true`. Only the review ceremony marks `reviewed: true`.

---

## Namespace Layout

Every service lives in its own namespace. Nothing deploys to `default`. Every non-system namespace must appear in `platform/charts/network-policies/values.yaml` for egress baseline enforcement.

---

## Distroless Mandatory

All container images use distroless base images. No shell, no package manager in production. Exceptions require a `VENDORS.yaml` entry with a migration path.

---

## Front Door — Zero Open Ports

Default: Cloudflare Tunnel (outbound-only). UFW blocks all inbound. SSH goes through `cloudflare access ssh`. Port 22 is never open. Alternative front doors implemented via a 5-hook interface in `bootstrap/frontdoor/`.
