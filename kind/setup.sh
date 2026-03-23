#!/usr/bin/env bash
# kind/setup.sh — Create and configure a sovereign-test kind cluster
# with Cilium CNI and local-path storage provisioner.
#
# Usage:
#   ./kind/setup.sh              # single-node (default, fast)
#   ./kind/setup.sh --ha         # 3-node HA cluster
#   ./kind/setup.sh --destroy    # delete the cluster
#   ./kind/setup.sh --status     # check cluster health
#   ./kind/setup.sh --dry-run    # print what would happen, no changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLUSTER_NAME="sovereign-test"
HA_CLUSTER_NAME="sovereign-ha"
MODE="single"
DRY_RUN=false

# ── Argument parsing ──────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --ha)       MODE="ha"; CLUSTER_NAME="$HA_CLUSTER_NAME" ;;
    --destroy)  MODE="destroy" ;;
    --status)   MODE="status" ;;
    --dry-run)  DRY_RUN=true ;;
    --help)
      echo "Usage: $0 [--ha] [--destroy] [--status] [--dry-run]"
      echo "  (no flags)  Create single-node cluster (fast, ~1.5GB RAM)"
      echo "  --ha        Create 3-node HA cluster (requires 8GB+ Docker RAM)"
      echo "  --destroy   Delete the cluster"
      echo "  --status    Check cluster health"
      echo "  --dry-run   Print what would happen without making changes"
      exit 0
      ;;
  esac
done

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# ── Preflight checks ──────────────────────────────────────────────────────────

echo "==> Pre-flight checks"

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found. Install Docker Desktop." >&2; exit 1
fi

if ! docker info &>/dev/null; then
  echo "ERROR: Docker daemon is not running. Start Docker Desktop." >&2; exit 1
fi

if ! command -v kind &>/dev/null; then
  echo "ERROR: kind not found. Run: brew install kind" >&2; exit 1
fi

if ! command -v kubectl &>/dev/null; then
  echo "ERROR: kubectl not found. Run: brew install kubectl" >&2; exit 1
fi

if ! command -v helm &>/dev/null; then
  echo "ERROR: helm not found. Run: brew install helm" >&2; exit 1
fi

# Check Docker memory — warn if too low for the chosen mode
DOCKER_MEM_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
DOCKER_MEM_GB=$(( DOCKER_MEM_BYTES / 1073741824 ))

if [[ "$MODE" == "ha" ]] && [[ "$DOCKER_MEM_GB" -lt 8 ]]; then
  echo ""
  echo "WARNING: Docker Desktop has ${DOCKER_MEM_GB}GB RAM allocated."
  echo "         The HA cluster needs >= 8GB to run comfortably."
  echo "         Go to: Docker Desktop → Settings → Resources → Memory"
  echo "         Set to at least 10GB, then restart Docker Desktop."
  echo ""
  echo "         Continuing anyway — it may OOM-kill pods. Use --ha with caution."
  echo ""
elif [[ "$MODE" == "single" ]] && [[ "$DOCKER_MEM_GB" -lt 4 ]]; then
  echo "WARNING: Docker Desktop has only ${DOCKER_MEM_GB}GB RAM. Recommend >= 4GB." >&2
fi

echo "  docker:  running (${DOCKER_MEM_GB}GB allocated)"
echo "  kind:    $(kind version)"
echo "  kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"
echo "  helm:    $(helm version --short)"

# ── Status mode ───────────────────────────────────────────────────────────────

if [[ "$MODE" == "status" ]]; then
  echo ""
  echo "==> Cluster status"
  if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    kubectl --context "kind-${CLUSTER_NAME}" get nodes -o wide
    echo ""
    kubectl --context "kind-${CLUSTER_NAME}" get pods -A --field-selector=status.phase!=Running 2>/dev/null \
      | head -20 || true
  else
    echo "No cluster named '$CLUSTER_NAME' found."
    echo "Existing clusters: $(kind get clusters 2>/dev/null || echo 'none')"
  fi
  exit 0
fi

# ── Destroy mode ──────────────────────────────────────────────────────────────

if [[ "$MODE" == "destroy" ]]; then
  echo "==> Deleting cluster: $CLUSTER_NAME"
  if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    run kind delete cluster --name "$CLUSTER_NAME"
    echo "Cluster '$CLUSTER_NAME' deleted."
  else
    echo "No cluster named '$CLUSTER_NAME' found. Nothing to do."
  fi
  exit 0
fi

# ── Create cluster ────────────────────────────────────────────────────────────

CONFIG_FILE="$SCRIPT_DIR/sovereign-${MODE}.yaml"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE" >&2; exit 1
fi

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "==> Cluster '$CLUSTER_NAME' already exists — skipping creation."
  echo "    To recreate: $0 --destroy && $0"
else
  echo "==> Creating kind cluster: $CLUSTER_NAME (mode: $MODE)"
  # NOTE: no --wait here. With disableDefaultCNI:true the node stays NotReady
  # until Cilium is installed. We wait explicitly after Cilium is up.
  run kind create cluster \
    --name "$CLUSTER_NAME" \
    --config "$CONFIG_FILE"
fi

[[ "$DRY_RUN" == "true" ]] && { echo "[dry-run] Stopping here."; exit 0; }

run kubectl config use-context "kind-${CLUSTER_NAME}"

echo ""
echo "==> Nodes"
kubectl get nodes -o wide

# ── Install Cilium CNI ────────────────────────────────────────────────────────

echo ""
echo "==> Installing Cilium CNI (required — kindnet is disabled)"

# Cilium CLI preferred; fall back to helm if not available
if command -v cilium &>/dev/null; then
  run cilium install \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=kind-"${CLUSTER_NAME}"-control-plane \
    --set k8sServicePort=6443 \
    --wait

  echo "==> Cilium status"
  run cilium status --wait
else
  echo "  (cilium CLI not found — installing via helm)"
  run helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
  run helm repo update cilium

  run helm upgrade --install cilium cilium/cilium \
    --namespace kube-system \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost="$(kubectl get node "${CLUSTER_NAME}-control-plane" \
      -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')" \
    --set k8sServicePort=6443 \
    --set image.pullPolicy=IfNotPresent \
    --wait \
    --timeout 5m
fi

# ── Install local-path storage provisioner ────────────────────────────────────
# Replaces Rook/Ceph for CI — hostPath-backed PVCs, good enough for smoke tests.

echo ""
echo "==> Installing local-path storage provisioner (CI substitute for Rook/Ceph)"
run kubectl apply -f \
  https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

run kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "  Storage class 'local-path' set as default."

# ── Wait for cluster to settle ────────────────────────────────────────────────

echo ""
echo "==> Waiting for all system pods to be Running"
run kubectl wait --for=condition=Ready pods \
  --all -n kube-system \
  --timeout=3m \
  2>/dev/null || true

# ── Final status ──────────────────────────────────────────────────────────────

echo ""
echo "==> Cluster ready"
kubectl get nodes -o wide
echo ""
kubectl get storageclass
echo ""
echo "  Context:  kind-${CLUSTER_NAME}"
echo "  Ingress:  http://localhost:8080  (maps to NodePort 30080)"
echo "            https://localhost:8443 (maps to NodePort 30443)"
echo ""
echo "Next steps:"
echo "  Smoke test a chart:  helm install test-release charts/vault/ --dry-run"
echo "  Real install:        helm install test-release charts/vault/ -n vault --create-namespace"
echo "  Check pods:          kubectl get pods -A"
echo "  Teardown:            ./kind/setup.sh --destroy"
