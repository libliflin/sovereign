# Cluster Contract

Sovereign is cluster-agnostic. You can bring a K3s cluster, a Talos cluster, a kubeadm cluster, or a CAPI-managed cluster. The platform installs on top of any conformant Kubernetes cluster. This document defines what the cluster must provide and what sovereign installs, manages, and replaces.

---

## Kubernetes Version Requirement

Kubernetes 1.28 or later. The cluster must pass the CNCF conformance test suite for its version.

Managed cloud Kubernetes (EKS, GKE, AKS, DOKS) is intentionally not listed as a supported target. Cloud-managed Kubernetes introduces managed service dependencies (cloud load balancers, cloud storage classes, cloud IAM) that undermine sovereignty. Sovereign is designed for self-hosted clusters where you control the full stack from the OS upward.

---

## Required Cluster Capabilities

| Capability | Requirement | Why |
|------------|-------------|-----|
| Kubernetes API | v1.28+, conformant | Core platform requirement |
| Container runtime | CRI-compliant (containerd preferred) | Standard interface; containerd is CNCF Graduated |
| NetworkPolicy support | Required | Cilium provides this; Calico is acceptable if already present |
| Default StorageClass | At least one available | Sovereign installs Rook/Ceph for production; local-path-provisioner for kind-based testing |
| Node OS | Linux (amd64 or arm64) | Required for Cilium eBPF and Falco kernel modules |
| Kernel | 5.10 or later | Required for Cilium eBPF dataplane and Falco kernel-level tracing |
| Node count | 3+ (odd number) for production; 1 acceptable for kind/dev | etcd and Ceph both require odd quorum numbers |

---

## What Sovereign Installs — and What It Doesn't Touch

### Sovereign manages (owns the lifecycle of):

- **CNI: Cilium** — Sovereign replaces whatever CNI was present. This is the one opinionated requirement. Cilium is required for the security model (see "Cilium as the Reference CNI" below).
- **Certificate management: cert-manager** — manages all TLS certificates in the cluster, including self-signed for bootstrap and ACME/Let's Encrypt for production.
- **Secret management: OpenBao** — manages all secrets, dynamic credentials, and PKI. Replaces any existing secret store.
- **GitOps engine: ArgoCD** — takes over as the source of truth for all platform resources after bootstrap. Once ArgoCD is running, all further changes flow through Git.
- **Storage: Rook/Ceph** — installs the Rook operator and provisions a CephCluster across worker nodes. For production: requires at least 3 nodes with raw (unformatted) block devices. For kind: uses local-path-provisioner instead.
- **Ingress / service mesh: Istio** — provides mTLS between all services, ingress gateway, and traffic management.
- **Observability: Prometheus, Grafana, Loki, Tempo** — full observability stack. Replaces any existing monitoring setup.

### Sovereign does NOT touch:

- **Cluster provisioning** — use K3s, kubeadm, Talos, or CAPI. Sovereign's bootstrap scripts provision clusters as a convenience, but the cluster itself is not a sovereign-managed resource.
- **Node OS management** — use Talos, Flatcar, Ubuntu LTS, or your preferred immutable OS. Sovereign does not manage OS-level configuration after bootstrap hardening runs.
- **Cloud load balancers** — sovereign uses MetalLB or Cilium's built-in load balancer for bare-metal. No AWS ALB, no GCP Cloud Load Balancer, no DigitalOcean load balancer.
- **Cloud-managed databases** — sovereign is fully self-hosted. No RDS, no Cloud SQL, no PlanetScale. All databases run inside the cluster managed by the Ceph storage layer.
- **DNS (beyond wildcard entry)** — sovereign requires a single wildcard DNS entry (`*.domain.com → cluster ingress IP`) that you configure once. Sovereign does not manage your DNS provider.

---

## Cilium as the Reference CNI

Cilium is CNCF Graduated. It is the only CNI that provides all of the following in a single project:

- **NetworkPolicy** enforcement (standard Kubernetes NetworkPolicy + extended CiliumNetworkPolicy)
- **Hubble** — real-time network observability, flow visibility, and service dependency mapping
- **WireGuard** — transparent node-to-node encryption without any application changes
- **kube-proxy replacement** — eBPF-native service routing with lower latency and no iptables
- **Native load balancing** — can replace MetalLB for bare-metal L2/L3 load balancing

Sovereign's security model is zero-trust: every namespace has a default-deny NetworkPolicy, and services explicitly declare which other services they accept traffic from. This model is designed around Cilium's feature set. Hubble provides the visibility needed to audit and debug these policies without disabling them.

