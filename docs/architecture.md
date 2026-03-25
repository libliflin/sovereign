# Sovereign Platform — Architecture

This document explains how the platform is assembled: the bootstrap sequence,
the App-of-Apps GitOps pattern, the namespace layout, the security model, and
where every service lives after deployment.

---

## Bootstrap Sequence

Sovereign bootstraps in strict dependency order. Each phase must complete before
the next begins.

### Phase 0 — Cluster Provisioning (scripts)

Your VPS or bare-metal nodes are provisioned via `bootstrap/providers/<provider>.sh`.

- Minimum 3 nodes (odd number). `bootstrap.sh` refuses to proceed otherwise.
- All nodes running Ubuntu 22.04+
- kube-vip installed on all control plane nodes (floating API server VIP)
- K3s installed with `--cluster-init` + embedded etcd on node 1;
  nodes 2+ join via `--server https://<VIP>:6443`
- Kubeconfig written pointing at the VIP, not a single node IP

### Phase 1 — Cluster Foundations (bootstrap installs directly)

| Component | Purpose |
|---|---|
| Cilium | CNI + network policy + Hubble observability |
| Crossplane | Infrastructure composition (XRDs, Compositions) |
| cert-manager | TLS certificates (self-signed → Let's Encrypt) |
| Sealed Secrets | GitOps-safe secret encryption |

### Phase 2 — Identity and Secrets (Crossplane compositions)

| Component | Purpose |
|---|---|
| OpenBao | Secrets management (Apache 2.0 fork of Vault) |
| Keycloak | SSO / OIDC provider for all user-facing services |

### Phase 3 — Storage (enables all stateful services)

| Component | Purpose |
|---|---|
| Rook/Ceph | Block, filesystem, and object storage |
| StorageClasses | `ceph-block`, `ceph-filesystem`, `ceph-bucket` |

Ceph encryption at rest is required. Replication factor: 3.

### Phase 4 — GitOps Engine (self-managing from here)

| Component | Purpose |
|---|---|
| GitLab | SCM + CI + vendor mirrors |
| Harbor | Internal OCI image registry |
| ArgoCD | App-of-Apps engine — manages all subsequent services |
| GitLab CI Runners | Executes CI pipelines for vendor builds |

After Phase 4, ArgoCD takes over managing everything. No more manual `kubectl apply`.

### Phase 5 — Service Mesh and Security

| Component | Purpose |
|---|---|
| Istio | mTLS between all services |
| OPA/Gatekeeper | Admission control policies |
| Trivy Operator | Continuous vulnerability scanning |
| OWASP ZAP | Web application security scanning |
| Falco | Runtime security (syscall monitoring) |

### Phase 6 — Observability

| Component | Purpose |
|---|---|
| Prometheus + Alertmanager | Metrics collection and alerting |
| Grafana | Dashboards (authenticated via Keycloak OIDC) |
| Loki | Log aggregation (Ceph object storage backend) |
| Thanos | Long-term Prometheus storage (Ceph object backend) |
| Tempo | Distributed tracing (Ceph object backend) |

### Phase 7 — Developer Experience

| Component | Purpose |
|---|---|
| Backstage | Developer portal + service catalog |
| code-server | VS Code in browser (primary Claude Code agent interface) |
| SonarQube | Code quality history |
| ReportPortal | Test result history |

### Phase 8 — Testing Infrastructure

| Component | Purpose |
|---|---|
| Selenium Grid | Browser testing |
| k6 Operator | Load testing |
| MailHog | Email testing (SMTP trap) |
| Chaos Mesh | Resilience testing |

---

## App-of-Apps Pattern

The root ArgoCD application watches `argocd-apps/`. Every subdirectory contains
Application manifests for a tier of the stack. ArgoCD auto-syncs all of them.

```text
argocd-apps/
├── root-app.yaml        ← manages everything below
├── platform/            ← foundations: cilium, cert-manager, crossplane
├── security/            ← istio, opa-gatekeeper, trivy, falco
├── observability/       ← prometheus, grafana, loki, thanos, tempo
├── devex/               ← backstage, code-server, sonarqube
└── testing/             ← selenium-grid, k6, mailhog, chaos-mesh
```

Adding a new service:

1. Create `charts/<service>/` with `Chart.yaml`, `values.yaml`, `templates/`
2. Create `argocd-apps/<tier>/<service>-app.yaml`
3. ArgoCD picks it up automatically on next sync

---

## Namespace Layout

Each service has its own namespace. No service deploys into `default`.

| Namespace | Service |
|---|---|
| `cilium` | Cilium CNI |
| `cert-manager` | cert-manager |
| `crossplane-system` | Crossplane |
| `sealed-secrets` | Sealed Secrets controller |
| `openbao` | OpenBao secrets |
| `keycloak` | Keycloak SSO |
| `rook-ceph` | Rook/Ceph operator + cluster |
| `gitlab` | GitLab |
| `harbor` | Harbor registry |
| `argocd` | ArgoCD |
| `istio-system` | Istio control plane |
| `gatekeeper-system` | OPA/Gatekeeper |
| `monitoring` | Prometheus + Grafana + Alertmanager |
| `loki` | Loki log aggregation |
| `tempo` | Tempo tracing |
| `backstage` | Backstage developer portal |
| `code-server` | VS Code browser IDE |

---

## Security Model

**Zero open ports.** All inbound traffic (HTTP, HTTPS) reaches the cluster
through an outbound-only Cloudflare Tunnel. UFW blocks all inbound connections
by default. Port 22 is never exposed — SSH goes through `cloudflare access ssh`.

**mTLS everywhere.** Istio enforces mutual TLS between all in-cluster services.
No plaintext east-west traffic.

**SSO for everything.** Every user-facing service authenticates via Keycloak
OIDC. No per-service user databases.

**Secrets never in Git.** Sealed Secrets encrypts secrets for GitOps storage.
OpenBao provides runtime secret injection via Vault Agent sidecar or CSI driver.

**Distroless containers.** No shell, no package manager in production images.
Attack surface is the application binary only.

---

## Service URLs

All services are served under `*.<domain>`. The domain is set in
`bootstrap/config.yaml` and flows through `{{ .Values.global.domain }}` in
every Helm chart.

| Service | URL | Notes |
|---|---|---|
| ArgoCD | `https://argocd.<domain>` | GitOps dashboard |
| GitLab | `https://gitlab.<domain>` | SCM + CI + vendor mirrors |
| Harbor | `https://harbor.<domain>` | Internal image registry |
| Grafana | `https://grafana.<domain>` | Metrics + logs + traces |
| Keycloak | `https://auth.<domain>` | SSO for all services |
| OpenBao | `https://vault.<domain>` | Secrets (Apache 2.0 Vault fork) |
| Backstage | `https://backstage.<domain>` | Developer portal |
| VS Code | `https://code.<domain>` | Browser IDE for agents |
| Prometheus | `https://prometheus.<domain>` | Metrics (internal) |
| Alertmanager | `https://alerts.<domain>` | Alert routing |
| Sovereign PM | `https://pm.<domain>` | AI-native project management |

---

## Autarky Build System

After bootstrap, the cluster never pulls from external registries.

```text
vendor/fetch.sh     → mirrors upstream source into internal GitLab at pinned SHA
vendor/build.sh     → builds distroless OCI image, pushes to harbor.<domain>/sovereign/<name>
vendor/deploy.sh    → stages → smoke test → promote to production ArgoCD app
vendor/rollback.sh  → reverts to last-known-good image SHA (< 2 minutes)
vendor/backup.sh    → mirrors repos + images to secondary storage (runs as CronJob)
```

Image tag format: `<upstream-version>-<source-sha>-p<patch-count>`
Example: `v1.16.0-a3f8c2d-p3`

Every image change goes through staging before production. Rollback is always
available. See `vendor/VENDORS.yaml` for the full manifest of vendored services.
