# Custom Front Door Provider Guide

The Sovereign bootstrap uses a **pluggable front door** pattern that lets you
choose how inbound traffic reaches your cluster — or replace the default
Cloudflare Tunnel with any technology that suits your environment.

## The 5-hook contract

Every front door provider is a Bash script that defines exactly 5 functions.
The bootstrap calls them in order:

```
frontdoor_provision        (local)  — create the tunnel / gateway
frontdoor_install_agent    (remote) — install daemon on every VPS node
frontdoor_allowed_cidrs    (local)  — print CIDRs to allow through UFW
frontdoor_configure_dns    (local)  — point DNS at the front door
frontdoor_connection_info  (local)  — print post-bootstrap access instructions
```

### Call order in bootstrap.sh

```bash
# 1. Harden all nodes (unattended-upgrades, fail2ban, auditd, CIS sysctl)
source "bootstrap/hardening/base.sh"
source "bootstrap/hardening/ssh.sh"
source "bootstrap/hardening/kernel.sh"

# 2. Source the chosen front door implementation
source "bootstrap/frontdoor/${FRONT_DOOR}.sh"

# 3. Create the tunnel / gateway (local)
frontdoor_provision

# 4. Install the agent on every node (remote)
for node_ip in $NODE_IPS; do
  frontdoor_install_agent "$node_ip"
done

# 5. Configure DNS (local)
frontdoor_configure_dns

# 6. Lock down the firewall using allowed CIDRs (remote)
FRONTDOOR_CIDRS="$(frontdoor_allowed_cidrs)"
export FRONTDOOR_CIDRS
for node_ip in $NODE_IPS; do
  ssh root@"$node_ip" 'bash -s' < bootstrap/hardening/firewall.sh
done

# 7. Print access instructions (local)
frontdoor_connection_info
```

### Environment variables available in every hook

| Variable | Description |
|---|---|
| `DOMAIN` | Primary domain from `config.yaml` (e.g. `example.com`) |
| `NODE_IPS` | Space-separated list of all node IPs |
| `SSH_KEY` | Path to the SSH private key |
| `CONFIG_FILE` | Path to `bootstrap/config.yaml` |

---

## Built-in providers

| Provider | File | When to use |
|---|---|---|
| `cloudflare` | `bootstrap/frontdoor/cloudflare.sh` | Default — free, no open ports |
| `none` | `bootstrap/frontdoor/none.sh` | Testing / bare-metal with static IP |

---

## Implementing a custom provider — WireGuard example

This worked example implements a WireGuard-based front door.  Traffic enters
through a small "gateway" VPS that forwards it to the cluster nodes over a
WireGuard VPN.

### Architecture

```
User → gateway VPS (public IP) → WireGuard VPN → cluster nodes (private IPs)
```

### Step 1 — Copy the template

```bash
cp bootstrap/frontdoor/custom.sh.example bootstrap/frontdoor/wireguard.sh
```

Set `frontDoor: wireguard` in `bootstrap/config.yaml`.

### Step 2 — Implement `frontdoor_provision`

This runs locally.  It generates WireGuard keys and writes the peer config.

```bash
frontdoor_provision() {
  # Generate a keypair for the gateway
  local gw_private; gw_private="$(wg genkey)"
  local gw_public;  gw_public="$(echo "$gw_private" | wg pubkey)"

  # Read gateway IP from config.yaml
  local gw_ip; gw_ip="$(yq '.wireguard.gatewayIp' "$CONFIG_FILE")"

  # Write gateway config to /tmp for use in install_agent
  printf '[Interface]\nPrivateKey = %s\nAddress = 10.99.0.1/24\nListenPort = 51820\n' \
    "$gw_private" > /tmp/frontdoor-gateway.conf

  # Write the gateway public key for node peer configs
  echo "$gw_public" > /tmp/frontdoor-gw-pubkey
  echo "$gw_ip"     > /tmp/frontdoor-endpoint

  echo "frontdoor: WireGuard gateway config written"
}
```

### Step 3 — Implement `frontdoor_install_agent`

Called once per node.  Installs WireGuard and creates the peer configuration.

