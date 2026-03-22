#!/usr/bin/env bash
# digitalocean.sh — Provision a DigitalOcean Droplet and install K3s
# Called by bootstrap.sh after loading config.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SOVEREIGN_CONFIG:-${SCRIPT_DIR}/../config.yaml}"

# Require doctl CLI
if ! command -v doctl &>/dev/null; then
  echo "ERROR: 'doctl' CLI is required." >&2
  echo "  Install: brew install doctl  (macOS) or see https://docs.digitalocean.com/reference/doctl/how-to/install/" >&2
  echo "  Then run: doctl auth init" >&2
  exit 1
fi

# Require yq
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with: brew install yq" >&2
  exit 1
fi

# Read DigitalOcean config
DO_SIZE="$(yq '.digitalocean.size // "s-1vcpu-2gb"' "$CONFIG_FILE")"
DO_REGION="$(yq '.digitalocean.region // "nyc3"' "$CONFIG_FILE")"
DROPLET_NAME="$(yq '.digitalocean.dropletName // "sovereign-1"' "$CONFIG_FILE")"
SSH_KEY_PATH="${SOVEREIGN_SSH_KEY:-$(yq '.sshKeyPath // "~/.ssh/id_ed25519"' "$CONFIG_FILE")}"
DOMAIN="${SOVEREIGN_DOMAIN:-$(yq '.domain' "$CONFIG_FILE")}"
K3S_VERSION="$(yq '.k3sVersion // "v1.29.4+k3s1"' "$CONFIG_FILE")"

if [[ -z "$DOMAIN" || "$DOMAIN" == "null" ]]; then
  echo "ERROR: 'domain' is required in config.yaml" >&2
  exit 1
fi

# Expand tilde in SSH key path
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
  echo "ERROR: SSH key not found: $SSH_KEY_PATH" >&2
  exit 1
fi

echo "==> [DigitalOcean] Provisioning Droplet"
echo "    Size:    $DO_SIZE"
echo "    Region:  $DO_REGION"
echo "    Name:    $DROPLET_NAME"
echo ""

# Upload SSH key to DigitalOcean (idempotent by fingerprint)
SSH_KEY_PUB="${SSH_KEY_PATH}.pub"
if [[ ! -f "$SSH_KEY_PUB" ]]; then
  echo "ERROR: SSH public key not found: $SSH_KEY_PUB" >&2
  exit 1
fi

SSH_FINGERPRINT="$(ssh-keygen -lf "$SSH_KEY_PUB" | awk '{print $2}')"
DO_KEY_ID="$(doctl compute ssh-key list --format FingerPrint,ID --no-header 2>/dev/null \
  | grep "$SSH_FINGERPRINT" | awk '{print $2}' || true)"

if [[ -z "$DO_KEY_ID" ]]; then
  echo "==> Uploading SSH key to DigitalOcean..."
  DO_KEY_ID="$(doctl compute ssh-key import "sovereign-key" \
    --public-key-file "$SSH_KEY_PUB" \
    --format ID \
    --no-header)"
  echo "==> SSH key imported: $DO_KEY_ID"
else
  echo "==> SSH key already in DigitalOcean: $DO_KEY_ID"
fi

# Check if Droplet already exists
EXISTING_ID="$(doctl compute droplet list --format Name,ID --no-header 2>/dev/null \
  | grep "^${DROPLET_NAME} " | awk '{print $2}' || true)"

if [[ -n "$EXISTING_ID" ]]; then
  echo "==> Droplet '$DROPLET_NAME' already exists: $EXISTING_ID"
  DROPLET_ID="$EXISTING_ID"
else
  echo "==> Creating Droplet..."
  DROPLET_ID="$(doctl compute droplet create "$DROPLET_NAME" \
    --image ubuntu-22-04-x64 \
    --size "$DO_SIZE" \
    --region "$DO_REGION" \
    --ssh-keys "$DO_KEY_ID" \
    --wait \
    --format ID \
    --no-header)"
  echo "==> Droplet created: $DROPLET_ID"
fi

# Get public IP
SERVER_IP="$(doctl compute droplet get "$DROPLET_ID" \
  --format PublicIPv4 \
  --no-header)"

if [[ -z "$SERVER_IP" || "$SERVER_IP" == "null" ]]; then
  echo "==> Waiting for Droplet IP to be assigned..."
  for i in $(seq 1 20); do
    SERVER_IP="$(doctl compute droplet get "$DROPLET_ID" \
      --format PublicIPv4 \
      --no-header 2>/dev/null || echo "")"
    if [[ -n "$SERVER_IP" && "$SERVER_IP" != "null" ]]; then
      break
    fi
    echo "    Waiting for IP (attempt $i/20)..."
    sleep 5
  done
fi

echo "==> Droplet IP: $SERVER_IP"

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${SSH_KEY_PATH}")

# Wait for SSH to be ready
echo "==> Waiting for SSH to be ready..."
for i in $(seq 1 30); do
  if ssh "${SSH_OPTS[@]}" "root@${SERVER_IP}" "echo ok" &>/dev/null; then
    break
  fi
  echo "    SSH not ready yet (attempt $i/30)..."
  sleep 10
done

# Check if K3s is already installed
if ssh "${SSH_OPTS[@]}" "root@${SERVER_IP}" "command -v k3s" &>/dev/null; then
  echo "==> K3s already installed, skipping."
else
  echo "==> Installing K3s ${K3S_VERSION}..."
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "root@${SERVER_IP}" \
    "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} sh -s - \
      --write-kubeconfig-mode 644 \
      --tls-san ${SERVER_IP} \
      --tls-san ${DOMAIN}"

  echo "==> Waiting for K3s to start..."
  for i in $(seq 1 20); do
    if ssh "${SSH_OPTS[@]}" "root@${SERVER_IP}" "kubectl get nodes" &>/dev/null; then
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
KUBECONFIG_FILE="${KUBECONFIG_DIR}/sovereign-do.yaml"

ssh "${SSH_OPTS[@]}" "root@${SERVER_IP}" "cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/${SERVER_IP}/g" \
  > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"
echo "==> kubeconfig saved to: $KUBECONFIG_FILE"
echo ""
echo "    To use:  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""

# Cost estimate
echo "================================================================"
echo "  ESTIMATED MONTHLY COST (DigitalOcean)"
echo "================================================================"
case "$DO_SIZE" in
  s-1vcpu-1gb)  echo "  ~\$6/month   (s-1vcpu-1gb  — 1 vCPU, 1GB RAM)" ;;
  s-1vcpu-2gb)  echo "  ~\$12/month  (s-1vcpu-2gb  — 1 vCPU, 2GB RAM)  [default]" ;;
  s-2vcpu-2gb)  echo "  ~\$18/month  (s-2vcpu-2gb  — 2 vCPU, 2GB RAM)" ;;
  s-2vcpu-4gb)  echo "  ~\$24/month  (s-2vcpu-4gb  — 2 vCPU, 4GB RAM)  [recommended]" ;;
  s-4vcpu-8gb)  echo "  ~\$48/month  (s-4vcpu-8gb  — 4 vCPU, 8GB RAM)" ;;
  *)            echo "  See https://www.digitalocean.com/pricing for $DO_SIZE pricing" ;;
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
