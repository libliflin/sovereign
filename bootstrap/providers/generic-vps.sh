#!/usr/bin/env bash
# generic-vps.sh — SSH-install K3s on any Ubuntu 22.04 server
# Called by bootstrap.sh after loading config.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SOVEREIGN_CONFIG:-${SCRIPT_DIR}/../config.yaml}"

# Require yq
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with: brew install yq" >&2
  exit 1
fi

# Read generic VPS config
SERVER_IP="$(yq '.genericVps.ip' "$CONFIG_FILE")"
SSH_USER="$(yq '.genericVps.sshUser // "root"' "$CONFIG_FILE")"
SSH_KEY_PATH="$(yq '.genericVps.sshKeyPath' "$CONFIG_FILE")"
DOMAIN="${SOVEREIGN_DOMAIN:-$(yq '.domain' "$CONFIG_FILE")}"
K3S_VERSION="$(yq '.k3sVersion // "v1.29.4+k3s1"' "$CONFIG_FILE")"

if [[ -z "$SERVER_IP" || "$SERVER_IP" == "null" ]]; then
  echo "ERROR: 'genericVps.ip' is required in config.yaml for provider: generic-vps" >&2
  exit 1
fi

if [[ -z "$SSH_KEY_PATH" || "$SSH_KEY_PATH" == "null" ]]; then
  echo "ERROR: 'genericVps.sshKeyPath' is required in config.yaml" >&2
  exit 1
fi

# Expand tilde in SSH key path
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
  echo "ERROR: SSH key not found: $SSH_KEY_PATH" >&2
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${SSH_KEY_PATH}")

echo "==> [Generic VPS] Preparing to install K3s"
echo "    Target:   ${SSH_USER}@${SERVER_IP}"
echo "    K3s:      $K3S_VERSION"
echo "    Domain:   $DOMAIN"
echo ""

# Check SSH connectivity
echo "==> Testing SSH connectivity..."
if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "echo 'SSH OK'" 2>/dev/null; then
  echo "ERROR: Cannot connect to ${SSH_USER}@${SERVER_IP}" >&2
  echo "  Verify the IP address and SSH key are correct." >&2
  exit 1
fi

# Check OS
OS_INFO="$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "cat /etc/os-release | grep PRETTY_NAME" 2>/dev/null || echo 'unknown')"
echo "==> Remote OS: $OS_INFO"

# Check if K3s is already installed
if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "command -v k3s" &>/dev/null; then
  echo "==> K3s already installed on ${SERVER_IP}, skipping installation."
else
  echo "==> Installing K3s ${K3S_VERSION}..."
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" \
    "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} sh -s - \
      --write-kubeconfig-mode 644 \
      --tls-san ${SERVER_IP} \
      --tls-san ${DOMAIN}"

  echo "==> Waiting for K3s to start..."
  for i in $(seq 1 20); do
    if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "kubectl get nodes" &>/dev/null; then
      break
    fi
    echo "    Not ready yet (attempt $i/20)..."
    sleep 10
  done
fi

# Retrieve kubeconfig
echo "==> Fetching kubeconfig..."
KUBECONFIG_DIR="${HOME}/.kube"
mkdir -p "$KUBECONFIG_DIR"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/sovereign-vps.yaml"

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/${SERVER_IP}/g" \
  > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"
echo "==> kubeconfig saved to: $KUBECONFIG_FILE"
echo ""
echo "    To use:  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""

# Cost estimate
echo "================================================================"
echo "  ESTIMATED MONTHLY COST"
echo "================================================================"
echo "  Varies by provider — typical single-node K3s hosts:"
echo "    Vultr   1 vCPU / 1GB:  ~\$5-6/month"
echo "    Linode  1 vCPU / 1GB:  ~\$5/month (Nanode)"
echo "    Vultr   2 vCPU / 4GB:  ~\$24/month"
echo "    Linode  2 vCPU / 4GB:  ~\$20/month"
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
