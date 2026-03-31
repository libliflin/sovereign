#!/usr/bin/env bash
# operating-room/cluster.sh — Idempotent kind cluster lifecycle.
#
# Wraps cluster/kind/bootstrap.sh and install-foundations.sh with
# start/stop/status/reset commands. The operating room loop calls
# "start" before every cycle — it's a no-op if the cluster is up.
#
# Usage:
#   ./cluster.sh start    # create cluster + foundations if missing
#   ./cluster.sh stop     # delete the kind cluster
#   ./cluster.sh status   # report cluster + foundation health
#   ./cluster.sh reset    # stop + start (clean slate)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="sovereign-test"
CONTEXT="kind-${CLUSTER_NAME}"
VALUES_FILE="${REPO_ROOT}/cluster-values.yaml"

log() { echo "  [cluster] $*"; }

cluster_exists() {
    kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"
}

foundations_installed() {
    kubectl --context "$CONTEXT" get pods -n kube-system \
        -l k8s-app=cilium -o name 2>/dev/null | grep -q .
}

# ---------------------------------------------------------------------------
cmd_start() {
    if cluster_exists; then
        log "Cluster '$CLUSTER_NAME' already exists."
    else
        log "Creating cluster '$CLUSTER_NAME' ..."
        "${REPO_ROOT}/cluster/kind/bootstrap.sh" \
            --cluster-name "$CLUSTER_NAME" \
            --output "$VALUES_FILE"
        log "Cluster created."
    fi

    # Wait for nodes to be Ready (up to 60s)
    log "Waiting for nodes ..."
    local attempts=0
    while ! kubectl --context "$CONTEXT" get nodes 2>/dev/null \
            | grep -q " Ready"; do
        attempts=$((attempts + 1))
        if (( attempts > 12 )); then
            log "ERROR: Nodes not Ready after 60s."
            return 1
        fi
        sleep 5
    done
    log "Nodes ready."

    if foundations_installed; then
        log "Foundations already installed."
    else
        log "Installing foundations (Cilium, cert-manager, sealed-secrets, MinIO) ..."
        "${REPO_ROOT}/cluster/kind/install-foundations.sh" \
            --cluster-name "$CLUSTER_NAME"
        log "Foundations installed."
    fi

    log "Cluster '$CLUSTER_NAME' is ready."
}

cmd_stop() {
    if ! cluster_exists; then
        log "No cluster '$CLUSTER_NAME' to delete."
        return 0
    fi
    log "Deleting cluster '$CLUSTER_NAME' ..."
    kind delete cluster --name "$CLUSTER_NAME"
    rm -f "$VALUES_FILE"
    log "Cluster deleted."
}

cmd_status() {
    echo "=== Cluster ==="
    if cluster_exists; then
        echo "  Name: $CLUSTER_NAME (exists)"
        echo ""
        echo "  Nodes:"
        kubectl --context "$CONTEXT" get nodes 2>/dev/null \
            | sed 's/^/    /' || echo "    (unreachable)"
        echo ""
        echo "  Foundation pods:"
        kubectl --context "$CONTEXT" get pods -A \
            -l 'app.kubernetes.io/managed-by=Helm' \
            --no-headers 2>/dev/null \
            | awk '{printf "    %-30s %-20s %s\n", $2, $1, $4}' \
            || echo "    (none)"
    else
        echo "  No cluster '$CLUSTER_NAME' found."
        echo "  Run: $0 start"
    fi
}

cmd_reset() {
    cmd_stop
    cmd_start
}

# ---------------------------------------------------------------------------
case "${1:-help}" in
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    reset)  cmd_reset ;;
    *)
        echo "Usage: $0 start | stop | status | reset"
        exit 1
        ;;
esac
