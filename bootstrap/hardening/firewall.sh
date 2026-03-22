#!/usr/bin/env bash
# bootstrap/hardening/firewall.sh — UFW firewall: default-deny + frontdoor CIDRs
#
# Run on each node as root via SSH. Configures UFW to:
#   - Default DENY all inbound connections
#   - Default ALLOW all outbound connections
#   - Allow inbound HTTPS (443) and HTTP (80) only from front door CIDRs
#   - Allow inbound K8s API (6443) only from front door CIDRs
#   - Allow inbound Cilium overlay (VXLAN 8472) between cluster nodes
#   - Allow inbound etcd (2379/2380) between cluster nodes (from NODE_CIDRS)
#   - Allow loopback unconditionally
#
# CIDRs are passed via the FRONTDOOR_CIDRS env var (newline or space separated)
# and NODE_CIDRS env var (newline or space separated node IPs/CIDRs).
#
# Usage (called by bootstrap.sh via SSH):
#   FRONTDOOR_CIDRS="<cidr1>\n<cidr2>" \
#   NODE_CIDRS="<node1-ip>/32 <node2-ip>/32 <node3-ip>/32" \
#     ssh root@<node-ip> 'bash -s' < bootstrap/hardening/firewall.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "==> [hardening/firewall] Configuring UFW firewall..."

# Ensure we are running as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: firewall.sh must run as root" >&2
  exit 1
fi

# Require UFW
if ! command -v ufw &>/dev/null; then
  echo "==> [hardening/firewall] Installing UFW..."
  apt-get install -y -qq ufw
fi

# ── Reset UFW to a clean state ─────────────────────────────────────────────
echo "==> [hardening/firewall] Resetting UFW rules..."
ufw --force reset

# ── Default policies ───────────────────────────────────────────────────────
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

# ── Always allow loopback ──────────────────────────────────────────────────
ufw allow in on lo
ufw deny in from 127.0.0.0/8

# ── Allow SSH from front door CIDRs only ───────────────────────────────────
# (SSH access is via the front door tunnel or whitelisted IP)
FRONTDOOR_CIDRS="${FRONTDOOR_CIDRS:-}"
if [[ -n "$FRONTDOOR_CIDRS" ]]; then
  echo "==> [hardening/firewall] Allowing platform traffic from front door CIDRs..."
  while IFS= read -r cidr; do
    [[ -z "$cidr" ]] && continue
    echo "    Allowing CIDR: $cidr"
    ufw allow from "$cidr" to any port 22 comment "SSH via frontdoor"
    ufw allow from "$cidr" to any port 80 comment "HTTP via frontdoor"
    ufw allow from "$cidr" to any port 443 comment "HTTPS via frontdoor"
    ufw allow from "$cidr" to any port 6443 comment "K8s API via frontdoor"
  done <<< "$FRONTDOOR_CIDRS"
else
  echo "  WARN: FRONTDOOR_CIDRS is empty — no external access will be allowed." >&2
fi

# ── Allow cluster-internal traffic (node-to-node) ─────────────────────────
NODE_CIDRS="${NODE_CIDRS:-}"
if [[ -n "$NODE_CIDRS" ]]; then
  echo "==> [hardening/firewall] Allowing cluster-internal traffic between nodes..."
  while IFS= read -r cidr; do
    [[ -z "$cidr" ]] && continue
    echo "    Node CIDR: $cidr"
    # Cilium VXLAN overlay
    ufw allow from "$cidr" to any port 8472 proto udp comment "Cilium VXLAN"
    # etcd cluster communication
    ufw allow from "$cidr" to any port 2379 proto tcp comment "etcd client"
    ufw allow from "$cidr" to any port 2380 proto tcp comment "etcd peer"
    # K3s node ports
    ufw allow from "$cidr" to any port 10250 proto tcp comment "kubelet"
    ufw allow from "$cidr" to any port 10251 proto tcp comment "kube-scheduler"
    ufw allow from "$cidr" to any port 10252 proto tcp comment "kube-controller"
    # kube-vip health check
    ufw allow from "$cidr" to any port 9999 proto tcp comment "kube-vip health"
  done <<< "$NODE_CIDRS"
fi

# ── Enable UFW ──────────────────────────────────────────────────────────────
echo "==> [hardening/firewall] Enabling UFW..."
ufw --force enable

echo "==> [hardening/firewall] UFW status:"
ufw status verbose

echo "==> [hardening/firewall] Firewall hardening complete."
