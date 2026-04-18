# Domain Map — Who to Ask About What

Sovereign spans multiple domains of knowledge. A bug that looks like "the chart is wrong" might actually be "the upstream CRD changed in this version." This map names each domain, its authoritative source, and where boundaries create confusion.

---

## Domain 1: Kubernetes / Helm

**Covers:** Chart structure, Helm template rendering, CRD schemas, kubectl commands, pod scheduling, namespace isolation, resource requests/limits, PDB behavior.

**Authoritative source:**
- Helm: https://helm.sh/docs/
- Kubernetes API: https://kubernetes.io/docs/reference/

**Where confusion enters:**
- Upstream chart values change across versions. When an AC asserts a specific field value (e.g., `PeerAuthentication.mode`), cross-check the pinned chart version's values.yaml — not the latest docs.
- `podAntiAffinity: requiredDuringScheduling` prevents scheduling on a single-node kind cluster. Charts use `preferredDuringScheduling` to remain kind-testable, but HA gate only checks *presence* of anti-affinity, not the scheduling mode.
- `helm template` and `helm install` produce different behavior when upstream dependencies aren't resolved. Run `helm dependency update` before both.

---

## Domain 2: ArgoCD / GitOps

**Covers:** App-of-Apps pattern, Application manifests, sync policies, health checks, `revisionHistoryLimit`, image updater.

**Authoritative source:**
- ArgoCD: https://argo-cd.readthedocs.io/

**Where confusion enters:**
- ArgoCD CRDs are not installed in `kind-sovereign-test`. YAML validation requires `yaml.safe_load`, not `kubectl apply --dry-run`.
- `spec.revisionHistoryLimit: 3` is a project-specific requirement, not an ArgoCD default. CI rejects manifests without it.
- ArgoCD shows "OutOfSync" when chart templates render differently than the live cluster state. This is not always a problem — it can be a timing issue after a sync.

---

## Domain 3: Istio / Service Mesh

**Covers:** mTLS configuration, PeerAuthentication, DestinationRules, VirtualServices, Envoy proxy behavior.

**Authoritative source:**
- Istio: https://istio.io/latest/docs/

**Where confusion enters:**
- `PeerAuthentication mode: STRICT` applies to the namespace where it's applied. A STRICT policy in `istio-system` sets the mesh default, but per-namespace overrides in individual service charts can silently downgrade to PERMISSIVE. G8 only catches the mesh-default level.
- `PERMISSIVE` mode looks like it's working during debugging but allows plaintext traffic. The project's zero-trust promise depends on STRICT mode; any debugging workaround that sets PERMISSIVE must be reverted.
- Istio sidecar injection requires namespace labels. Charts that deploy to non-injected namespaces bypass mTLS silently.

---

## Domain 4: Cloud Providers / Networking

**Covers:** VPS provisioning (Hetzner, DigitalOcean, AWS, Vultr, bare metal), DNS (Cloudflare), Cloudflare Tunnel, kube-vip floating VIP, firewall rules (UFW).

**Authoritative source:**
- Cloudflare: https://developers.cloudflare.com/
- Hetzner: https://docs.hetzner.com/
- kube-vip: https://kube-vip.io/

**Where confusion enters:**
- Cloudflare Tunnel requires `accountId`, `zoneId`, and `tunnelName` — three different identifiers. The bootstrap config needs all three; getting one wrong produces cryptic errors.
- kube-vip VIP must be an unused IP on the same subnet as the nodes. `bootstrap.sh` auto-derives `<node1-subnet>.100` if not specified; this can collide with an existing host.
- `bootstrap.sh --estimated-cost` shows estimates but prices change. The table in README is best-effort.
- AWS free tier (t2.micro/t3.micro, 1 GB RAM) cannot run k3s with embedded etcd. This is a common newcomer mistake.

---

## Domain 5: Security Stack

**Covers:** Sealed Secrets, OpenBao (Vault fork), Keycloak OIDC/SSO, OPA/Gatekeeper admission control, Falco runtime detection, Trivy vulnerability scanning, OWASP ZAP.

