# DigitalOcean — Provider Guide

DigitalOcean Droplets offer simple pricing and a developer-friendly CLI (`doctl`).
Sovereign requires a **3-node HA cluster** minimum — single-node deployments are not supported.

## Estimated Cost (3-Node HA Cluster)

| Droplet Size    | vCPU | RAM  | Per Node/Month | 3-Node Total |
|-----------------|------|------|----------------|--------------|
| s-2vcpu-4gb     | 2    | 4 GB | ~$24           | **~$72/month** ✓ recommended minimum |
| s-4vcpu-8gb     | 4    | 8 GB | ~$48           | **~$144/month** |
| s-8vcpu-16gb    | 8    | 16 GB| ~$96           | **~$288/month** |

The **3x s-2vcpu-4gb** cluster (~$72/month) is the minimum for production workloads.

> **Free credits:** New DigitalOcean accounts often receive $200 in free credits valid
> for 60 days — enough to run a 3-node cluster for free while evaluating the platform.
> The s-1vcpu-1gb ($6/node) is NOT supported — too small for K3s + workloads.

## Prerequisites

- A DigitalOcean account: <https://www.digitalocean.com/>
- `doctl` CLI installed and authenticated
- `yq` YAML parser installed
- An SSH key pair (`~/.ssh/id_ed25519` by default)

### Install doctl CLI

```bash
# macOS
brew install doctl

# Linux
wget https://github.com/digitalocean/doctl/releases/latest/download/doctl-$(curl -s https://api.github.com/repos/digitalocean/doctl/releases/latest | grep tag_name | cut -d '"' -f4 | tr -d 'v')-linux-amd64.tar.gz
tar xf ~/doctl-*.tar.gz
sudo mv ~/doctl /usr/local/bin
```

### Install yq

```bash
# macOS
brew install yq

# Linux
sudo snap install yq
```

## Step-by-Step Setup

### 1. Create a DigitalOcean account and authenticate doctl

1. Go to <https://www.digitalocean.com/> → **Sign Up**
2. In the DigitalOcean control panel, go to **API → Tokens → Generate New Token**
3. Name it `sovereign`, select **Read** and **Write** scopes, click **Generate Token**
4. Copy the token

```bash
doctl auth init
# Enter your access token: <paste-token>

# Verify
doctl account get
```

### 2. Configure Sovereign

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
```

Edit `bootstrap/config.yaml`:

```yaml
domain: "your-domain.com"
provider: "digitalocean"
sshKeyPath: "~/.ssh/id_ed25519"

nodes:
  count: 3                 # minimum — must be odd and >= 3
  serverType: "s-2vcpu-4gb"  # per-node droplet size

# Optional: specify the kube-vip VIP (auto-derived as <node1-private-subnet>.100 if omitted)
# kubeVip:
#   vip: "10.108.0.100"   # must be an unused IP on the VPC private subnet

digitalocean:
  region: "nyc3"           # choose closest to your users
  dropletName: "sovereign" # droplets will be sovereign-1, sovereign-2, sovereign-3
```

**Available regions:**
- `nyc3` — New York 3
- `sfo3` — San Francisco 3
- `ams3` — Amsterdam 3
- `sgp1` — Singapore 1
- `lon1` — London 1
- `fra1` — Frankfurt 1
- `tor1` — Toronto 1
- `blr1` — Bangalore 1
- `syd1` — Sydney 1

### 3. Run bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:
1. Upload your SSH public key to DigitalOcean (idempotent by fingerprint)
2. Create a private VPC for inter-node communication
3. Create `nodes.count` Droplets running Ubuntu 22.04 (sovereign-1, -2, -3) with private networking
4. Install kube-vip on each node for a floating API server VIP (on the private VPC subnet)
5. Install K3s with `--cluster-init` + embedded etcd on node-1
6. Join nodes 2+ to the cluster via the kube-vip VIP
7. Wait for all nodes to be Ready
8. Fetch and save kubeconfig (pointing at kube-vip VIP) to `~/.kube/sovereign-do.yaml`

### 4. Verify the cluster

```bash
export KUBECONFIG=~/.kube/sovereign-do.yaml
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

To replace `sovereign-2` without cluster downtime:

```bash
# 1. Cordon and drain the failed node
kubectl cordon sovereign-2
kubectl drain sovereign-2 --ignore-daemonsets --delete-emptydir-data

# 2. Remove from K3s cluster
kubectl delete node sovereign-2

# 3. Delete the failed Droplet
doctl compute droplet delete sovereign-2 --force

# 4. Re-run bootstrap — it will create sovereign-2 and join it
./bootstrap/bootstrap.sh
```

etcd continues operating with 2/3 healthy nodes (quorum maintained) during the replacement.

## Cleanup

```bash
# Delete all Droplets
for i in 1 2 3; do
  doctl compute droplet delete "sovereign-${i}" --force
done

# Delete the VPC (after all Droplets are deleted)
doctl vpcs delete <vpc-id>
```

## Troubleshooting

**doctl: command not found:** Install doctl using the instructions above.

**Authentication failed:** Run `doctl auth init` again with a fresh API token.

**SSH key import fails:** Ensure `~/.ssh/id_ed25519.pub` exists.
Generate a key pair with: `ssh-keygen -t ed25519 -C "your-email@example.com"`

**Node fails to join:** Check the kube-vip VIP is reachable on the private subnet.
Verify: `ssh root@<node-ip> "curl -sk https://<vip>:6443/healthz"`

**Droplet not found after creation:** The `--wait` flag in `doctl` handles provisioning delays.
If a Droplet still isn't available after 5 minutes, check the DigitalOcean control panel.

**kube-vip pod not found:** Verify `/var/lib/rancher/k3s/server/manifests/kube-vip.yaml`
exists on node-1: `ssh root@<node1-ip> "ls /var/lib/rancher/k3s/server/manifests/"`
