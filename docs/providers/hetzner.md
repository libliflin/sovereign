# Hetzner Cloud — Provider Guide

Hetzner is the **recommended provider** for Sovereign. European data centres offer
excellent price-to-performance, and the `hcloud` CLI makes automation simple.

Sovereign requires a **3-node HA cluster** minimum — single-node deployments are not supported.

## Estimated Cost (3-Node HA Cluster)

| Server Type | vCPU | RAM   | Per Node/Month | 3-Node Total |
|-------------|------|-------|----------------|--------------|
| CX22        | 2    | 4 GB  | ~€5–6          | **~€15–18/month** ✓ recommended minimum |
| CX32        | 2    | 8 GB  | ~€10–12        | **~€30–36/month** |
| CX42        | 4    | 16 GB | ~€18–20        | **~€54–60/month** |
| CX52        | 8    | 32 GB | ~€36–40        | **~€108–120/month** |

The **3x CX22** cluster (~€15–18/month) is the minimum for development.
The **3x CX32** cluster (~€30–36/month) is recommended for production workloads.

> Free tier: Hetzner has no free tier, but it's the most affordable production-ready
> provider for Sovereign at ~€15/month for a 3-node HA cluster.

## Prerequisites

- A Hetzner Cloud account: <https://console.hetzner.cloud/>
- `hcloud` CLI installed
- `yq` YAML parser installed
- An SSH key pair (`~/.ssh/id_ed25519` by default)

### Install hcloud CLI

```bash
# macOS
brew install hcloud

# Linux
wget -O hcloud.tar.gz https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz
tar -xzf hcloud.tar.gz
sudo mv hcloud /usr/local/bin/
```

### Install yq

```bash
# macOS
brew install yq

# Linux
sudo snap install yq
```

## Step-by-Step Setup

### 1. Create a Hetzner Cloud project

1. Log in to <https://console.hetzner.cloud/>
2. Click **+ New project** → name it `sovereign`
3. Go to **Security → SSH Keys** → click **Add SSH Key** → paste your `~/.ssh/id_ed25519.pub`
   - Note the **name** you give it — you'll need it in `config.yaml` as `sshKeyName`
4. Go to **Security → API Tokens** → click **Generate API Token** → select **Read & Write**
5. Copy the token (you will only see it once)

### 2. Configure hcloud CLI

```bash
hcloud context create sovereign
# Paste your API token when prompted
hcloud context use sovereign
```

### 3. Configure Sovereign

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
```

Edit `bootstrap/config.yaml`:

```yaml
domain: "your-domain.com"
provider: "hetzner"
sshKeyPath: "~/.ssh/id_ed25519"

nodes:
  count: 3           # minimum — must be odd and >= 3
  serverType: "cx22" # per-node server type

# Optional: specify the kube-vip VIP (auto-derived as <node1-ip-subnet>.100 if omitted)
# kubeVip:
#   vip: "10.0.0.100"   # must be an unused IP on the same subnet

hetzner:
  apiToken: "your-hcloud-api-token"
  location: "nbg1"          # nbg1 = Nuremberg, fsn1 = Falkenstein, hel1 = Helsinki
  serverName: "sovereign"   # nodes will be sovereign-1, sovereign-2, sovereign-3
  sshKeyName: "your-key-name"  # name of the SSH key in Hetzner console
```

### 4. Run bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:
1. Create `nodes.count` CX22 servers running Ubuntu 22.04 (sovereign-1, -2, -3)
2. Install kube-vip on each node for a floating API server VIP
3. Install K3s with `--cluster-init` + embedded etcd on node-1
4. Join nodes 2+ to the cluster via the kube-vip VIP
5. Wait for all nodes to be Ready
6. Fetch and save kubeconfig (pointing at kube-vip VIP) to `~/.kube/sovereign-hetzner.yaml`

### 5. Verify the cluster

```bash
export KUBECONFIG=~/.kube/sovereign-hetzner.yaml
kubectl get nodes
# NAME           STATUS   ROLES                       AGE   VERSION
# sovereign-1    Ready    control-plane,etcd,master   2m    v1.29.4+k3s1
# sovereign-2    Ready    control-plane,etcd,master   1m    v1.29.4+k3s1
# sovereign-3    Ready    control-plane,etcd,master   1m    v1.29.4+k3s1

./bootstrap/verify.sh --vip <kube-vip-address>
```

## Adding Nodes

To scale out the cluster (must maintain odd count):

1. Update `nodes.count: 5` in `config.yaml`
2. Re-run `./bootstrap/bootstrap.sh` — it's idempotent and will provision the new nodes
3. The new nodes auto-join via the kube-vip VIP

## Replacing a Failed Node

To replace `sovereign-2` with a fresh node without cluster downtime:

```bash
# 1. Cordon and drain the failed node
kubectl cordon sovereign-2
kubectl drain sovereign-2 --ignore-daemonsets --delete-emptydir-data

# 2. Remove from K3s cluster
kubectl delete node sovereign-2

# 3. Delete the failed Hetzner server
hcloud server delete sovereign-2

# 4. Re-run bootstrap — it will create sovereign-2 again and join it
./bootstrap/bootstrap.sh
```

etcd continues operating with 2/3 healthy nodes (quorum maintained) during the replacement.

## Scaling Server Type

To upgrade a node to a larger server type:

```bash
hcloud server change-type sovereign-1 --server-type cx42 --keep-disk
```

Note: Resize requires a brief restart (~1 minute downtime per node).
Rolling resize: do one node at a time to maintain etcd quorum.

## Troubleshooting

**SSH connection refused:** Hetzner servers are SSH-ready ~30s after creation.
The bootstrap script waits up to 3 minutes with automatic retries.

**hcloud context not found:** Run `hcloud context create sovereign` and paste your API token.

**K3s not starting:** Check logs: `ssh root@<ip> "journalctl -u k3s -n 50"`

**kube-vip pod not found:** Verify `/var/lib/rancher/k3s/server/manifests/kube-vip.yaml`
exists on node-1. Check: `ssh root@<node1-ip> "cat /var/lib/rancher/k3s/server/manifests/kube-vip.yaml"`

**Node fails to join (etcd quorum):** If 2 of 3 nodes are healthy, etcd has quorum.
Check the joining node's K3s logs: `ssh root@<node-ip> "journalctl -u k3s -n 50"`
