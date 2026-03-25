# Vultr — Provider Guide

Vultr is a global cloud provider with data centres across 6 continents.
Sovereign requires a **3-node HA cluster** minimum — single-node deployments
are not supported.

## Estimated Cost (3-Node HA Cluster)

| Instance | vCPU | RAM | Per Node/Month | 3-Node Total |
|---|---|---|---|---|
| vc2-1c-2gb | 1 | 2 GB | ~$6 | **~$18/month** (minimum — tight) |
| vc2-2c-4gb | 2 | 4 GB | ~$24 | **~$72/month** ✓ recommended minimum |
| vc2-4c-8gb | 4 | 8 GB | ~$48 | **~$144/month** |
| vc2-8c-16gb | 8 | 16 GB | ~$96 | **~$288/month** |

The **3x vc2-2c-4gb** cluster (~$72/month) is recommended for production.
The 1-CPU instance is not supported — K3s with embedded etcd requires >= 2 vCPU.

> **Free tier:** Vultr has no free tier, but new accounts often receive $100–$250
> in trial credits. Check the Vultr website for current promotions.

## Prerequisites

- A Vultr account: <https://www.vultr.com/>
- `vultr-cli` installed
- `yq` YAML parser installed
- An SSH key pair (`~/.ssh/id_ed25519` by default)

### Install vultr-cli

```bash
# macOS
brew install vultr-cli

# Linux (download latest release)
VULTR_CLI_VER=$(curl -s https://api.github.com/repos/vultr/vultr-cli/releases/latest \
  | grep tag_name | cut -d '"' -f4)
wget -O vultr-cli.tar.gz \
  "https://github.com/vultr/vultr-cli/releases/download/${VULTR_CLI_VER}/vultr-cli_${VULTR_CLI_VER}_linux_64-bit.tar.gz"
tar -xzf vultr-cli.tar.gz && sudo mv vultr-cli /usr/local/bin/
```

### Install yq

```bash
# macOS
brew install yq

# Linux
sudo snap install yq
```

## Step-by-Step Setup

### 1. Create a Vultr account and get an API key

1. Go to <https://www.vultr.com/> → **Create Account**
2. In the Vultr dashboard → **Account** → **API** → click **Enable API**
3. Copy the API key

### 2. Configure vultr-cli

```bash
export VULTR_API_KEY="your-api-key"
vultr-cli account info   # verify the key works
```

Add to your shell profile to persist:

```bash
echo 'export VULTR_API_KEY="your-api-key"' >> ~/.zshrc
```

### 3. Add your SSH key to Vultr

```bash
vultr-cli ssh-key create \
  --name sovereign \
  --key "$(cat ~/.ssh/id_ed25519.pub)"
```

Note the SSH key ID from the output — you'll need it in `config.yaml`.

### 4. Configure Sovereign

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
```

Edit `bootstrap/config.yaml`:

```yaml
domain: "your-domain.com"
provider: "vultr"
sshKeyPath: "~/.ssh/id_ed25519"

nodes:
  count: 3          # minimum — must be odd and >= 3
  serverType: "vc2-2c-4gb"   # recommended for production

vultr:
  apiKey: "your-vultr-api-key"
  region: "ewr"         # ewr = New Jersey, lax = Los Angeles, ams = Amsterdam
  instanceName: "sovereign"   # nodes will be sovereign-1, sovereign-2, sovereign-3
  sshKeyId: "your-ssh-key-id"
```

### 5. Run bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:

1. Create `nodes.count` instances running Ubuntu 22.04 (sovereign-1, -2, -3)
2. Install kube-vip on each node for a floating API server VIP
3. Install K3s with `--cluster-init` + embedded etcd on node-1
4. Join nodes 2+ to the cluster via the kube-vip VIP
5. Wait for all nodes to be Ready
6. Fetch and save kubeconfig (pointing at kube-vip VIP) to `~/.kube/sovereign-vultr.yaml`

### 6. Verify the cluster

```bash
export KUBECONFIG=~/.kube/sovereign-vultr.yaml
kubectl get nodes
# NAME           STATUS   ROLES                       AGE   VERSION
# sovereign-1    Ready    control-plane,etcd,master   2m    v1.29.4+k3s1
# sovereign-2    Ready    control-plane,etcd,master   1m    v1.29.4+k3s1
# sovereign-3    Ready    control-plane,etcd,master   1m    v1.29.4+k3s1

./bootstrap/verify.sh --vip <kube-vip-address>
```

## Available Regions

| Region Code | Location |
|---|---|
| `ewr` | New Jersey, USA |
| `lax` | Los Angeles, USA |
| `ord` | Chicago, USA |
| `dfw` | Dallas, USA |
| `sea` | Seattle, USA |
| `mia` | Miami, USA |
| `ams` | Amsterdam, Netherlands |
| `fra` | Frankfurt, Germany |
| `lhr` | London, UK |
| `cdg` | Paris, France |
| `nrt` | Tokyo, Japan |
| `sgp` | Singapore |
| `syd` | Sydney, Australia |

## Adding Nodes

To scale out the cluster (must maintain odd count):

1. Update `nodes.count: 5` in `config.yaml`
2. Re-run `./bootstrap/bootstrap.sh` — it's idempotent and will provision the new nodes
3. The new nodes auto-join via the kube-vip VIP

## Replacing a Failed Node

```bash
# 1. Cordon and drain the failed node
kubectl cordon sovereign-2
kubectl drain sovereign-2 --ignore-daemonsets --delete-emptydir-data

# 2. Remove from K3s cluster
kubectl delete node sovereign-2

# 3. Delete the failed Vultr instance
vultr-cli instance delete <instance-id>

# 4. Re-run bootstrap to provision a replacement
./bootstrap/bootstrap.sh
```

etcd continues operating with 2/3 healthy nodes (quorum maintained) during
the replacement.

## Troubleshooting

**API key rejected:** Verify `VULTR_API_KEY` is set and the key has read+write
permissions. Run `vultr-cli account info` to confirm.

**SSH connection refused:** Vultr instances typically boot in 60–90 seconds.
The bootstrap script retries SSH every 10 seconds for up to 5 minutes.

**K3s not starting:** Check logs:
`ssh root@<ip> "journalctl -u k3s -n 50"`

**Node fails to join:** Verify the kube-vip VIP is reachable on the private
network. Check: `ssh root@<node-ip> "curl -sk https://<vip>:6443/healthz"`
