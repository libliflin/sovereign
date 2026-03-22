# Sovereign Platform — Quickstart Guide

Get from zero to a running platform in ~15 minutes.

## Prerequisites

Before you begin, you need:

- **A domain name** (e.g., `example.com`) with DNS you can manage
- **A server or cloud account** — see [Provider Guides](#provider-guides)
- **Local tools:**
  - `bash`, `ssh`, `curl`
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
- Provider credentials (API tokens, SSH key path)
- `platform.repoUrl` — your fork URL (ArgoCD will watch this)

## Step 3: Bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:
1. Provision a server (or connect to your existing one)
2. Install K3s
3. Install cluster foundations (Cilium, Crossplane, cert-manager, Sealed Secrets)
4. Print DNS setup instructions

## Step 4: Configure DNS

The bootstrap script will print a line like:

```
ACTION REQUIRED: Create DNS record:
  *.example.com → 1.2.3.4 (A record, TTL 300)
```

Create that wildcard DNS record in your DNS provider. This enables all service subdomains.

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

- [Hetzner Cloud](providers/hetzner.md) — ~€4/mo, recommended
- [AWS EC2 Free Tier](providers/aws-ec2-free-tier.md) — free for 12 months
- [DigitalOcean](providers/digitalocean.md) — ~$6/mo
- [Vultr](providers/vultr.md) — ~$6/mo
- [Bare metal / existing cluster](providers/bare-metal.md) — free

## Next Steps

- Read [Architecture](architecture.md) to understand the platform
- Read [Day-2 Operations](day-2-operations.md) for upgrades, backups, and scaling
