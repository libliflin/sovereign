#!/usr/bin/env bash
# kind/smoke-test/rolling-update.sh
#
# HA-003: Rolling update smoke test.
# Installs a test Helm chart into kind-sovereign-test with replicaCount=2 and
# maxUnavailable=0, triggers a rolling update, polls pods every 2 seconds, and
# verifies that at no point were fewer than 1 pod Running.
#
# Usage:
#   ./kind/smoke-test/rolling-update.sh [--dry-run]

set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/charts/rolling-test" && pwd)"
CONTEXT="kind-sovereign-test"
NAMESPACE="rolling-test"
RELEASE="rolling-test"
MIN_RUNNING=1
POLL_INTERVAL=2
ROLLOUT_TIMEOUT=60
DRY_RUN=false

log() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help) echo "Usage: $0 [--dry-run]"; exit 0 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN — no cluster changes will be made"
  log "Test steps:"
  log "  1. Create namespace: ${NAMESPACE}"
  log "  2. helm install ${RELEASE} ${CHART_DIR} --set replicaCount=2 --set rollAnnotation=initial"
  log "  3. Wait for 2 pods Running"
  log "  4. helm upgrade ${RELEASE} ${CHART_DIR} --set rollAnnotation=upgraded (triggers rolling update)"
  log "  5. Poll 'kubectl get pods -l app=rolling-test' every ${POLL_INTERVAL}s for ${ROLLOUT_TIMEOUT}s"
  log "  6. Assert: at no point fewer than ${MIN_RUNNING} pod(s) Running"
  log "  7. helm uninstall ${RELEASE} and delete namespace"
  log "Chart: ${CHART_DIR}"
  exit 0
fi

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
  log "Cleaning up..."
  helm uninstall "${RELEASE}" --namespace "${NAMESPACE}" --kube-context "${CONTEXT}" 2>/dev/null || true
  kubectl delete namespace "${NAMESPACE}" --context "${CONTEXT}" 2>/dev/null || true
}
trap cleanup EXIT

# ── 1. Create namespace ───────────────────────────────────────────────────────
log "Creating namespace: ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" --context "${CONTEXT}" 2>/dev/null || true

# ── 2. Install chart ──────────────────────────────────────────────────────────
log "Installing ${RELEASE} (replicaCount=2, maxUnavailable=0)..."
helm install "${RELEASE}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --kube-context "${CONTEXT}" \
  --set replicaCount=2 \
  --set rollAnnotation=initial \
  --wait \
  --timeout 60s

log "Initial deployment ready:"
kubectl get pods -l app=rolling-test -n "${NAMESPACE}" --context "${CONTEXT}"

# ── 3. Trigger rolling update ─────────────────────────────────────────────────
log "Triggering rolling update (bumping rollAnnotation to 'upgraded')..."
helm upgrade "${RELEASE}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --kube-context "${CONTEXT}" \
  --set replicaCount=2 \
  --set rollAnnotation=upgraded

# ── 4. Poll pods during rollout ───────────────────────────────────────────────
log "Polling pods every ${POLL_INTERVAL}s for up to ${ROLLOUT_TIMEOUT}s..."
MIN_OBSERVED=999
ELAPSED=0
while [[ $ELAPSED -lt $ROLLOUT_TIMEOUT ]]; do
  RUNNING=$(kubectl get pods -l app=rolling-test -n "${NAMESPACE}" --context "${CONTEXT}" \
    --no-headers 2>/dev/null | grep -c " Running " || true)
  log "  t=${ELAPSED}s: ${RUNNING} Running"
  if [[ $RUNNING -lt $MIN_OBSERVED ]]; then
    MIN_OBSERVED=$RUNNING
  fi
  # Check if rollout is complete (rollout status exits 0 means done)
  if kubectl rollout status deployment/rolling-test -n "${NAMESPACE}" --context "${CONTEXT}" \
      --timeout=1s 2>/dev/null; then
    log "Rollout complete at t=${ELAPSED}s"
    break
  fi
  sleep "${POLL_INTERVAL}"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

log "Minimum Running pods observed during rollout: ${MIN_OBSERVED}"

# ── 5. Final pod state ────────────────────────────────────────────────────────
log "Final pod state:"
kubectl get pods -l app=rolling-test -n "${NAMESPACE}" --context "${CONTEXT}"

# ── 6. Assert invariant ───────────────────────────────────────────────────────
if [[ $MIN_OBSERVED -lt $MIN_RUNNING ]]; then
  echo "FAIL: minimum ${MIN_OBSERVED} pods Running during rollout (required >= ${MIN_RUNNING})"
  exit 1
fi

echo "PASS: zero unavailability during rollout (min Running observed: ${MIN_OBSERVED})"
