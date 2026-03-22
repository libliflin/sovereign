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

echo "==> Provider: $PROVIDER"
echo "==> Domain:   $DOMAIN"
echo ""

# Route to the appropriate provider script
PROVIDER_SCRIPT="${SCRIPT_DIR}/providers/${PROVIDER}.sh"

if [[ ! -f "$PROVIDER_SCRIPT" ]]; then
  echo "ERROR: No provider script found for '$PROVIDER'" >&2
  echo "  Supported providers: hetzner, generic-vps, aws-ec2, digitalocean" >&2
  echo "  Expected file: $PROVIDER_SCRIPT" >&2
  exit 1
fi

echo "==> Delegating to provider script: $PROVIDER_SCRIPT"
echo ""

# Export config path so provider scripts can read it
export SOVEREIGN_CONFIG="$CONFIG_FILE"
export SOVEREIGN_DOMAIN="$DOMAIN"

bash "$PROVIDER_SCRIPT"

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
