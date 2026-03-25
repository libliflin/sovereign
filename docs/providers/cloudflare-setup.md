# Cloudflare Setup Guide

This guide covers setting up a Cloudflare free account and configuring the
credentials that the Sovereign bootstrap uses for tunnel creation and DNS
management.

## What the bootstrap uses Cloudflare for

| Feature | Purpose |
|---|---|
| **Cloudflare Tunnel** | Outbound-only tunnel from your VPS to Cloudflare's edge — no inbound ports opened |
| **Wildcard DNS** | `*.<domain>` CNAME pointing at the tunnel, created automatically by `bootstrap.sh` |
| **Zero Trust SSH** | Replaces SSH over port 22; access via `cloudflared access ssh` |

After bootstrap, **your VPS has no open inbound ports**.  All traffic (HTTP,
HTTPS, SSH) flows through the tunnel.

---

## Step 1 — Create a Cloudflare account

1. Go to <https://dash.cloudflare.com/sign-up> and create a free account.
2. Add your domain to Cloudflare (follow the on-screen instructions).
3. Update your registrar's nameservers to Cloudflare's nameservers.

> **Free tier is sufficient.**  Cloudflare Tunnel, Zero Trust SSH, and DNS API
> access are all available on the free plan.

---

## Step 2 — Find your Account ID and Zone ID

### Account ID

1. Log in to the Cloudflare dashboard.
2. Click any domain in your account list.
3. On the right sidebar, scroll to **API** — your **Account ID** is listed there.

Alternatively, from the Cloudflare dashboard URL:

```text
https://dash.cloudflare.com/<ACCOUNT_ID>/...
```

### Zone ID

1. In the Cloudflare dashboard, select your domain.
2. On the **Overview** page, scroll down to the **API** section on the right.
3. Copy the **Zone ID**.

---

## Step 3 — Create an API Token

The bootstrap needs an API token with permission to create tunnels and manage
DNS records.

1. Go to **My Profile → API Tokens → Create Token**.
2. Use **Create Custom Token**.
3. Set the following permissions:

| Permission type | Resource | Permission |
|---|---|---|
| Account | Cloudflare Tunnel | Edit |
| Zone | DNS | Edit |

1. Under **Zone Resources**, select **Specific zone → your domain**.
1. Under **Account Resources**, select **All accounts** (or the specific account).
1. Click **Continue to summary**, then **Create Token**.
1. **Copy the token immediately** — it will not be shown again.

---

## Step 4 — Choose a tunnel name

Pick a short, descriptive name for your tunnel, e.g. `sovereign-example-com`.
The name is used in the Cloudflare dashboard and in the tunnel's CNAME target.

---

## Step 5 — Add credentials to config.yaml

```yaml
cloudflare:
  apiToken: "your-api-token-here"         # from Step 3
  accountId: "your-account-id-here"       # from Step 2
  zoneId: "your-zone-id-here"             # from Step 2
  tunnelName: "sovereign-example-com"     # from Step 4

frontDoor: cloudflare                     # activates this provider
```

> **Never commit `bootstrap/config.yaml`.**  The `.gitignore` excludes it, but
> double-check before pushing.

---

## Step 6 — Run the bootstrap

```bash
./bootstrap/bootstrap.sh
```

The bootstrap will:

1. Call `frontdoor_provision` — creates the tunnel via Cloudflare API
2. Install `cloudflared` on every VPS node as a systemd service
3. Call `frontdoor_configure_dns` — creates `*.<domain>` CNAME record
4. Print Zero Trust SSH access instructions

---

## Zero Trust SSH access (post-bootstrap)

After bootstrap, SSH access goes through Cloudflare Access rather than a
public SSH port.

### Install `cloudflared` locally

```bash
# macOS
brew install cloudflare/cloudflare/cloudflared

# Linux (Debian/Ubuntu)
curl -L https://pkg.cloudflare.com/cloudflared-stable-linux-amd64.deb -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb
```

### Configure SSH

Add to `~/.ssh/config`:

```text
Host *.example.com
    ProxyCommand cloudflared access ssh --hostname %h
```

### Connect

```bash
ssh root@node1.example.com
```

Cloudflare Access will prompt for browser authentication on the first
connection.  Subsequent connections are seamless.

---

## Verifying the tunnel

After bootstrap completes:

```bash
# Check tunnel status in Cloudflare dashboard
# Zero Trust → Access → Tunnels → sovereign-example-com → should show "Healthy"

# Or via curl (replace with your actual domain)
curl -I https://argocd.example.com
# Should return 200 or 302 — traffic is flowing through the tunnel
```

---

## Troubleshooting

### Tunnel shows "Degraded" or "Down"

```bash
# SSH to the VPS and check the service
ssh root@<node-ip>
systemctl status cloudflared
journalctl -u cloudflared -n 50
```

Common causes:

- `credentials.json` has wrong permissions (must be 600)
- `config.yml` has wrong tunnel ID
- Network egress blocked (some providers block outbound 443 to Cloudflare)

### DNS record not created

Check that the API token has **DNS: Edit** permission for the correct zone.
Run `bootstrap/providers/cloudflare-dns.sh` helpers manually to test:

```bash
source bootstrap/providers/cloudflare-dns.sh
export CF_API_TOKEN="your-token"
export CF_ZONE_ID="your-zone-id"
cf_zone_lookup example.com   # should print your zone ID
```

### API token errors

Verify the token has not expired and has the correct account/zone scopes.
Re-create the token in the Cloudflare dashboard if needed, then update
`bootstrap/config.yaml` and re-run `./bootstrap/bootstrap.sh`.