**Authoritative source:**
- OpenBao: https://openbao.org/ (Apache 2.0 fork of Vault)
- Keycloak: https://www.keycloak.org/documentation
- OPA/Gatekeeper: https://open-policy-agent.github.io/gatekeeper/

**Where confusion enters:**
- OpenBao, not Vault. The project uses OpenBao (Apache 2.0) specifically because HashiCorp Vault switched to BSL. Never add `vault` as a dependency — use `openbao`. This is a constitutional decision (T1 Sovereignty).
- Sealed Secrets are cluster-specific — a sealed secret from one cluster cannot be decrypted by another. This means secrets cannot be shared across clusters without re-sealing.
- Keycloak OIDC client configuration must match exactly across all services that use it. A misconfigured redirect URI will silently fail SSO login.
- OPA/Gatekeeper admission control runs as a webhook. If the webhook is down, pod admission may be blocked cluster-wide (depending on `failurePolicy`).

---

## Domain 6: Observability Stack

**Covers:** Prometheus, Grafana, Loki (log aggregation), Thanos (long-term Prometheus storage), Tempo (tracing), Alertmanager.

**Authoritative source:**
- Prometheus: https://prometheus.io/docs/
- Grafana: https://grafana.com/docs/
- Loki: https://grafana.com/docs/loki/
- Tempo: https://grafana.com/docs/tempo/

**Where confusion enters:**
- Loki uses Ceph object storage as its backend. If Ceph is degraded, Loki ingestion fails. Logs appear to be missing when they're actually not being written.
- Thanos compacts Prometheus data asynchronously. Queries spanning long time ranges hit Thanos, not Prometheus directly. Query latency is higher.
- Grafana authenticates via Keycloak OIDC. If Keycloak is down, Grafana is inaccessible — even for admins. The observability stack depends on the identity stack.

---

## Domain 7: Storage — Rook/Ceph

**Covers:** Block storage (`ceph-block`), filesystem storage (`ceph-filesystem`), object storage (`ceph-bucket`), OSD health, replication.

**Authoritative source:**
- Rook: https://rook.io/docs/
- Ceph: https://docs.ceph.com/

**Where confusion enters:**
- Ceph requires 3 OSD nodes minimum for replication factor 3. A single OSD failure puts the cluster in HEALTH_WARN but remains functional. Two OSD failures makes the cluster read-only.
- `ceph-block` (RBD) supports ReadWriteOnce. `ceph-filesystem` (CephFS) supports ReadWriteMany. Using the wrong storage class for a service that needs multi-pod access is a common mistake.
- PVC provisioning can be slow during initial cluster setup while OSDs are being initialized.

---

## Domain 8: License Policy

**Covers:** Which software is permitted (Apache 2.0, MIT, BSD), which is blocked (BSL), which needs review (AGPL).

**Authoritative source:** `docs/governance/license-policy.md`, `platform/vendor/VENDORS.yaml`.

**Where confusion enters:**
- HashiCorp Vault is BSL-licensed. The project uses OpenBao instead. Never suggest adding Vault.
- AGPL components require legal review before inclusion. The copyleft clause applies to network use.
- `VENDORS.yaml` is the authoritative license record. Any new vendored component must be added here with its license verified.

---

## Boundary Confusion Map

| Symptom | Could Be Domain A | Could Be Domain B | How to Tell |
|---|---|---|---|
| Pod not scheduling | Kubernetes anti-affinity | Ceph OSD not ready (no PVC bound) | `kubectl describe pod` — check Events |
| SSO login fails | Keycloak config | Istio blocking the callback | Check Keycloak logs, then Istio access logs |
| Grafana shows no data | Prometheus scrape not configured | Loki/Thanos query routing | Check Grafana data source config, then Prometheus targets |
| ArgoCD out of sync | Chart template changed | Upstream CRD version changed | `argocd app diff` — look at what changed |
| Gate G6 passes vacuously | Chart path changed (not `platform/charts/*/templates/`) | Empty templates dir | Check the grep path, check `ls platform/charts/*/templates/` |
| `ha-gate.sh` exits early | `grep` no-match under `pipefail` | `_globals/` chart has no `replicaCount` | Add `|| true`, check which chart caused exit |
