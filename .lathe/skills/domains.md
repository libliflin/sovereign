# Domain Boundaries

The Sovereign platform spans multiple authority domains. A bug that looks like "a Helm chart problem" might actually be "a Kubernetes API version issue" or "an upstream chart behavior we didn't account for." This map tells you who to ask about what — and where boundary confusion tends to generate wrong fixes.

---

## Domain 1: Kubernetes / Helm

**What it covers:** Pod scheduling, workload types (Deployment, StatefulSet, DaemonSet), Services, Ingress, NetworkPolicy, PodDisruptionBudget, resource limits, RBAC, namespaces, Helm chart templating and lifecycle (install/upgrade/rollback), Helm dependency resolution.

**Authoritative sources:**
- Kubernetes API docs (`kubernetes.io/docs/reference/`)
- Helm docs (`helm.sh/docs/`)
- `kubectl explain <resource>` for field-level documentation
- The rendered output of `helm template` — this is the ground truth of what will be applied

**Where boundary confusion happens:**
- `podAntiAffinity` in `values.yaml` vs. in the rendered template: setting `affinity:` in values doesn't guarantee the chart propagates it. Always verify with `helm template | grep podAntiAffinity`.
- Upstream charts (Bitnami, etc.) have their own `affinity`, `resources`, `replicaCount` keys that may differ from our conventions. Check the upstream values.yaml before assuming our naming works.
- `helm lint` passes with warnings that are actually fatal in older K8s versions. `helm lint --strict` is stricter.
- API version deprecations: a chart templating `extensions/v1beta1/Ingress` will pass lint but fail apply on K8s 1.22+.

---

## Domain 2: Container Images / Distroless / OCI

**What it covers:** OCI image format, base image selection (distroless vs. standard), multi-stage builds, image tagging conventions, Harbor registry (push, pull, tag), image vulnerability scanning (Trivy).

**Authoritative sources:**
- Google Distroless project (`github.com/GoogleContainerTools/distroless`)
- OCI Image Spec (`opencontainers.org`)
- Harbor docs for registry operations
- `platform/vendor/DISTROLESS.md` for project-specific distroless guidance

**Where boundary confusion happens:**
- "The service doesn't start" is often "the distroless image has no shell, so the entrypoint is wrong." Debug by running with `-it --entrypoint sh` on the debug variant, not by switching to a non-distroless image.
- Trivy findings on a distroless image may reference the base image CVEs, not the application code CVEs. The remediation paths are different.
- Harbor's internal registry URL includes the domain: `harbor.{{ .Values.global.domain }}/sovereign`. Hardcoding `harbor.sovereign-autarky.dev` in a chart template violates the domain-as-variable principle.

---

## Domain 3: Kubernetes Networking / Cilium / Istio

**What it covers:** CNI (Cilium handles pod networking and NetworkPolicy enforcement), service mesh (Istio handles mTLS, traffic management, observability), Ingress and front door design.

**Authoritative sources:**
- Cilium docs (`docs.cilium.io`) — especially NetworkPolicy syntax
- Istio docs (`istio.io/docs/`) — PeerAuthentication (mTLS mode), AuthorizationPolicy, ServiceEntry
- The cluster contract (`contract/v1/`) — `network.networkPolicyEnforced` and `autarky.externalEgressBlocked` are constants enforced here

**Where boundary confusion happens:**
- Cilium and Istio both implement NetworkPolicy — but Istio's `AuthorizationPolicy` operates at L7 (HTTP) while Cilium's `NetworkPolicy` operates at L3/L4. A deny-all NetworkPolicy blocks TCP; an Istio `DENY` AuthorizationPolicy blocks HTTP paths. They're complementary, not competing.
- Istio STRICT mTLS mode means every pod-to-pod connection must have a client certificate. A pod without an Istio sidecar injected can't communicate with a mesh service. If a new service can't reach another, check sidecar injection before checking NetworkPolicy.
- `externalEgressBlocked: true` in the cluster contract means no pod can call `docker.io`. The Cilium NetworkPolicy enforces this. If a pod needs external access (e.g., a vendor fetch job), it needs an explicit egress allow rule — this is an intentional exception, not a bug to work around.

---

## Domain 4: Security / PKI / Secrets

**What it covers:** Certificate management (cert-manager, cluster CA), secrets management (OpenBao, Sealed Secrets), SSO/OIDC (Keycloak), OPA/Gatekeeper policy, Falco runtime rules.

**Authoritative sources:**
- cert-manager docs (`cert-manager.io/docs/`)
- OpenBao docs (Apache 2.0 fork of Vault — `openbao.org/docs/`) — use OpenBao, not Vault, per T1 Sovereignty
- Sealed Secrets docs for GitOps-safe encrypted secrets
- Keycloak docs for OIDC/SSO configuration
- OPA/Rego language reference for Gatekeeper policies

**Where boundary confusion happens:**
- OpenBao is a drop-in API-compatible Vault fork, but configuration syntax and operator behavior may diverge from Vault in newer versions. If Vault docs say one thing and OpenBao behaves differently, OpenBao wins — it's the authoritative implementation in this project.
- Sealed Secrets encrypt secrets for a specific cluster's controller key. A secret sealed for production can't be unsealed in a kind development cluster. If `kubectl get secret` shows the sealed secret controller erroring, it's a key mismatch, not a Helm chart bug.
- cert-manager ClusterIssuers vs. Issuers: ClusterIssuers work across namespaces; Issuers are namespace-scoped. The `pki.clusterIssuer` field in the cluster contract must refer to a ClusterIssuer.

