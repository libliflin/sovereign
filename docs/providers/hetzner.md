# Hetzner Cloud — Provider Guide

Hetzner is the recommended provider for Sovereign. Their European data centres offer
excellent price-to-performance, and the `hcloud` CLI makes automation simple.

## Estimated Cost

| Server Type | vCPU | RAM  | Monthly (EUR) |
|-------------|------|------|---------------|
| CX11 / CX12 | 2    | 2 GB | ~€3–4         |
| CX21 / CX22 | 2    | 4 GB | ~€5–6 ✓ recommended |
| CX31 / CX32 | 2    | 8 GB | ~€10–12       |
| CX41 / CX42 | 4    | 16 GB| ~€18–20       |

The CX22 (~€6/month) is the minimum recommended for running the full platform.

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

hetzner:
  apiToken: "your-hcloud-api-token"
  serverType: "cx22"        # CX22 = ~€6/mo
  location: "nbg1"          # nbg1 = Nuremberg (closest to most EU users)
  serverName: "sovereign-1"
  sshKeyName: "your-key-name"  # Name as shown in Hetzner console
```

### 4. Run bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:
1. Create a CX22 server running Ubuntu 22.04
2. Install K3s
3. Fetch and save kubeconfig to `~/.kube/sovereign-hetzner.yaml`
4. Print DNS setup instructions

### 5. Configure DNS

After bootstrap, add the following records in Cloudflare (or your DNS provider):

```
Type: A   Name: *.your-domain.com   Value: <server-ip>   Proxy: DNS only
Type: A   Name: your-domain.com     Value: <server-ip>   Proxy: DNS only
```

DNS propagation typically takes 1–5 minutes with Cloudflare.

### 6. Verify the cluster

```bash
export KUBECONFIG=~/.kube/sovereign-hetzner.yaml
kubectl get nodes
# NAME          STATUS   ROLES                  AGE   VERSION
# sovereign-1   Ready    control-plane,master   1m    v1.29.4+k3s1

./bootstrap/verify.sh
```

## Scaling Up

To upgrade to a larger server type:

```bash
hcloud server change-type sovereign-1 --server-type cx42 --keep-disk
```

Note: You can resize up but not down (to protect your data).

## Multiple Nodes

For a multi-node cluster, provision additional servers and join them as K3s agents:

```bash
# Get the join token from the server
K3S_TOKEN=$(ssh root@<server-ip> "cat /var/lib/rancher/k3s/server/node-token")

# On each agent node
curl -sfL https://get.k3s.io | K3S_URL=https://<server-ip>:6443 K3S_TOKEN=$K3S_TOKEN sh -
```

## Troubleshooting

**SSH connection refused:** Hetzner servers are ready ~30s after creation. Wait and retry.

**hcloud context not found:** Run `hcloud context create sovereign` and paste your API token.

**K3s not starting:** Check logs: `ssh root@<ip> "journalctl -u k3s -n 50"`
