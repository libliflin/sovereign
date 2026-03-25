# Bare Metal / Existing Cluster — Provider Guide

Use this guide if you already have servers (physical or virtual) running
Ubuntu 22.04+ and want to install Sovereign on them, or if you want to onboard
an existing Kubernetes cluster.

Sovereign requires a **3-node HA cluster** minimum — single-node deployments
are not supported.

## Estimated Cost

| Setup | Cost |
|---|---|
| Owned hardware (3 nodes) | **$0/month** after hardware purchase |
| Rented dedicated servers | Varies by provider — typically $30–$150/month per node |

Bare metal is the best long-term value. A 3-node cluster on second-hand
servers (e.g. used Intel NUCs, mini-PCs, or decommissioned workstations)
can run the full Sovereign stack for under $500 of one-time hardware cost.

## Hardware Requirements (per node, minimum)

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 2 vCPU / cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Disk | 40 GB SSD | 100 GB NVMe SSD |
| Network | 100 Mbps | 1 Gbps |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

All 3 nodes must be on the same subnet (or have L2 connectivity) for kube-vip
to provide the floating API server VIP.

## Prerequisites

- 3+ servers running Ubuntu 22.04+ (odd number, minimum 3)
- SSH access to all nodes (key-based, no password)
- All nodes reachable from the machine running `bootstrap.sh`
- `yq` YAML parser installed on your local machine
- An unused IP on the same subnet for the kube-vip VIP

### Install yq

```bash
# macOS
brew install yq

# Linux
sudo snap install yq
```

## Option A — Bootstrap from scratch (servers have Ubuntu, no K8s yet)

### 1. Prepare your servers

Ensure you can SSH into each node:

```bash
ssh root@<node1-ip> "echo node1 ok"
ssh root@<node2-ip> "echo node2 ok"
ssh root@<node3-ip> "echo node3 ok"
```

### 2. Configure Sovereign

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
```

Edit `bootstrap/config.yaml`:

```yaml
domain: "your-domain.com"
provider: "bare-metal"
sshKeyPath: "~/.ssh/id_ed25519"

nodes:
  count: 3          # must be odd and >= 3
  ips:              # list all node IPs explicitly
    - "192.168.1.10"
    - "192.168.1.11"
    - "192.168.1.12"

kubeVip:
  vip: "192.168.1.100"  # unused IP on the same subnet
```

### 3. Run bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:

1. Harden all nodes (unattended-upgrades, fail2ban, auditd, CIS sysctl)
2. Install kube-vip on each node for a floating API server VIP
3. Install K3s with `--cluster-init` + embedded etcd on node-1
4. Join nodes 2+ to the cluster via the kube-vip VIP
5. Wait for all nodes to be Ready
6. Write kubeconfig (pointing at kube-vip VIP) to `~/.kube/sovereign-bare-metal.yaml`

### 4. Verify the cluster

```bash
export KUBECONFIG=~/.kube/sovereign-bare-metal.yaml
kubectl get nodes
# NAME           STATUS   ROLES                       AGE   VERSION
# sovereign-1    Ready    control-plane,etcd,master   2m    v1.29.4+k3s1
# sovereign-2    Ready    control-plane,etcd,master   1m    v1.29.4+k3s1
# sovereign-3    Ready    control-plane,etcd,master   1m    v1.29.4+k3s1

./bootstrap/verify.sh --vip 192.168.1.100
```

## Option B — Onboard an existing Kubernetes cluster

If you already have a working K8s cluster (K3s, kubeadm, or any CNCF-conformant
distribution), you can install the Sovereign application layer on top.

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
# Set provider: existing-cluster
# Set kubeConfigPath: /path/to/your/kubeconfig

./bootstrap/existing-cluster.sh
```

This skips OS provisioning and K3s installation. It installs:

- Cilium CNI (replaces your existing CNI — see note below)
- Crossplane, cert-manager, Sealed Secrets
- Then hands off to ArgoCD for the rest

> **CNI replacement note:** Sovereign uses Cilium as the reference CNI.
> If your existing cluster uses a different CNI, the installer will prompt
> before replacing it. Back up any existing network policies first.

## Adding Nodes

To add nodes to the cluster (must maintain odd count):

1. Provision the new node with Ubuntu 22.04
2. Add its IP to `nodes.ips` in `config.yaml`
3. Update `nodes.count` to the new total
4. Re-run `./bootstrap/bootstrap.sh` — it's idempotent and joins the new node

## Replacing a Failed Node

```bash
# 1. Cordon and drain the failed node
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 2. Remove from the K3s cluster
kubectl delete node <node-name>

# 3. On the failed server: wipe K3s state
ssh root@<node-ip> "/usr/local/bin/k3s-uninstall.sh"

# 4. Reinstall on the same IP — re-run bootstrap (idempotent)
./bootstrap/bootstrap.sh
```

etcd continues operating with 2/3 healthy nodes (quorum maintained) during
the replacement.

## DNS Setup

For bare metal, DNS is not configured automatically. After bootstrap, set up
a wildcard DNS record pointing to the kube-vip VIP:

```text
*.your-domain.com  →  <kube-vip VIP>  (A record)
```

If using Cloudflare:

1. Log in to the Cloudflare dashboard
2. Go to DNS → Add record
3. Type: **A**, Name: `*`, IPv4 address: `<kube-vip VIP>`, Proxy: off (DNS only)

## Troubleshooting

**SSH connection refused:** Verify the SSH key is authorised on the target node:
`ssh -i ~/.ssh/id_ed25519 root@<node-ip>`

**kube-vip VIP unreachable:** The VIP must be on the same subnet as the nodes.
Verify: `ping <vip>` from one of the nodes. If it fails, check `nodes.ips` and
`kubeVip.vip` are on the same /24 subnet.

**K3s fails to form etcd cluster:** All 3 nodes must be able to reach each other
on port 2380 (etcd peer). Check firewall rules: `ufw allow from <node-subnet>`

**Existing CNI conflict:** If you see pod networking issues after onboarding an
existing cluster, check that the old CNI daemonsets are fully removed before
Cilium comes up.