---

## Domain 5: GitOps / ArgoCD

**What it covers:** ArgoCD Application manifests, App-of-Apps pattern, sync policies, resource health checks, ArgoCD Image Updater.

**Authoritative sources:**
- ArgoCD docs (`argo-cd.readthedocs.io`)
- The `argocd-apps/` directory for this project's Application manifests

**Where boundary confusion happens:**
- "The chart is correct but ArgoCD shows OutOfSync": This is usually either (a) the Application manifest's `targetRevision` is pinned to a branch and there's a drift, or (b) ArgoCD's resource tracking excludes something. Not a chart bug.
- `revisionHistoryLimit: 3` is required on all Application manifests. Missing it fails the `argocd-validate` CI job. This is separate from Kubernetes Deployment revision history.
- ArgoCD owns the deployed state after bootstrap. Manual `kubectl apply` of a chart that ArgoCD manages will be reverted by ArgoCD on its next sync. Use `kubectl patch` or go through Git for intentional changes.

---

## Domain 6: Observability Stack

**What it covers:** Prometheus (metrics collection, alerting), Grafana (dashboards), Loki (logs), Tempo (distributed traces), Thanos (long-term metrics retention).

**Authoritative sources:**
- Prometheus docs and PromQL reference
- Grafana docs for dashboard provisioning (JSON model, datasource configuration)
- Loki LogQL reference
- Tempo TraceQL reference

**Where boundary confusion happens:**
- Loki Simple Scalable mode vs. single binary: the project uses Simple Scalable for HA. This means multiple deployments (ingester, distributor, querier) and multiple PDBs. A single PDB for the whole Loki installation fails the HA gate.
- Thanos is for long-term retention only — it doesn't replace Prometheus, it extends it. Prometheus handles recent metrics; Thanos handles historical queries and deduplication across replicas.
- Grafana dashboard provisioning via ConfigMap is the GitOps path. Dashboards created in the UI are lost on redeploy. If a dashboard needs to survive upgrades, it must be in a `platform/charts/prometheus-stack/` ConfigMap.

---

## Domain 7: Delivery Machine (ralph ceremonies / sprint mechanics)

**What it covers:** The ralph ceremony system, sprint files, constitutional gates, story lifecycle, the `prd/` JSON schema.

**Authoritative sources:**
- `scripts/ralph/ceremonies.py` and `scripts/ralph/lib/` — the implementation
- `prd/constitution.json` — the constitutional gate definitions
- `CLAUDE.md` (root) — the team norms and story lifecycle documentation

**Where boundary confusion happens:**
- G2 checks staleness (file modification date), not correctness. `docs/state/agent.md` can be trivially touched to pass G2 without actually updating the briefing.
- The `prd/manifest.json` → `activeSprint` pointer and the sprint file's `status: "active"` must agree. When they diverge (a sprint file is deleted but manifest still points to it), ceremonies fail silently.
- "Ceremony output" vs. "CI output": ceremonies produce stdout. If a ceremony exits 0 but produces nothing, it ran successfully (from gate perspective) but gave no useful information. This is a delivery machine issue, not a constitutional violation — G1 only checks compile.

---

## Domain 8: Provider Infrastructure (VPS / bare metal)

**What it covers:** Hetzner API, DigitalOcean API, DNS management (Cloudflare), Cloudflare Tunnel configuration, VPS provisioning scripts in `bootstrap/`.

**Authoritative sources:**
- Provider-specific docs: `docs/providers/hetzner.md`, `docs/providers/digitalocean.md`, etc.
- `.env.example` for the full list of required credentials and where to get them
- Cloudflare Tunnel docs for the zero-open-ports front door design

**Where boundary confusion happens:**
- The kind path (`cluster/kind/`) and the VPS path (`bootstrap/`) are independent. Changes to kind scripts don't affect VPS scripts. They share `platform/charts/` but not bootstrap logic.
- "The provider CLI fails" is usually a credential issue (`source .env` not run, or token expired), not a bug in the bootstrap script.
- Node count must be odd and >= 3 for both etcd quorum and Ceph quorum. `bootstrap.sh` enforces this. The kind path uses a single-node cluster for development (explicitly not HA — the kind path is for testing charts, not for testing HA).

---

## Cross-Domain Confusion Map

| Symptom | Wrong domain to look | Right domain to look |
|---|---|---|
| "Pod can't reach service X" | Chart values | Cilium NetworkPolicy / Istio AuthorizationPolicy |
| "ArgoCD shows OutOfSync after helm upgrade" | Helm chart | ArgoCD Application manifest / sync policy |
| "Sealed secret controller error" | Chart template | Cert/key mismatch — wrong cluster's controller key |
| "Image pull fails on kind" | Chart templates | kind doesn't have Harbor; uses direct pull from upstream (autarky exception for kind) |
| "Service starts but can't connect to Vault/OpenBao" | OpenBao config | Istio sidecar injection / mTLS mode |
| "Helm lint passes but apply fails" | Chart values | K8s API version — check `kubectl api-versions` |
| "Grafana dashboard missing after upgrade" | Prometheus config | Dashboard must be provisioned via ConfigMap, not created in UI |
| "Ceremony runs but produces nothing" | Constitutional gates | Delivery machine — ceremony's own output logic |