```bash
frontdoor_install_agent() {
  local node_ip="${1:?}"
  local SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i "$SSH_KEY")
  local node_index="${2:-0}"                 # bootstrap.sh passes 0-based index

  # Generate a keypair for this node
  local node_private; node_private="$(wg genkey)"
  local node_public;  node_public="$(echo "$node_private" | wg pubkey)"
  local node_addr="10.99.0.$((node_index + 2))/24"

  # Build node wg0.conf
  local gw_pubkey; gw_pubkey="$(cat /tmp/frontdoor-gw-pubkey)"
  local gw_ip;     gw_ip="$(cat /tmp/frontdoor-endpoint)"
  local wg_conf
  wg_conf="$(printf '[Interface]\nPrivateKey = %s\nAddress = %s\n\n[Peer]\nPublicKey = %s\nEndpoint = %s:51820\nAllowedIPs = 10.99.0.0/24\nPersistentKeepalive = 25\n' \
    "$node_private" "$node_addr" "$gw_pubkey" "$gw_ip")"

  # Install WireGuard on the node
  ssh "${SSH_OPTS[@]}" "root@${node_ip}" 'apt-get update -qq && apt-get install -y wireguard'

  # Push the config
  printf '%s\n' "$wg_conf" | ssh "${SSH_OPTS[@]}" "root@${node_ip}" 'cat > /etc/wireguard/wg0.conf && chmod 600 /etc/wireguard/wg0.conf'

  # Enable and start
  ssh "${SSH_OPTS[@]}" "root@${node_ip}" 'systemctl enable --now wg-quick@wg0'

  echo "frontdoor: WireGuard installed on ${node_ip} (${node_addr})"
}
```

### Step 4 — Implement `frontdoor_allowed_cidrs`

Only the WireGuard gateway needs to reach the nodes directly.

```bash
frontdoor_allowed_cidrs() {
  local gw_ip; gw_ip="$(cat /tmp/frontdoor-endpoint)"
  echo "${gw_ip}/32"
  # Plus the WireGuard internal subnet so nodes can talk to each other
  echo "10.99.0.0/24"
}
```

### Step 5 — Implement `frontdoor_configure_dns`

Point `*.<domain>` at the gateway's public IP.

```bash
frontdoor_configure_dns() {
  local gw_ip; gw_ip="$(cat /tmp/frontdoor-endpoint)"
  local CF_API_TOKEN; CF_API_TOKEN="$(yq '.cloudflare.apiToken' "$CONFIG_FILE")"
  local CF_ZONE_ID;   CF_ZONE_ID="$(yq '.cloudflare.zoneId' "$CONFIG_FILE")"

  # Use the shared Cloudflare DNS helper (or replace with your DNS provider's API)
  # shellcheck source=bootstrap/providers/cloudflare-dns.sh
  source "bootstrap/providers/cloudflare-dns.sh"
  cf_dns_upsert "*.${DOMAIN}" "A" "$gw_ip" false
  cf_dns_upsert "$DOMAIN"     "A" "$gw_ip" false

  echo "frontdoor: DNS configured — *.${DOMAIN} → ${gw_ip}"
}
```

### Step 6 — Implement `frontdoor_connection_info`

```bash
frontdoor_connection_info() {
  local gw_ip; gw_ip="$(cat /tmp/frontdoor-endpoint)"
  echo ""
  echo "=============================================="
  echo "  Bootstrap complete (WireGuard front door)"
  echo "=============================================="
  echo ""
  echo "  Gateway VPS: ${gw_ip}"
  echo ""
  echo "  SSH to nodes (direct, via WireGuard VPN):"
  echo "    ssh -i ${SSH_KEY} root@10.99.0.2"
  echo ""
  echo "  Platform services:"
  echo "    ArgoCD:   https://argocd.${DOMAIN}"
  echo "    Grafana:  https://grafana.${DOMAIN}"
  echo "    GitLab:   https://gitlab.${DOMAIN}"
  echo "    Keycloak: https://auth.${DOMAIN}"
  echo ""
  echo "  Kubernetes:"
  echo "    export KUBECONFIG=~/.kube/sovereign-${DOMAIN}.yaml"
  echo "    kubectl get nodes"
}
```

---

## Implementing other front door types

### Tailscale

Use `tailscale up --advertise-routes` on each node and the Tailscale API to
create an auth key.  `frontdoor_allowed_cidrs` returns only the Tailscale
CGNAT range `100.64.0.0/10` — no public ports needed.

### Bastion / jump host

Provision a single small "bastion" VM with a public IP.  All cluster traffic
NATed through it.  `frontdoor_allowed_cidrs` returns only the bastion IP.

### Bare metal / static IP

If your cluster is on a fixed IP with no NAT concerns, use the `none` provider
(or a simple custom provider that returns your management IP range).

---

## Testing your provider

Before running a full bootstrap:

```bash
# Source your provider and test each hook in isolation
source bootstrap/config.yaml   # or export the env vars manually
source bootstrap/frontdoor/wireguard.sh

frontdoor_provision
frontdoor_allowed_cidrs        # should print one or more CIDRs
# frontdoor_install_agent <node-ip>   # test against a real or test VPS
# frontdoor_configure_dns            # test against your DNS provider
frontdoor_connection_info
```

Run shellcheck before committing:

```bash
shellcheck bootstrap/frontdoor/wireguard.sh
```
