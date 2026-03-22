#!/usr/bin/env bash
# hetzner.sh — Provision a Hetzner Cloud server and install K3s
# Called by bootstrap.sh after loading config.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SOVEREIGN_CONFIG:-${SCRIPT_DIR}/../config.yaml}"

# Require hcloud CLI
if ! command -v hcloud &>/dev/null; then
  echo "ERROR: 'hcloud' CLI is required." >&2
  echo "  Install: brew install hcloud  (macOS) or see https://github.com/hetznercloud/cli" >&2
  exit 1
fi

# Require yq
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with: brew install yq" >&2
  exit 1
fi

# Read Hetzner-specific config
HCLOUD_TOKEN="$(yq '.hetzner.token' "$CONFIG_FILE")"
SERVER_TYPE="$(yq '.hetzner.serverType // "cx22"' "$CONFIG_FILE")"
LOCATION="$(yq '.hetzner.location // "nbg1"' "$CONFIG_FILE")"
SSH_KEY_NAME="$(yq '.hetzner.sshKeyName' "$CONFIG_FILE")"
SERVER_NAME="$(yq '.hetzner.serverName // "sovereign"' "$CONFIG_FILE")"
DOMAIN="${SOVEREIGN_DOMAIN:-$(yq '.domain' "$CONFIG_FILE")}"
K3S_VERSION="$(yq '.k3sVersion // "v1.29.4+k3s1"' "$CONFIG_FILE")"

if [[ -z "$HCLOUD_TOKEN" || "$HCLOUD_TOKEN" == "null" ]]; then
  echo "ERROR: 'hetzner.token' is required in config.yaml" >&2
  exit 1
fi

if [[ -z "$SSH_KEY_NAME" || "$SSH_KEY_NAME" == "null" ]]; then
  echo "ERROR: 'hetzner.sshKeyName' is required in config.yaml" >&2
  exit 1
fi

export HCLOUD_TOKEN

echo "==> [Hetzner] Provisioning server"
echo "    Server type: $SERVER_TYPE"
echo "    Location:    $LOCATION"
echo "    Name:        $SERVER_NAME"
echo ""

# Check if server already exists
if hcloud server describe "$SERVER_NAME" &>/dev/null; then
  echo "==> Server '$SERVER_NAME' already exists, skipping creation."
  SERVER_IP="$(hcloud server describe "$SERVER_NAME" -o format='{{.PublicNet.IPv4.IP}}')"
else
  echo "==> Creating server..."
  hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --image ubuntu-22.04 \
    --location "$LOCATION" \
    --ssh-key "$SSH_KEY_NAME"

  echo "==> Waiting for server to be running..."
  for i in $(seq 1 30); do
    STATUS="$(hcloud server describe "$SERVER_NAME" -o format='{{.Status}}')"
    if [[ "$STATUS" == "running" ]]; then
      break
    fi
    echo "    Status: $STATUS (attempt $i/30)..."
    sleep 5
  done

  SERVER_IP="$(hcloud server describe "$SERVER_NAME" -o format='{{.PublicNet.IPv4.IP}}')"
  echo "==> Server created: $SERVER_IP"

  # Wait for SSH to be ready
  echo "==> Waiting for SSH to be ready..."
  for i in $(seq 1 20); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@${SERVER_IP}" "echo ok" &>/dev/null; then
      break
    fi
    echo "    SSH not ready yet (attempt $i/20)..."
    sleep 10
  done
fi

echo "==> Server IP: $SERVER_IP"
echo ""

# Install K3s
echo "==> Installing K3s ${K3S_VERSION} on ${SERVER_IP}..."
ssh -o StrictHostKeyChecking=no "root@${SERVER_IP}" \
  "INSTALL_K3S_VERSION=${K3S_VERSION} sh -s - --write-kubeconfig-mode 644 --tls-san ${SERVER_IP} --tls-san ${DOMAIN}" \
  < <(curl -sfL https://get.k3s.io)

# Retrieve kubeconfig
echo "==> Fetching kubeconfig..."
KUBECONFIG_DIR="${HOME}/.kube"
mkdir -p "$KUBECONFIG_DIR"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/sovereign-hetzner.yaml"

ssh -o StrictHostKeyChecking=no "root@${SERVER_IP}" "cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/${SERVER_IP}/g" \
  > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"
echo "==> kubeconfig saved to: $KUBECONFIG_FILE"
echo ""
echo "    To use:  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""

# Cost estimate
echo "================================================================"
echo "  ESTIMATED MONTHLY COST (Hetzner)"
echo "================================================================"
case "$SERVER_TYPE" in
  cx11|cx12) echo "  ~  3-4 EUR/month (CX11/CX12 — 2 vCPU, 2GB RAM)" ;;
  cx21|cx22) echo "  ~  5-6 EUR/month (CX21/CX22 — 2 vCPU, 4GB RAM)  [recommended]" ;;
  cx31|cx32) echo "  ~ 10-12 EUR/month (CX31/CX32 — 2 vCPU, 8GB RAM)" ;;
  cx41|cx42) echo "  ~ 18-20 EUR/month (CX41/CX42 — 4 vCPU, 16GB RAM)" ;;
  *)         echo "  See https://www.hetzner.com/cloud for pricing for $SERVER_TYPE" ;;
esac
echo ""

# DNS instructions
echo "================================================================"
echo "  CLOUDFLARE DNS SETUP"
echo "================================================================"
echo "  Add a wildcard A record in Cloudflare DNS:"
echo ""
echo "    Type:  A"
echo "    Name:  *.${DOMAIN}"
echo "    Value: ${SERVER_IP}"
echo "    TTL:   Auto"
echo "    Proxy: DNS only (grey cloud) — NOT proxied initially"
echo ""
echo "  Also add a root A record:"
echo "    Type:  A"
echo "    Name:  ${DOMAIN}"
echo "    Value: ${SERVER_IP}"
echo ""
echo "================================================================"
echo "  NEXT STEPS"
echo "================================================================"
echo "  1. Set Cloudflare DNS as shown above"
echo "  2. export KUBECONFIG=$KUBECONFIG_FILE"
echo "  3. kubectl get nodes   # verify cluster is Ready"
echo "  4. ./bootstrap/verify.sh"
echo "================================================================"
