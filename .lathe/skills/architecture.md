# Architecture — Decisions in Force

Read `docs/state/architecture.md` for the full current architecture document (rewritten each sprint). This file captures the decisions most relevant to the champion's cycle-to-cycle work.

---

## What Sovereign Is

A fully self-hosted, zero-trust, HA Kubernetes platform deployable from a single `bootstrap.sh` invocation. The domain is a runtime variable. Every service is installed by ArgoCD from this repository. Nothing is clicked into existence.

Dogfood domain: `sovereign-autarky.dev`

---

## Core Invariants

These are non-negotiable. Any story that violates them is stopped.

| Invariant | Rule |
|---|---|
| **Autarky** | After bootstrap, the cluster never pulls from docker.io, quay.io, ghcr.io, gcr.io, or registry.k8s.io. All images come from internal Harbor. |
| **HA mandatory** | Minimum 3 nodes (odd), replicaCount ≥ 2, PodDisruptionBudget, podAntiAffinity on every chart. `bootstrap.sh` refuses < 3 nodes. |
| **Distroless mandatory** | All container images use distroless bases. Exceptions require a VENDORS.yaml deprecation entry with a migration path. |
| **Domain is a variable** | `{{ .Values.global.domain }}` everywhere in templates. Never hardcoded. |
| **Zero open ports** | Default front door is Cloudflare Tunnel. VPS firewall drops everything except Cloudflare's published IP ranges. SSH via `cloudflare access ssh`. |
| **No plain-text secrets** | Sealed Secrets for GitOps. OpenBao for runtime injection. Never committed. |

---

## Architecture Layers

```
ArgoCD (App-of-Apps)           ← manages everything after bootstrap
  └─ argocd-apps/<tier>/*.yaml ← one Application per service

Platform services              ← platform/charts/<service>/
Kind bootstrap charts          ← cluster/kind/charts/<service>/

Infrastructure                 ← Crossplane compositions (XRDs, not scripts)
Secrets                        ← Sealed Secrets (at-rest) + OpenBao (runtime)
Storage                        ← Rook/Ceph (block, file, object)
Networking                     ← Cilium CNI, kube-vip VIP, Istio mTLS STRICT
```

---

## Key Components

| Component | Role | Source |
|---|---|---|
| ArgoCD | GitOps engine, App-of-Apps | argocd-apps/ |
| Forgejo | SCM + CI (replacing GitHub) | platform/charts/forgejo/ |
| Harbor | Internal OCI registry (autarky) | platform/charts/harbor/ |
| OpenBao | Secrets management (Vault fork, Apache 2.0) | platform/charts/openbao/ |
| Keycloak | SSO / identity | platform/charts/keycloak/ |
| Istio | Service mesh, mTLS STRICT | platform/charts/istio/ |
| OPA/Gatekeeper | Policy enforcement | platform/charts/opa-gatekeeper/ |
| Falco | Runtime threat detection | platform/charts/falco/ |
| Prometheus + Grafana | Metrics + dashboards | platform/charts/prometheus-stack/ |
| Loki | Log aggregation | platform/charts/loki/ |
| Tempo | Distributed tracing | platform/charts/tempo/ |
| Thanos | Long-term metrics retention | platform/charts/thanos/ |
| Backstage | Service catalog + developer portal | platform/charts/backstage/ |
| Crossplane | Infrastructure compositions | platform/charts/crossplane/ |
| Rook/Ceph | Distributed storage | (via cluster bootstrap) |
| Cilium | CNI + NetworkPolicy enforcement | cluster/kind/charts/cilium/ |
| cert-manager | TLS certificate automation | cluster/kind/charts/cert-manager/ |
| Sealed Secrets | GitOps-safe secret encryption | platform/charts/sealed-secrets/ |

---

## Contract System

`contract/v1/` defines the platform configuration schema. `contract/validate.py` enforces:
- Required fields are present (runtime.domain, imageRegistry, storageClass, etc.)
- `autarky.externalEgressBlocked: true` — egress is blocked
- `autarky.imagesFromInternalRegistryOnly: true` — no external image pulls
- `network.networkPolicyEnforced: true` — NetworkPolicies active
- apiVersion matches `sovereign.dev/cluster/v1`

The contract is the machine-verifiable form of the autarky and zero-trust claims. When in doubt about whether a config is valid, run the validator.

---

## Sprint/Delivery Model

```
prd/manifest.json              ← source of truth: active sprint, increments
prd/increment-N-<name>.json   ← sprint stories
prd/backlog.json               ← all future stories
prd/constitution.json          ← themes + constitutional gates
```

Stories: `passes: false, reviewed: false` → needs implementation. `passes: true, reviewed: false` → awaiting review. `passes: true, reviewed: true` → accepted.

Ceremonies run in order: orient → constitution-review → epic-breakdown → backlog-groom → plan → preflight → smart → execute → smoke → proof → review → retro → sync → advance.

---

## Sovereignty Tiers

- **Tier 1** (CNI, storage, PKI, GitOps, service mesh, policy, observability): must be CNCF/ASF/LF governed
- **Tier 2** (Forgejo, Keycloak, Harbor, Backstage): must be Apache 2.0 / MIT / BSD

OpenBao replaces Vault — the reference precedent for replacing a component that changed license terms (BSL).

---

## Notes for the Champion

- **`docs/state/agent.md`** is the live briefing rewritten each sprint. Read it before any implementation work.
- **`docs/state/architecture.md`** is the current architecture document (also rewritten each sprint).
- **The root `charts/` directory is empty and retired.** Never create charts there.
- **`ha_exception: true` in VENDORS.yaml** marks architecturally single-instance components that are exempt from the podAntiAffinity and replicaCount checks. Use sparingly.
- **kube-vip** provides the floating API server VIP — no external load balancer required for HA.
