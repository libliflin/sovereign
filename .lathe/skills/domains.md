# Domain Boundaries

Sovereign spans multiple domains of knowledge with distinct authorities. Problems attributed to the wrong domain produce fixes in the wrong layer. This is the "who to ask about what" guide.

---

## Domain Map

### 1. Helm / Kubernetes Resource Modeling

**What it covers:** Chart structure, template rendering, values schema, resource types (Deployment, StatefulSet, PDB, NetworkPolicy, Service, Ingress, ConfigMap, ServiceAccount). What gets rendered and why.

**Authoritative source:** Helm docs (helm.sh), Kubernetes API reference (kubernetes.io/docs/reference).

**Where confusion lives:** Upstream wrapper charts (cilium, cert-manager, bitnami subcharts) have their own values schema that doesn't map 1:1 to the wrapper's values. A key that looks reasonable (`initResources`) may not propagate to all initContainers in the upstream chart. Always read the upstream chart's `values.yaml` before assuming a key exists.

**Boundary with CI/gates domain:** Helm template output is what CI validates — not values.yaml syntax. A values.yaml that looks correct but doesn't render the expected resource fails the gate, not the values file.

---

### 2. Kubernetes Cluster Operations

**What it covers:** Node scheduling, pod lifecycle, drain behavior, etcd quorum, rolling updates, PodDisruptionBudgets (enforcement), StorageClass provisioning, CNI behavior.

**Authoritative source:** Kubernetes docs, kind docs for local clusters, k3s docs for VPS clusters.

**Where confusion lives:**
- PDB enforcement: the `kubectl drain` command respects PDBs, but `kubectl delete pod` does not. Test PDB enforcement via drain, not delete.
- kind vs. production: kind's `local-path` StorageClass is a hostPath provisioner — it does not behave like Rook/Ceph. Storage-related behaviors that work in kind may fail in production.
- CRDs: custom resources (ArgoCD Application, Crossplane XR, Chaos Mesh objects) require the operator's CRDs to be installed before `kubectl apply --dry-run=client` works. In kind-sovereign-test (bare cluster), these are not installed. Use YAML-only validation.

---

### 3. GitOps / ArgoCD

**What it covers:** How ArgoCD watches the repo, App-of-Apps structure, sync policies, diff detection, `revisionHistoryLimit`, domain injection via `spec.source.helm.parameters`.

**Authoritative source:** ArgoCD docs (argo-cd.readthedocs.io), the Application CRD spec.

**Where confusion lives:**
- ArgoCD reads `spec.source.helm.parameters` to inject values at sync time. This is different from `values.yaml` or `valueFiles`. Using `valueFiles` for domain injection is wrong.
- ArgoCD Applications without `revisionHistoryLimit: 3` accumulate history entries indefinitely — this is a resource leak and a CI gate failure.
- ArgoCD manages state declaratively from the repo. If you manually apply a change to the cluster without committing it, ArgoCD will revert it on the next sync.

**Boundary with Helm domain:** Helm renders the chart; ArgoCD applies the rendered output to the cluster. Errors from ArgoCD sync are usually either "can't reach the chart" or "the rendered output has a resource ArgoCD can't apply" — check which layer failed.

---

### 4. Security Policies (Zero Trust Stack)

**What it covers:** Istio mTLS (pod-to-pod encryption and auth), OPA/Gatekeeper (admission control — what can be created), Falco (runtime detection — what is running), NetworkPolicy (Cilium enforcement), Sealed Secrets (at-rest secret encryption), OpenBao (runtime secret injection).

**Authoritative source:** Each component's own docs. The policy intent is `docs/governance/sovereignty.md` and `docs/governance/cluster-contract.md`.

**Where confusion lives:**
- Istio mTLS STRICT mode blocks pod-to-pod traffic that isn't mTLS — services without Istio sidecar injection will fail to communicate with sidecar-injected services.
- NetworkPolicy and Istio policy are independent enforcement layers. A NetworkPolicy allow doesn't override Istio's mTLS requirement.
- OPA/Gatekeeper admission control runs at create/update time. A policy violation doesn't prevent existing resources from running — only new creates/updates.
- The `network-policies` chart manages egress baselines per namespace. Missing a namespace here means its pods can make unrestricted external connections — a T1 sovereignty violation.

---

### 5. Observability Stack

**What it covers:** Prometheus metrics scraping and alerting, Grafana dashboards and datasources, Loki log aggregation, Tempo distributed tracing, Thanos long-term metrics.

**Authoritative source:** Each component's Helm chart values schema + upstream docs.

**Where confusion lives:**
- Grafana datasource registration: each observability chart must include a Grafana datasource ConfigMap in its templates. Without it, Grafana doesn't auto-discover the data source. CI gate: `helm template | grep -i datasource` must exit 0.
- Loki and Tempo run in distributed mode — they have multiple components (ingester, distributor, querier). The PDB count must be >= number of deployed components, not just >= 1.
- Thanos runs as a sidecar to Prometheus — it requires access to Ceph object storage. This dependency means Thanos won't work until Rook/Ceph is healthy.

---

### 6. Sovereignty / License Policy

**What it covers:** Which dependencies are allowed (Apache 2.0/MIT/BSD), which are blocked (BSL, SSPL), which need review (AGPL), and how to handle a vendor that changes terms.

**Authoritative source:** `docs/governance/license-policy.md`, `docs/governance/sovereignty.md`, `platform/vendor/VENDORS.yaml`.

**Where confusion lives:**
- Vault → OpenBao is the reference precedent for sovereignty-driven replacement. The decision to replace isn't about functionality — it's about who controls the project's future.
- Tier 1 components (CNI, storage, PKI, GitOps, service mesh, policy, observability) must be CNCF/ASF/LF governed. A single vendor controlling a Tier 1 component's roadmap is grounds for replacement.
- BSL-licensed software in VENDORS.yaml must be marked `deprecated: true`. Not just noted — deprecated with a migration path.

---

### 7. Developer Experience Services

**What it covers:** code-server (browser VS Code), Backstage (service catalog), Forgejo (SCM + CI), Keycloak (SSO), Sovereign PM (project management UI).

**Authoritative source:** Each service's upstream docs + this project's Helm values.

**Where confusion lives:**
- SSO wiring: each service requires explicit Keycloak OIDC configuration. Keycloak DNS resolution may not work in kind before Keycloak is fully provisioned — use `KEYCLOAK_URL` as an explicit Helm value, not a hardcoded service URL.
- code-server toolchain: the initContainer copies kubectl/helm/k9s to `/home/coder/workspace/bin` via an emptyDir volume. If the initContainer fails silently, the tools aren't in PATH. Verify the initContainer logs.
- Backstage: the service catalog is only populated if plugins and entity sources are configured. A fresh Backstage deployment shows an empty catalog — it's not broken, it's unconfigured.

---

## Cross-Domain Confusion Points

| Symptom | Wrong attribution | Right attribution |
|---|---|---|
| "helm gate failed" with no detail | Chart logic | CI message quality (contributor domain, not chart domain) |
| Pod can't reach another pod | NetworkPolicy | Could be Istio mTLS, NetworkPolicy, or DNS — check each layer |
| ArgoCD sync fails for a CRD resource | ArgoCD config | Usually: CRDs not installed, or wrong namespace, or missing RBAC |
| `check-limits.py` fails on a subchart | Your chart | Upstream subchart defaults — override via `<subchart>.resources` in values.yaml |
| Grafana shows "datasource not found" | Grafana config | Missing datasource ConfigMap in the chart's templates directory |
| kind test passes, production fails | Kind environment | StorageClass, image registry, or external service dependency differs |
