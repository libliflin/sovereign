#!/usr/bin/env bash
# bootstrap.sh — Main entry point for Sovereign Platform bootstrap
# Usage: ./bootstrap/bootstrap.sh [--config <path>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--config <path-to-config.yaml>]"
      echo "Default config: bootstrap/config.yaml"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Verify config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE" >&2
  echo "  Copy bootstrap/config.yaml.example to bootstrap/config.yaml and fill it in." >&2
  exit 1
fi

# Require yq for YAML parsing
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with: brew install yq  (or snap install yq)" >&2
  exit 1
fi

echo "==> Reading config: $CONFIG_FILE"

# Read required fields
PROVIDER="$(yq '.provider' "$CONFIG_FILE")"
DOMAIN="$(yq '.domain' "$CONFIG_FILE")"

if [[ -z "$PROVIDER" || "$PROVIDER" == "null" ]]; then
  echo "ERROR: 'provider' is required in config.yaml" >&2
  exit 1
fi

if [[ -z "$DOMAIN" || "$DOMAIN" == "null" ]]; then
  echo "ERROR: 'domain' is required in config.yaml" >&2
  exit 1
fi

# Read and validate node count — must be odd and >= 3 (HA requirement)
NODE_COUNT="$(yq '.nodes.count // 1' "$CONFIG_FILE")"
if [[ "$NODE_COUNT" -lt 3 ]]; then
  echo "ERROR: nodes.count must be >= 3. Single-node and 2-node clusters are not supported." >&2
  echo "  Sovereign requires an odd number of nodes >= 3 for etcd quorum and Ceph quorum." >&2
  exit 1
fi
if (( NODE_COUNT % 2 == 0 )); then
  echo "ERROR: nodes.count must be odd (got $NODE_COUNT). Even-node clusters break etcd quorum." >&2
  exit 1
fi

echo "==> Provider: $PROVIDER"
echo "==> Domain:   $DOMAIN"
echo "==> Nodes:    $NODE_COUNT"

# Read front door provider (default: cloudflare)
FRONT_DOOR="$(yq '.frontDoor // "cloudflare"' "$CONFIG_FILE")"
echo "==> FrontDoor: $FRONT_DOOR"
echo ""

# Route to the appropriate provider script
PROVIDER_SCRIPT="${SCRIPT_DIR}/providers/${PROVIDER}.sh"

if [[ ! -f "$PROVIDER_SCRIPT" ]]; then
  echo "ERROR: No provider script found for '$PROVIDER'" >&2
  echo "  Supported providers: hetzner, generic-vps, aws-ec2, digitalocean" >&2
  echo "  Expected file: $PROVIDER_SCRIPT" >&2
  exit 1
fi

# Validate and source front door implementation
FRONTDOOR_SCRIPT="${SCRIPT_DIR}/frontdoor/${FRONT_DOOR}.sh"
if [[ ! -f "$FRONTDOOR_SCRIPT" ]]; then
  echo "ERROR: No front door script found for '$FRONT_DOOR'" >&2
  echo "  Supported front doors: cloudflare, none" >&2
  echo "  Expected file: $FRONTDOOR_SCRIPT" >&2
  exit 1
fi

# Source the front door implementation (see interface.sh for the hook contract)
# shellcheck disable=SC1090
source "$FRONTDOOR_SCRIPT"

# Export config path so provider scripts can read it
export SOVEREIGN_CONFIG="$CONFIG_FILE"
export SOVEREIGN_DOMAIN="$DOMAIN"

echo "==> Delegating to provider script: $PROVIDER_SCRIPT"
echo ""

# Provider script must write node IPs (one per line) to SOVEREIGN_NODELIST
SOVEREIGN_NODELIST="${TMPDIR:-/tmp}/sovereign-nodes-$$.txt"
export SOVEREIGN_NODELIST

bash "$PROVIDER_SCRIPT"

# Read node IPs provisioned by the provider
if [[ ! -f "$SOVEREIGN_NODELIST" ]] || [[ ! -s "$SOVEREIGN_NODELIST" ]]; then
  echo "WARN: Provider did not write node list to ${SOVEREIGN_NODELIST}." >&2
  echo "  Hardening and frontdoor hooks will be skipped." >&2
  echo "  (Provider scripts write IPs via: echo \"\$IP\" >> \"\$SOVEREIGN_NODELIST\")" >&2