Other CNIs can run sovereign, but with reduced capability:

| Feature | Cilium | Calico | Flannel |
|---------|--------|--------|---------|
| NetworkPolicy | Yes | Yes | No |
| Hubble observability | Yes | No | No |
| WireGuard encryption | Yes | Yes (v3.x) | No |
| kube-proxy replacement | Yes | No | No |
| Native LB | Yes | No | No |

If you bring a cluster with Calico or flannel, sovereign will install but: Hubble-dependent dashboards will be disabled, WireGuard node encryption will not be available via Cilium, and kube-proxy replacement will not be active. Cilium will still be installed as the CNI — it replaces the existing one during bootstrap. The existing CNI's DaemonSet will be removed.

If you need to keep a non-Cilium CNI for a specific reason, document it in your cluster's `config.yaml` with a `cni_override` field and a written justification. This is an audit-visible configuration change.

---

## Relationship to Adjacent Projects

### Talos Linux

Talos is an excellent OS choice for sovereign nodes. Talos provides an immutable, API-managed node operating system with no SSH access — all management is through the Talos API. Sovereign's bootstrap scripts provision K3s or kubeadm clusters on generic Linux. If you choose Talos instead, sovereign installs cleanly on top of a Talos-provisioned cluster. See `docs/providers/talos.md` (forthcoming) for the integration guide.

### Cluster API (CAPI)

CAPI is the CNCF standard for cluster lifecycle management — provisioning, scaling, and upgrading Kubernetes clusters across any infrastructure provider. Sovereign's bootstrap scripts are a simpler alternative intended for single-cluster deployments. For multi-cluster deployments, production fleet management, or teams that need a declarative cluster lifecycle, CAPI is the recommended path. Sovereign installs as the application platform on a CAPI-managed cluster without modification.

### Sidero / Omni

Sidero is Talos's cluster management layer. Omni is Sidero's SaaS control plane (self-hostable). If your organization uses Sidero or Omni to manage node provisioning and cluster lifecycle, sovereign installs as the application platform on top. The boundary is clear: Sidero owns the cluster, sovereign owns the platform.

### K3s

Sovereign's default for bootstrapped single-node or HA clusters. K3s is lightweight (single binary), Apache 2.0 licensed, and maintained by SUSE/Rancher. It is used in bootstrap scripts and kind-based testing for convenience. K3s is a bootstrap tool — it is not a sovereign platform dependency. You can replace K3s with kubeadm or Talos at any point without affecting any sovereign platform component.

---

## HA Minimum

For production clusters:
- **Control plane:** 3 nodes (odd number for etcd quorum). 5 nodes for large installations. Even numbers are not supported — etcd requires a majority quorum.
- **Worker nodes:** 3 or more. Ceph requires at least 3 nodes with raw block devices for replication factor 3. Fewer than 3 workers means Ceph cannot maintain data safety guarantees.
- **Single-node:** supported for development and testing only (kind). Sovereign will install on a single node but will not enforce PodDisruptionBudget minimums or Ceph replication — it's not a safe configuration for any data you care about.

`bootstrap.sh` enforces this: if `nodes.count` in `config.yaml` is even or less than 3, the script exits with a clear error message before provisioning anything. This check cannot be bypassed with a flag — it is a hard gate.

---

## Bring Your Cluster Checklist

Run through this before pointing sovereign's bootstrap at an existing cluster:

1. `kubectl version` — confirm server version is 1.28 or later.
2. `kubectl get nodes` — confirm all nodes are in `Ready` state.
3. Check CNI: `kubectl get pods -n kube-system | grep -E 'cilium|calico|flannel|weave'` — note which CNI is present. Sovereign will replace it with Cilium.
4. Check StorageClass: `kubectl get storageclass` — confirm at least one StorageClass exists. Note the default. Sovereign will add Ceph storage classes and update the default.
5. Check node count and kernel version: `kubectl get nodes -o wide` — confirm 3+ nodes and Linux kernel 5.10+.
6. Check for raw block devices (for Ceph): on each worker node, confirm at least one unformatted block device is available (`lsblk` on the node — look for unformatted disks).
7. Run `./bootstrap/verify.sh` — this script performs all of the above checks automatically and reports pass/fail for each prerequisite.
8. If all checks pass: run `./bootstrap/bootstrap.sh --existing-cluster --kubeconfig=<path-to-kubeconfig>`.
