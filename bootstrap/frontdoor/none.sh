#!/usr/bin/env bash
# bootstrap/frontdoor/none.sh — Baseline front door (UFW only, no tunnel)
#
# This provider:
#   - Does NOT install any tunnel or VPN agent.
#   - Prompts the operator for their public IP (or reads FRONTDOOR_CALLER_IP).
#   - UFW allows only that IP on platform ports (80, 443, 6443).
#   - SSH is only allowed from the same CIDR.
#
# Security posture: all ports are blocked except from the caller's IP.
# Suitable for development or when behind a corporate VPN.
#
# Usage: set frontDoor: none in bootstrap/config.yaml
# ─────────────────────────────────────────────────────────────────────────────
# shellcheck source=bootstrap/frontdoor/interface.sh

# frontdoor_provision — no external service needed
frontdoor_provision() {
  echo "==> [frontdoor/none] No tunnel provisioning needed."
}

# frontdoor_install_agent — no daemon to install
frontdoor_install_agent() {
  echo "==> [frontdoor/none] No agent to install on nodes."
}

# frontdoor_configure_dns — manual instructions
frontdoor_configure_dns() {
  local domain="${SOVEREIGN_DOMAIN:-your-domain.com}"
  local vip="${SOVEREIGN_VIP:-<kube-vip-IP>}"
  echo ""
  echo "==> [frontdoor/none] Manual DNS setup required."
  echo ""
  echo "  Create a wildcard A record in your DNS provider:"
  echo "    *.${domain}  →  ${vip}"
  echo ""
  echo "  If using Cloudflare, also disable the proxy (orange cloud → grey cloud)"
  echo "  so the VIP is exposed directly. For production, use frontDoor: cloudflare instead."
  echo ""
}

# frontdoor_allowed_cidrs — prompt for caller IP or read from env
frontdoor_allowed_cidrs() {
  if [[ -n "${FRONTDOOR_CALLER_IP:-}" ]]; then
    echo "${FRONTDOOR_CALLER_IP}"
    return 0
  fi

  # Interactive prompt when running from a terminal
  if [[ -t 0 ]]; then
    echo "" >&2
    echo "==> [frontdoor/none] Enter your public IP (CIDR) to whitelist in UFW." >&2
    echo "    Find yours at: https://ifconfig.me" >&2
    echo "    Example: 203.0.113.42/32" >&2
    echo -n "    Your IP/CIDR: " >&2
    local caller_ip
    read -r caller_ip
    if [[ -z "$caller_ip" ]]; then
      echo "ERROR: No IP entered. Set FRONTDOOR_CALLER_IP=<your-ip>/32 to skip the prompt." >&2
      exit 1
    fi
    echo "$caller_ip"
  else
    echo "ERROR: frontdoor/none requires FRONTDOOR_CALLER_IP env var in non-interactive mode." >&2
    echo "  Example: FRONTDOOR_CALLER_IP=203.0.113.42/32 ./bootstrap/bootstrap.sh" >&2
    exit 1
  fi
}

# frontdoor_connection_info — print SSH instructions
frontdoor_connection_info() {
  local domain="${SOVEREIGN_DOMAIN:-your-domain.com}"
  local node_ips="${SOVEREIGN_NODE_IPS:-<node-IPs>}"
  echo ""
  echo "==> [frontdoor/none] Bootstrap complete."
  echo ""
  echo "  Nodes are accessible only from your whitelisted IP."
  echo "  SSH access:"
  for ip in $node_ips; do
    echo "    ssh root@${ip}"
  done
  echo ""
  echo "  Platform will be available at: https://argocd.${domain}"
  echo ""
  echo "  NOTE: For production, switch to frontDoor: cloudflare to close all"
  echo "        inbound ports and route traffic through a secure tunnel."
  echo ""
}
