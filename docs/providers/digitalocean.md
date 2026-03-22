# DigitalOcean — Provider Guide

DigitalOcean Droplets offer simple pricing and a developer-friendly CLI (`doctl`).
The cheapest Droplet runs from $4–6/month, making it one of the most affordable
options for Sovereign.

## Estimated Cost

| Droplet Size    | vCPU | RAM  | Monthly (USD)          |
|-----------------|------|------|------------------------|
| s-1vcpu-1gb     | 1    | 1 GB | ~$6                    |
| s-1vcpu-2gb     | 1    | 2 GB | ~$12 ✓ default         |
| s-2vcpu-2gb     | 2    | 2 GB | ~$18                   |
| s-2vcpu-4gb     | 2    | 4 GB | ~$24 ✓ recommended     |
| s-4vcpu-8gb     | 4    | 8 GB | ~$48                   |

The `s-2vcpu-4gb` (~$24/month) is recommended for a comfortable platform experience.

**Note:** New DigitalOcean accounts often receive $200 in free credits valid for 60 days.

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
cd ~
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
```

Verify authentication:

```bash
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

digitalocean:
  size: "s-2vcpu-4gb"   # ~$24/mo — recommended
  region: "nyc3"        # choose closest to you
  dropletName: "sovereign-1"
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
1. Upload your SSH public key to DigitalOcean (if not already present)
2. Create a Droplet running Ubuntu 22.04 LTS
3. Wait for the Droplet to be running and SSH-accessible
4. Install K3s
5. Fetch and save kubeconfig to `~/.kube/sovereign-do.yaml`

### 4. Configure DNS

After bootstrap, add the following records in Cloudflare (or your DNS provider):

```
Type: A   Name: *.your-domain.com   Value: <droplet-ip>   Proxy: DNS only
Type: A   Name: your-domain.com     Value: <droplet-ip>   Proxy: DNS only
```

DigitalOcean Droplets retain their public IP unless deleted, so no Elastic IP equivalent
is needed.

Optionally, you can use DigitalOcean's built-in DNS:

```bash
doctl compute domain create your-domain.com --ip-address <droplet-ip>
doctl compute domain records create your-domain.com \
  --record-type A --record-name "*" --record-data <droplet-ip> --record-ttl 300
```

### 5. Verify the cluster

```bash
export KUBECONFIG=~/.kube/sovereign-do.yaml
kubectl get nodes
# NAME          STATUS   ROLES                  AGE   VERSION
# sovereign-1   Ready    control-plane,master   1m    v1.29.4+k3s1

./bootstrap/verify.sh
```

## Scaling Up

To resize a Droplet (requires a power-off):

```bash
doctl compute droplet-action resize <droplet-id> --size s-4vcpu-8gb --wait
```

For horizontal scaling, provision additional Droplets and join them as K3s agents:

```bash
# Get the join token from the server
K3S_TOKEN=$(ssh root@<server-ip> "cat /var/lib/rancher/k3s/server/node-token")

# On each agent Droplet
curl -sfL https://get.k3s.io | K3S_URL=https://<server-ip>:6443 K3S_TOKEN=$K3S_TOKEN sh -
```

## Cleanup

To destroy all resources:

```bash
doctl compute droplet delete sovereign-1 --force
```

## Troubleshooting

**doctl: command not found:** Install doctl using the instructions above.

**Authentication failed:** Run `doctl auth init` again with a fresh API token.

**SSH key import fails:** Ensure `~/.ssh/id_ed25519.pub` exists. Generate a key pair
with `ssh-keygen -t ed25519 -C "your-email@example.com"`.

**K3s install fails:** Check that the Droplet has internet access. Verify with:
`ssh root@<ip> "curl -I https://get.k3s.io"`

**Droplet not found after creation:** DigitalOcean Droplets take ~30–60 seconds to
provision. The `--wait` flag in `doctl` handles this automatically.
