# Sovereign Platform — Quickstart Guide

Get from zero to a running platform in ~15 minutes.

## Security posture

By default, **Sovereign closes all inbound ports** on your VPS.  All traffic
(HTTP, HTTPS, SSH) is routed through a Cloudflare Tunnel — an outbound-only
connection from your server to Cloudflare's edge.  No firewall rules, no open
ports, no IP whitelisting required.

```text
User → Cloudflare edge → Cloudflare Tunnel (outbound) → your VPS
```

If you prefer a different approach (WireGuard VPN, static IP allow-list, or
no front door at all), you can swap the front door provider in `config.yaml`:

```yaml
frontDoor: cloudflare   # default — recommended
# frontDoor: none       # bare-metal / known-IP setup (prompts for your IP)
# frontDoor: wireguard  # custom WireGuard-based front door
```

See [Front Door Provider Guide](providers/front-door-custom.md) to implement
your own.

---

## Prerequisites

Before you begin, you need:

- **A domain name** (e.g., `example.com`) with DNS managed by Cloudflare
  (required for the default front door; see [Cloudflare Setup](providers/cloudflare-setup.md))
- **A server or cloud account** — see [Provider Guides](#provider-guides)
- **Local tools:**
  - `bash`, `ssh`, `curl`, `yq`
  - `kubectl` — [install](https://kubernetes.io/docs/tasks/tools/)
  - `helm` v3+ — [install](https://helm.sh/docs/intro/install/)
  - Provider CLI (see your provider guide)

## Step 1: Clone the repo

```bash
git clone https://github.com/libliflin/sovereign
cd sovereign
```

## Step 2: Configure

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
```

Open `bootstrap/config.yaml` and fill in:

- `domain` — your domain name
- `provider` — your cloud provider (`hetzner`, `generic`, `aws-ec2`, `digitalocean`)
- `frontDoor` — security front door (`cloudflare` recommended; see [Cloudflare Setup](providers/cloudflare-setup.md))
- Provider credentials (API tokens, SSH key path)
- Cloudflare credentials (`cloudflare.apiToken`, `accountId`, `zoneId`, `tunnelName`)
- `platform.repoUrl` — your fork URL (ArgoCD will watch this)

## Step 3: Bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:

1. Harden all nodes (unattended-upgrades, fail2ban, auditd, CIS sysctl)
2. Provision a server (or connect to your existing one)
3. Create a Cloudflare Tunnel and install `cloudflared` on every node
4. Configure `*.<domain>` DNS via Cloudflare API (automatic — no manual step)
5. Install K3s with HA (3-node etcd cluster, kube-vip floating VIP)
6. Install cluster foundations (Cilium, Crossplane, cert-manager, Sealed Secrets)
7. Print connection instructions

> **No open ports.**  The Cloudflare Tunnel is outbound-only.  UFW blocks all
> inbound connections by default.

## Step 4: Verify the tunnel

If you are using the default Cloudflare front door, DNS is configured
automatically and the tunnel is live when bootstrap completes.

Check tunnel health in the Cloudflare Zero Trust dashboard:
**Zero Trust → Access → Tunnels → your-tunnel-name → Healthy**

For other front door providers, the bootstrap will print the DNS record you
need to create.

## Step 5: Verify

```bash
export KUBECONFIG=~/.kube/config-sovereign
./bootstrap/verify.sh
```

All checks should pass within 5-10 minutes of DNS propagation.

## Step 6: Access services

Once ArgoCD is running and synced, access your services:

| Service | URL |
|---|---|
| ArgoCD | `https://argocd.example.com` |
| Grafana | `https://grafana.example.com` |
| GitLab | `https://gitlab.example.com` |
| Keycloak | `https://auth.example.com` |

Default admin credentials are printed by the bootstrap script and stored in Sealed Secrets.

## Provider Guides

- [Hetzner Cloud](providers/hetzner.md) — ~€12/mo for 3-node HA cluster, recommended
- [AWS EC2](providers/aws-ec2.md) — ~$60/mo for 3-node HA cluster (t3.small minimum)
- [DigitalOcean](providers/digitalocean.md) — ~$18/mo for 3-node HA cluster
- [Vultr](providers/vultr.md) — ~$18/mo for 3-node HA cluster
- [Bare metal / existing cluster](providers/bare-metal.md) — free

## Front Door Guides

- [Cloudflare Setup](providers/cloudflare-setup.md) — default, free, no open ports
- [Custom Front Door](providers/front-door-custom.md) — WireGuard, Tailscale, or any provider

## Next Steps

- Read [Architecture](architecture.md) to understand the platform
- Read [Day-2 Operations](day-2-operations.md) for upgrades, backups, and scaling
