# Domain Map — Who to Ask About What

Sovereign spans multiple domains of knowledge, each with its own authority. A bug that looks like a Helm problem might be a Kubernetes API version issue. A "zero-trust" gap that looks like an Istio config problem might be a NetworkPolicy gap. This map prevents the champion and builder from going to the wrong authority.

---

## Kubernetes / k3s

**Covers:** Cluster orchestration, etcd quorum, RBAC, CRDs, API server, kubelet, resource scheduling, PodDisruptionBudget mechanics, NetworkPolicy enforcement.

**Authoritative sources:** kubernetes.io/docs, k3s.io/docs

**Where confusion happens:**
- `kubectl apply --dry-run=client` doesn't validate CRDs — it only checks syntax. For ArgoCD Application manifests, use `yq e '.'` instead.
- etcd quorum: 3 nodes tolerate 1 failure. 2 nodes lose quorum on any failure. The bootstrap.sh refusal to proceed with < 3 nodes enforces this.
- k3s embeds etcd by default in HA mode. No external etcd required.
- kube-vip provides the floating API server VIP — not a cloud load balancer.

---

## Helm

**Covers:** Chart templating, values inheritance, dependency management (Chart.lock), chart packaging, OCI push.

**Authoritative sources:** helm.sh/docs

**Where confusion happens:**
- `helm dependency update` is required before `helm lint` on charts with dependencies — otherwise lint fails on missing chart deps.
- Values from parent charts override child chart values. When a service chart wraps an upstream subchart, check the upstream's values.yaml for its HA keys first.
- `helm template` renders locally without a cluster — required for the HA gate checks.
- `helm install --wait` blocks until pods are ready; useful for kind smoke tests.

---

## ArgoCD

**Covers:** GitOps sync, Application CRDs, App-of-Apps pattern, sync waves, health checks, resource hooks.

**Authoritative sources:** argo-cd.readthedocs.io

**Where confusion happens:**
- `spec.revisionHistoryLimit: 3` is required on every Application manifest. CI enforces this.
- Domain-aware charts receive `global.domain` via `spec.source.helm.parameters`, not via valueFiles — the latter requires a file to exist in the chart.
- ArgoCD Application CRDs are not installed locally; validate manifests with `yq e '.'` not `kubectl apply --dry-run`.
- App-of-Apps: the root app watches `argocd-apps/` and creates all child Applications. Tier structure is a convention, not enforced by ArgoCD itself.

---

## Istio

**Covers:** Service mesh, mTLS (STRICT/PERMISSIVE), traffic management, telemetry (metrics, traces, access logs), PeerAuthentication, DestinationRule, VirtualService.

**Authoritative sources:** istio.io/docs

**Where confusion happens:**
- `PeerAuthentication` with `mtls.mode: STRICT` enforces mTLS at the pod level — but only for pods in the mesh. Pods without sidecars bypass it.
- `PERMISSIVE` mode accepts both plaintext and mTLS. Sovereign requires `STRICT` everywhere. Check that the PeerAuthentication resource is namespace-scoped (or mesh-wide), not just deployment-scoped.
- Istio telemetry feeds Prometheus, Grafana, Jaeger/Tempo — it's both a security and observability component.
- Kiali visualizes the mesh. If mTLS shows gaps in Kiali, trace back to which namespace has PERMISSIVE mode.

---

## Rook/Ceph

**Covers:** Distributed block storage (RBD), filesystem storage (CephFS), object storage (S3-compatible), OSD quorum.

**Authoritative sources:** rook.io/docs, docs.ceph.io

**Where confusion happens:**
- Ceph quorum requires 3 OSDs (monitors). Fewer than 3 nodes means no Ceph — this is why bootstrap.sh refuses < 3 nodes.
- Block storage (`ceph-block`) for single-writer volumes. Filesystem storage (`ceph-filesystem`) for ReadWriteMany. Object storage (`rook-ceph-object-store`) for S3-compatible workloads.
- StorageClass references must use `{{ .Values.global.storageClass }}` in templates — never hardcode `ceph-block`.
- Ceph recovery is slow after a node loss. PodDisruptionBudgets are critical to prevent multi-node loss from voluntary disruptions.

---

## Crossplane

**Covers:** Infrastructure compositions, XRDs (CompositeResourceDefinitions), Claims, Providers (Kubernetes, Helm, cloud providers).

**Authoritative sources:** docs.crossplane.io

**Where confusion happens:**
- Crossplane creates Kubernetes resources from XRD Claims — it's for infrastructure (namespaces, RBAC, cloud resources), not application deployment (that's ArgoCD).
- Providers are Crossplane-specific controllers. The Kubernetes and Helm providers are used for in-cluster compositions. Cloud providers (Hetzner, DigitalOcean) are used for VPS management.
- XRD schema changes can break existing Claims. Plan schema evolution carefully.

---

## OpenBao (Runtime Secrets)

**Covers:** Dynamic secrets, PKI, secret injection (Agent Sidecar / Vault Secrets Operator), leases, auth backends (Kubernetes JWT, AppRole).

