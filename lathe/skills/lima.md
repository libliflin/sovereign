# Lima VM + k3s Cluster Management

## Overview

The local development cluster runs as 3 Lima VMs (real Linux, real kernel) with k3s
(same runtime as production). This gives us real eBPF, real block devices, real
network isolation — no container-based k8s workarounds.

**License:** Lima is Apache 2.0 (T1 compliant).

## VM Names and Networking

| VM | Role | DNS |
|----|------|-----|
| `sovereign-0` | k3s server (control plane) | `lima-sovereign-0.internal` |
| `sovereign-1` | k3s agent (worker) | `lima-sovereign-1.internal` |
| `sovereign-2` | k3s agent (worker) | `lima-sovereign-2.internal` |

All VMs use the `lima:user-v2` network for inter-node communication.

## Kubeconfig

```bash
export KUBECONFIG=$(limactl list sovereign-0 --format 'unix://{{.Dir}}/copied-from-guest/kubeconfig.yaml')
```

The loop.sh sets this automatically. All kubectl/helm commands use this kubeconfig.

## Creating the Cluster

### Step 1: Server node

```bash
limactl start --name sovereign-0 --network lima:user-v2 template:k3s
```

Wait for it to be ready:
```bash
limactl shell sovereign-0 kubectl get nodes
```

### Step 2: Get join credentials

```bash
SERVER_URL=$(printf "https://lima-%s.internal:6443" sovereign-0)
TOKEN=$(limactl shell sovereign-0 sudo cat /var/lib/rancher/k3s/server/node-token)
```

### Step 3: Agent nodes

```bash
limactl start --name sovereign-1 --network lima:user-v2 template:k3s \
  --set ".param.url=\"${SERVER_URL}\" | .param.token=\"${TOKEN}\""

limactl start --name sovereign-2 --network lima:user-v2 template:k3s \
  --set ".param.url=\"${SERVER_URL}\" | .param.token=\"${TOKEN}\""
```

### Step 4: Verify

```bash
limactl shell sovereign-0 kubectl get nodes
# Should show 3 nodes: sovereign-0 (control-plane), sovereign-1, sovereign-2
```

## Checking Cluster Health

```bash
# VM status
limactl list

# Nodes
kubectl get nodes

# All pods
kubectl get pods -A

# Shell into a VM
limactl shell sovereign-0 <command>
limactl shell sovereign-1 <command>
```

## Loading Images into the Cluster

k3s uses containerd. Import images directly — no kind load, no docker save dance:

```bash
# From the host: copy a tar into the VM and import
limactl copy image.tar sovereign-0:/tmp/image.tar
limactl shell sovereign-0 sudo k3s ctr images import /tmp/image.tar

# Repeat for each node (or let k3s pull from internal registry once Harbor is up)
```

For images already in a registry the nodes can reach (like Harbor running inside the
cluster), k3s pulls normally — no special loading needed.

## Stopping / Starting

```bash
# Stop all VMs (preserves state)
limactl stop sovereign-0 sovereign-1 sovereign-2

# Start again
limactl start sovereign-0
limactl start sovereign-1
limactl start sovereign-2

# Nuclear: delete and recreate
limactl delete sovereign-0 sovereign-1 sovereign-2 --force
# Then recreate from step 1
```

## What Works That Didn't Work on Kind

| Feature | Kind | Lima + k3s |
|---------|------|------------|
| **eBPF / Falco** | No (no kernel headers) | Yes (real kernel) |
| **Ceph / raw block devices** | No | Yes (virtual disks) |
| **Network policies** | Partial (breaks CoreDNS) | Full (real CNI) |
| **Image loading** | kind load (digest issues) | ctr import or registry pull |
| **DNS resolution** | Docker bridge DNS hacks | Real DNS, real /etc/hosts |
| **StorageClass** | Only local-path | Any (local-path, Ceph, etc.) |
| **Multi-node HA** | Fake (containers on one host) | Real VMs, real isolation |

## Troubleshooting

### VM won't start
```bash
limactl list  # check status
limactl stop sovereign-0 && limactl start sovereign-0  # restart
```

### k3s not ready inside VM
```bash
limactl shell sovereign-0 systemctl status k3s
limactl shell sovereign-0 journalctl -u k3s --tail=30
```

### Node not joining cluster
```bash
# Check agent logs
limactl shell sovereign-1 journalctl -u k3s-agent --tail=30
# Verify token and URL are correct
limactl shell sovereign-1 cat /etc/rancher/k3s/config.yaml
```

### Storage issues
k3s comes with local-path provisioner by default. For Ceph, Rook can use the VM's
virtual disk as an OSD — no raw block device workarounds needed.
