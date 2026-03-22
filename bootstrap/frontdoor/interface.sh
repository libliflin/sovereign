#!/usr/bin/env bash
# bootstrap/frontdoor/interface.sh — Front door provider hook contract
#
# Every front door implementation MUST source this file and implement all 5
# functions listed below. To add a new provider:
#
#   1. Copy bootstrap/frontdoor/custom.sh.example to bootstrap/frontdoor/<name>.sh
#   2. Implement all 5 functions
#   3. Set frontDoor: <name> in bootstrap/config.yaml
#
# bootstrap.sh sources the chosen implementation and calls hooks in this order:
#
#   1. frontdoor_provision      — local: create tunnel / reserve service
#   2. frontdoor_install_agent  — remote: install daemon on each node
#   3. frontdoor_configure_dns  — point DNS records at the front door
#   4. frontdoor_allowed_cidrs  — emit CIDRs; firewall.sh applies UFW rules
#   5. frontdoor_connection_info — print how to connect after bootstrap
#
# ─────────────────────────────────────────────────────────────────────────────

# frontdoor_provision
# ─────────────────────────────────────────────────────────────────────────────
# Run locally BEFORE nodes are hardened. Creates whatever external service or
# tunnel the front door needs (e.g., Cloudflare Tunnel, WireGuard config).
#
# Environment guaranteed by bootstrap.sh:
#   SOVEREIGN_DOMAIN    — the platform domain (e.g. sovereign-autarky.dev)
#   SOVEREIGN_CONFIG    — path to bootstrap/config.yaml
#   SOVEREIGN_NODE_IPS  — space-separated list of all node IPs
#
# Must exit 0 on success. May write state to /tmp/sovereign-frontdoor-*.
#
# Example:
#   frontdoor_provision() {
#     echo "==> [frontdoor] Creating Cloudflare Tunnel..."
#   }
frontdoor_provision() {
  echo "ERROR: frontdoor_provision not implemented by $(basename "${BASH_SOURCE[0]}")" >&2
  exit 1
}

# frontdoor_install_agent [NODE_IP...]
# ─────────────────────────────────────────────────────────────────────────────
# Run remotely on EACH node after provisioning. Installs the front door agent
# daemon (e.g., cloudflared, WireGuard, Tailscale) and starts it.
#
# Arguments: $@ — one or more node IP addresses to install on
#
# Uses the SSH credentials from SOVEREIGN_CONFIG (sshKeyPath, ssh user).
# Must be idempotent — safe to run more than once on the same node.
#
# Example:
#   frontdoor_install_agent() {
#     for NODE_IP in "$@"; do
#       ssh root@"$NODE_IP" "curl -fsSL https://example.com/install.sh | sh"
#     done
#   }
frontdoor_install_agent() {
  echo "ERROR: frontdoor_install_agent not implemented by $(basename "${BASH_SOURCE[0]}")" >&2
  exit 1
}

# frontdoor_configure_dns
# ─────────────────────────────────────────────────────────────────────────────
# Point DNS records for *.<domain> at the front door entry point.
# Called after the agent is installed and running on all nodes.
#
# Environment guaranteed by bootstrap.sh:
#   SOVEREIGN_DOMAIN    — the platform domain
#   SOVEREIGN_CONFIG    — path to config.yaml
#
# For tunnel-based providers (Cloudflare): create a CNAME to the tunnel hostname.
# For IP-based providers: create an A record to the VIP.
# For manual providers (none): print instructions for the human operator.
#
# Example:
#   frontdoor_configure_dns() {
#     echo "==> [frontdoor] Creating wildcard DNS CNAME..."
#   }
frontdoor_configure_dns() {
  echo "ERROR: frontdoor_configure_dns not implemented by $(basename "${BASH_SOURCE[0]}")" >&2
  exit 1
}

# frontdoor_allowed_cidrs
# ─────────────────────────────────────────────────────────────────────────────
# Print newline-separated CIDR ranges that should be allowed through the
# firewall. bootstrap.sh passes this output to hardening/firewall.sh, which
# applies UFW rules: allow only these CIDRs on platform ports (80, 443, 6443).
#
# For tunnel-based providers: emit Cloudflare IP ranges (no inbound ports needed)
#   but the node still needs to accept health checks from within the cluster.
# For IP-based providers: emit the VPN/bastion CIDR.
# For manual providers (none): prompt the operator for their public IP.
#
# Output must be valid IPv4 or IPv6 CIDRs, one per line.
# Empty output means "no inbound access allowed" — use with caution.
#
# Example:
#   frontdoor_allowed_cidrs() {
#     echo "173.245.48.0/20"
#     echo "103.21.244.0/22"
#   }
frontdoor_allowed_cidrs() {
  echo "ERROR: frontdoor_allowed_cidrs not implemented by $(basename "${BASH_SOURCE[0]}")" >&2
  exit 1
}

# frontdoor_connection_info
# ─────────────────────────────────────────────────────────────────────────────
# Print human-readable instructions for connecting to the cluster after
# bootstrap completes. Called as the final step.
#
# Should cover:
#   - How to SSH into nodes (e.g., cloudflare access ssh, tailscale ssh)
#   - How to access the Kubernetes API
#   - Any dashboards or control plane URLs
#
# Example:
#   frontdoor_connection_info() {
#     echo "Access nodes via: cloudflare access ssh root@node1.${SOVEREIGN_DOMAIN}"
#   }
frontdoor_connection_info() {
  echo "ERROR: frontdoor_connection_info not implemented by $(basename "${BASH_SOURCE[0]}")" >&2
  exit 1
}