**Authoritative sources:** openbao.org/docs (OpenBao is the Apache 2.0 fork of HashiCorp Vault; Vault docs apply where OpenBao hasn't diverged)

**Where confusion happens:**
- OpenBao replaced Vault due to Vault's BSL license change. API is compatible; the binary name changed.
- Sealed Secrets is for *GitOps-safe at-rest encryption* (static secrets in repos). OpenBao is for *runtime secret injection* (dynamic secrets, short-lived credentials).
- If a pod needs a database password, it gets it from OpenBao at runtime. If ArgoCD needs a registry credential, it gets it from Sealed Secrets at sync time.

---

## OPA / Gatekeeper

**Covers:** Admission control policies, Rego language, ConstraintTemplates, Constraints, audit mode.

**Authoritative sources:** openpolicyagent.org/docs, open-policy-agent.github.io/gatekeeper

**Where confusion happens:**
- Gatekeeper enforces at admission (prevent). OPA's audit mode runs against existing resources (detect after-the-fact).
- ConstraintTemplates define the policy logic (Rego). Constraints instantiate a template with specific parameters.
- A policy violation blocks `kubectl apply` — contributor experience is affected when policies are too strict or have false positives.
- Sovereign uses Gatekeeper to enforce autarky (no external registries), HA (PDB required), and naming conventions.

---

## Observability Stack (Prometheus / Grafana / Loki / Tempo / Thanos)

**Covers:** Metrics (Prometheus), dashboards (Grafana), logs (Loki), traces (Tempo), long-term storage (Thanos).

**Authoritative sources:** prometheus.io/docs, grafana.com/docs, grafana.com/docs/loki, grafana.com/docs/tempo, thanos.io/docs

**Where confusion happens:**
- **Prometheus scrapes metrics** from targets. Grafana *reads* from Prometheus. Thanos provides long-term retention and cross-cluster queries.
- **Loki is not Elasticsearch.** It indexes log *labels* (pod name, namespace, container) not log content. LogQL filters by label first, then regex the content.
- **Tempo requires trace context propagation** in the application. Istio can inject trace headers automatically; applications must not strip them.
- The Prometheus Operator manages Prometheus instances via ServiceMonitor and PodMonitor CRDs — not raw prometheus.yml config files.
- Thanos requires object storage (MinIO or S3-compatible) for block persistence. Without it, Thanos runs but doesn't retain historical data.

---

## Cloudflare (Front Door)

**Covers:** Tunnel (zero-open-ports ingress), Zero Trust Access (identity-aware proxy), DNS management, IP range lists.

**Authoritative sources:** developers.cloudflare.com/cloudflare-one

**Where confusion happens:**
- Cloudflare Tunnel is *outbound-only* from the cluster — the VPS firewall can drop all inbound traffic except Cloudflare's published IP ranges.
- Zero Trust Access enforces identity *before* traffic reaches the cluster. mTLS (Istio) enforces identity *inside* the cluster. Both are required for end-to-end zero trust.
- Sovereign's front door is pluggable — the 5-hook interface in `bootstrap/frontdoor/` allows swapping Cloudflare for a different solution. The Cloudflare dependency is on the front-door component, not the platform core.
- SSH access goes through `cloudflare access ssh` — port 22 is never open.

---

## Cloud Providers (Hetzner / DigitalOcean / Vultr / Bare Metal)

**Covers:** VPS provisioning, block volumes, firewalls, networking, API credentials.

**Authoritative sources:** Provider-specific docs. See `docs/providers/` for provider-specific notes.

**Where confusion happens:**
- Provider choice affects node specs, networking, and cost — but not the Kubernetes stack. The platform is provider-agnostic above the VPS layer.
- Hetzner Volumes are block storage from the provider, not Ceph. They're used for bootstrap storage before Ceph is running.
- Firewall rules that block Cloudflare's IP ranges will break the front door entirely. Always configure the firewall from `.env` credentials, not manually.

---

## Shell / Bash

**Covers:** Bootstrap scripts, ceremony scripts, deployment scripts.

**Authoritative sources:** shellcheck.net (static analysis), bash manual

**Where confusion happens:**
- All scripts are validated with `shellcheck -S error`. Warnings treated as errors.
- Vendor scripts (`platform/vendor/*.sh`) must implement `--dry-run` and `--backup` flags. CI checks for these.
- `bootstrap.sh --dry-run` previews intended actions without executing them. This is tested in CI (`bootstrap-validate` job).
- macOS uses `gtimeout` (from coreutils) instead of `timeout`. `snapshot.sh` handles this portably.

---

## Boundary Confusion Guide

| Symptom | Likely domain | Not likely |
|---|---|---|
| Pod can't reach another pod | NetworkPolicy (Cilium) or Istio PeerAuthentication | DNS, application code |
| ArgoCD shows "OutOfSync" but manifest looks right | Helm template drift, chart value propagation | ArgoCD itself |
| `helm lint` passes but CI fails | CI checks a superset of what lint checks (PDB, replicaCount, limits) | Helm |
| Secret visible in git history | Sealed Secrets wasn't used — plaintext was committed | OpenBao |
| Ceph degraded after node reboot | OSD count < 3 or PDB prevented pod restart | k3s, ArgoCD |
| Validator rejects a valid config | parse_yaml_flat in validate.py doesn't handle all YAML | The config itself |
| mTLS not enforced despite PeerAuthentication | Pod not in Istio mesh (missing sidecar injection label) | Istio policy config |
