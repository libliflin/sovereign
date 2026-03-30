#!/usr/bin/env bash
# cluster/kind/install-foundations.sh
#
# KIND-001b: Install Cilium CNI, cert-manager, sealed-secrets, local-path
# StorageClass, and MinIO into an existing kind cluster.
#
# Assumes: cluster was created by cluster/kind/bootstrap.sh (KIND-001a).
#
# Usage:
#   ./cluster/kind/install-foundations.sh [--cluster-name NAME] [--dry-run]

set -euo pipefail

CLUSTER_NAME="sovereign-test"
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIND_CHARTS="${SCRIPT_DIR}/charts"

log() { echo "==> $*"; }

usage() {
  echo "Usage: $0 [--cluster-name NAME] [--dry-run]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=true;      shift   ;;
    --help)         usage ;;
    *) echo "Unknown flag: $1"; usage ;;
  esac
done

CONTEXT="kind-${CLUSTER_NAME}"

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN — no cluster changes will be made"
  log "Would install into context: ${CONTEXT}"
  log "  1. Cilium CNI (kube-proxy replacement disabled for kind compat)"
  log "  2. Remove kindnet DaemonSet"
  log "  3. cert-manager (with self-signed ClusterIssuer)"
  log "  4. sealed-secrets"
  log "  5. local-path StorageClass (rename default from 'standard' to 'local-path')"
  log "  6. MinIO (via bitnami helm chart, bootstrap window)"
  exit 0
fi

log "Installing platform foundations into ${CONTEXT}"

# ── 1. Install Cilium ─────────────────────────────────────────────────────────
log "Installing Cilium..."
# Use kubeProxyReplacement=false for kind compat (kube-proxy is running)
helm upgrade --install cilium "${KIND_CHARTS}/cilium/" \
  --namespace kube-system \
  --kube-context "${CONTEXT}" \
  --set cilium.kubeProxyReplacement=false \
  --set cilium.encryption.enabled=false \
  --set cilium.hubble.enabled=false \
  --set cilium.hubble.relay.enabled=false \
  --set cilium.hubble.ui.enabled=false \
  --wait --timeout 120s

# Remove kindnet (Cilium takes over)
log "Removing kindnet DaemonSet..."
kubectl delete daemonset kindnet -n kube-system --context "${CONTEXT}" 2>/dev/null || true
log "Waiting for Cilium pods to stabilize..."
kubectl rollout status daemonset/cilium -n kube-system --context "${CONTEXT}" --timeout=90s

# In kind, the default-deny-all NetworkPolicy breaks CoreDNS (blocks API server egress).
# Remove the restrictive policies; kind is a local dev environment, not production.
log "Removing kind-incompatible NetworkPolicies from kube-system..."
kubectl delete networkpolicy default-deny-all allow-dns-egress allow-same-namespace \
  -n kube-system --context "${CONTEXT}" 2>/dev/null || true

# Restart CoreDNS so new pods get Cilium-managed networking
log "Restarting CoreDNS..."
kubectl rollout restart deployment/coredns -n kube-system --context "${CONTEXT}"
kubectl rollout status deployment/coredns -n kube-system --context "${CONTEXT}" --timeout=90s

# ── 2. Install cert-manager ───────────────────────────────────────────────────
# Two-step: install cert-manager CRDs + core first (selfSigned.enabled=false),
# then upgrade to add ClusterIssuers once CRDs are registered.
log "Installing cert-manager (step 1: core + CRDs)..."
helm dependency update "${KIND_CHARTS}/cert-manager/" 2>&1 | tail -3
helm upgrade --install cert-manager "${KIND_CHARTS}/cert-manager/" \
  --namespace cert-manager \
  --kube-context "${CONTEXT}" \
  --create-namespace \
  --set selfSigned.enabled=false \
  --wait --timeout 120s
log "Waiting for cert-manager CRDs to be established..."
kubectl wait --for=condition=Established crd/clusterissuers.cert-manager.io \
  --context "${CONTEXT}" --timeout=60s
log "Installing cert-manager (step 2: ClusterIssuers)..."
helm upgrade cert-manager "${KIND_CHARTS}/cert-manager/" \
  --namespace cert-manager \
  --kube-context "${CONTEXT}" \
  --set selfSigned.enabled=true \
  --wait --timeout 120s
log "cert-manager ready."

# ── 3. Install sealed-secrets ─────────────────────────────────────────────────
log "Installing sealed-secrets..."
helm upgrade --install sealed-secrets "${KIND_CHARTS}/sealed-secrets/" \
  --namespace sealed-secrets \
  --kube-context "${CONTEXT}" \
  --create-namespace \
  --wait --timeout 120s
log "sealed-secrets ready."

# ── 4. Create local-path StorageClass ────────────────────────────────────────
# kind already has local-path provisioner. Rename the default SC to 'local-path'.
log "Configuring local-path StorageClass..."
kubectl annotate storageclass standard \
  storageclass.kubernetes.io/is-default-class- \
  --context "${CONTEXT}" 2>/dev/null || true
kubectl apply --context "${CONTEXT}" -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
YAML
log "local-path StorageClass created."

# ── 5. Install MinIO ──────────────────────────────────────────────────────────
log "Installing MinIO..."
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update bitnami 2>&1 | tail -2
helm upgrade --install minio bitnami/minio \
  --version 14.6.2 \
  --namespace minio \
  --kube-context "${CONTEXT}" \
  --create-namespace \
  --set auth.rootUser=minioadmin \
  --set auth.rootPassword=minioadmin \
  --set mode=standalone \
  --set replicaCount=1 \
  --set persistence.storageClass=local-path \
  --set persistence.size=1Gi \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=256Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=1Gi \
  --wait --timeout 120s
log "MinIO ready."

log ""
log "Platform foundations installed successfully in ${CONTEXT}:"
kubectl get pods -n kube-system -l k8s-app=cilium --context "${CONTEXT}"
kubectl get pods -n cert-manager --context "${CONTEXT}"
kubectl get pods -n sealed-secrets --context "${CONTEXT}"
kubectl get pods -n minio --context "${CONTEXT}"
kubectl get storageclass --context "${CONTEXT}"