else
  # Build space-separated node IPs for frontdoor hooks
  SOVEREIGN_NODE_IPS=""
  while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    SOVEREIGN_NODE_IPS="${SOVEREIGN_NODE_IPS:+$SOVEREIGN_NODE_IPS }$ip"
  done < "$SOVEREIGN_NODELIST"
  export SOVEREIGN_NODE_IPS

  SSH_KEY="$(yq '.sshKeyPath' "$CONFIG_FILE")"
  SSH_KEY="${SSH_KEY/#\~/$HOME}"
  export SOVEREIGN_SSH_KEY="$SSH_KEY"

  # ── Step 1: Run base hardening on all nodes ──────────────────────────────
  echo ""
  echo "==> Running base hardening on all nodes..."
  for NODE_IP in $SOVEREIGN_NODE_IPS; do
    echo "  --> Hardening node: $NODE_IP"
    SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i "$SSH_KEY")
    ssh "${SSH_OPTS[@]}" "root@${NODE_IP}" 'bash -s' < "${SCRIPT_DIR}/hardening/base.sh"
    ssh "${SSH_OPTS[@]}" "root@${NODE_IP}" 'bash -s' < "${SCRIPT_DIR}/hardening/ssh.sh"
    ssh "${SSH_OPTS[@]}" "root@${NODE_IP}" 'bash -s' < "${SCRIPT_DIR}/hardening/kernel.sh"
  done

  # ── Step 2: Provision the front door (local) ─────────────────────────────
  echo ""
  echo "==> Provisioning front door: $FRONT_DOOR..."
  frontdoor_provision

  # ── Step 3: Install front door agent on all nodes ────────────────────────
  echo ""
  echo "==> Installing front door agent on nodes..."
  # shellcheck disable=SC2086
  frontdoor_install_agent $SOVEREIGN_NODE_IPS

  # ── Step 4: Configure DNS ────────────────────────────────────────────────
  echo ""
  echo "==> Configuring DNS via front door..."
  frontdoor_configure_dns

  # ── Step 5: Apply firewall rules using frontdoor CIDRs ───────────────────
  echo ""
  echo "==> Applying firewall rules (frontdoor_allowed_cidrs → UFW)..."
  FRONTDOOR_CIDRS="$(frontdoor_allowed_cidrs)"
  export FRONTDOOR_CIDRS

  NODE_CIDRS=""
  for ip in $SOVEREIGN_NODE_IPS; do
    NODE_CIDRS="${NODE_CIDRS:+$NODE_CIDRS
}${ip}/32"
  done
  export NODE_CIDRS

  for NODE_IP in $SOVEREIGN_NODE_IPS; do
    echo "  --> Applying firewall on node: $NODE_IP"
    SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i "$SSH_KEY")
    FRONTDOOR_CIDRS="$FRONTDOOR_CIDRS" NODE_CIDRS="$NODE_CIDRS" \
      ssh "${SSH_OPTS[@]}" "root@${NODE_IP}" 'bash -s' \
      < "${SCRIPT_DIR}/hardening/firewall.sh"
  done

  # ── Step 6: Print connection info ────────────────────────────────────────
  echo ""
  frontdoor_connection_info

  # Cleanup
  rm -f "$SOVEREIGN_NODELIST"
fi

# ── Phase 1: Install foundational platform components ──────────────────────────
echo ""
echo "==> Phase 1: Installing ArgoCD and bootstrapping App-of-Apps"
echo ""

# Resolve sovereign repo root (parent of bootstrap/)
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Require helm
if ! command -v helm &>/dev/null; then
  echo "ERROR: 'helm' is required. Install from https://helm.sh/docs/intro/install/" >&2
  exit 1
fi

# Require kubectl
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: 'kubectl' is required. Install from https://kubernetes.io/docs/tasks/tools/" >&2
  exit 1
fi

# Add ArgoCD Helm repo
echo "==> Adding argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

# Install ArgoCD into the argocd namespace
echo "==> Installing ArgoCD..."
helm dependency update "${REPO_ROOT}/charts/argocd"
helm upgrade --install argocd "${REPO_ROOT}/charts/argocd" \
  --namespace argocd \
  --create-namespace \
  --set "global.domain=${SOVEREIGN_DOMAIN}" \
  --wait \
  --timeout 300s

echo "==> ArgoCD installed. Waiting for server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s

# Apply the root App-of-Apps
echo "==> Applying root App-of-Apps manifest..."
kubectl apply -f "${REPO_ROOT}/argocd-apps/root-app.yaml"

echo ""
echo "✓ Bootstrap complete!"
echo ""
echo "ArgoCD is now managing the platform via GitOps."
echo "Access ArgoCD at: https://argocd.${SOVEREIGN_DOMAIN}"
echo ""
echo "Get the initial admin password with:"
echo "  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Next steps:"
echo "  1. Configure Cloudflare wildcard DNS: *.${SOVEREIGN_DOMAIN} → <node-IP>"
echo "  2. Run: ./bootstrap/verify.sh"
echo "  3. Push your config changes to the sovereign repo to trigger GitOps sync"
