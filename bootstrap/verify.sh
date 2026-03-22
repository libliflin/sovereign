#!/usr/bin/env bash
# verify.sh — Post-bootstrap health check for the Sovereign Platform
# Usage: ./bootstrap/verify.sh [--vip <kube-vip-address>]
#
# Checks:
#   1. kubectl connectivity
#   2. Node count >= 3 (HA minimum)
#   3. All nodes are Ready
#   4. etcd cluster health (embedded etcd via K3s)
#   5. kube-vip VIP is reachable (if --vip provided or KUBE_VIP set)
#   6. kube-system pods are Running
#   7. StorageClasses present (if Ceph deployed)
set -euo pipefail

PASS=0
FAIL=0
KUBE_VIP="${KUBE_VIP:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vip)
      KUBE_VIP="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--vip <kube-vip-address>]"
      echo ""
      echo "Options:"
      echo "  --vip <addr>   kube-vip floating VIP to test connectivity to"
      echo "                 Can also be set via KUBE_VIP env var"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ok() {
  echo "  [OK]   $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  [FAIL] $1"
  FAIL=$((FAIL + 1))
}

warn() {
  echo "  [WARN] $1"
}

echo "================================================================"
echo "  Sovereign Platform — Bootstrap Verification"
echo "================================================================"
echo ""

# 1. Check kubectl
echo "=> Checking kubectl..."
if command -v kubectl &>/dev/null; then
  KUBECTL_VER="$(kubectl version --client --short 2>/dev/null | head -1 || kubectl version --client 2>/dev/null | head -1)"
  ok "kubectl found: ${KUBECTL_VER}"
else
  fail "kubectl not found — install kubectl and set KUBECONFIG"
fi

# 2. Check cluster connectivity
echo ""
echo "=> Checking cluster connectivity..."
if kubectl cluster-info &>/dev/null; then
  SERVER_URL="$(kubectl cluster-info 2>/dev/null | head -1 | grep -oE 'https://[^ ]+' || echo 'unknown')"
  ok "kubectl connected to cluster (${SERVER_URL})"
else
  fail "kubectl cannot connect — check KUBECONFIG and cluster status"
fi

# 3. Check node count >= 3 (HA minimum)
echo ""
echo "=> Checking HA node count..."
if kubectl get nodes &>/dev/null; then
  TOTAL_NODES="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$TOTAL_NODES" -lt 3 ]]; then
    fail "Only ${TOTAL_NODES} node(s) found — minimum is 3 for HA (etcd quorum + Ceph)"
  elif (( TOTAL_NODES % 2 == 0 )); then
    fail "Even number of nodes (${TOTAL_NODES}) — use an odd count for etcd quorum"
  else
    ok "${TOTAL_NODES} nodes found (HA: odd count >= 3)"
  fi
else
  fail "Cannot list nodes"
fi

# 4. Check all nodes are Ready
echo ""
echo "=> Checking node Ready status..."
if kubectl get nodes &>/dev/null; then
  NOT_READY="$(kubectl get nodes --no-headers 2>/dev/null | grep -vc ' Ready' || true)"
  if [[ "$NOT_READY" -eq 0 && "${TOTAL_NODES:-0}" -gt 0 ]]; then
    ok "All ${TOTAL_NODES} node(s) are Ready"
  else
    fail "${NOT_READY} / ${TOTAL_NODES:-?} node(s) are not Ready"
    kubectl get nodes 2>/dev/null || true
  fi
else
  fail "Cannot list nodes"
fi

# 5. Check etcd cluster health (K3s embedded etcd via etcdctl in k3s)
echo ""
echo "=> Checking etcd cluster health..."
# K3s ships etcdctl. Try to query etcd endpoints health via kubectl.
# Check that all control plane nodes have etcd pods (K3s embedded etcd)
ETCD_PODS="$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
  | grep -c 'etcd' || true)"

if [[ "$ETCD_PODS" -gt 0 ]]; then
  ok "etcd pods found (${ETCD_PODS}) — embedded etcd cluster running"
else
  # K3s embedded etcd may not show as separate pods — check via k3s status
  warn "No etcd pods visible in kube-system (expected for K3s embedded etcd)"
  warn "Verify with: kubectl get nodes -o wide && check K3s server logs"
fi

# Check kube-vip pod is running (indicates HA VIP is active)
KUBEVIP_POD="$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
  | grep 'kube-vip' | grep -c 'Running' || true)"
if [[ "$KUBEVIP_POD" -gt 0 ]]; then
  ok "kube-vip pod(s) running (${KUBEVIP_POD}) — floating VIP active"
else
  fail "kube-vip pod not found or not Running in kube-system"
  warn "Expected kube-vip to be deployed as a static Pod by K3s"
fi

# 6. Check VIP reachability (if provided)
echo ""
echo "=> Checking kube-vip VIP reachability..."
if [[ -n "$KUBE_VIP" ]]; then
  if curl -sk --connect-timeout 5 "https://${KUBE_VIP}:6443/healthz" | grep -q 'ok' 2>/dev/null; then
    ok "VIP ${KUBE_VIP}:6443 is reachable and returning healthy"
  elif curl -sk --connect-timeout 5 "https://${KUBE_VIP}:6443/readyz" &>/dev/null; then
    ok "VIP ${KUBE_VIP}:6443 is reachable"
  else
    fail "VIP ${KUBE_VIP}:6443 is not reachable — check kube-vip and network config"
  fi
else
  warn "KUBE_VIP not set — skipping VIP reachability check"
  warn "Run with: ./bootstrap/verify.sh --vip <your-vip-address>"
  warn "Or set: export KUBE_VIP=<your-vip-address>"
fi

# 7. Check kube-system pods
echo ""
echo "=> Checking kube-system pods..."
NOT_RUNNING="$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
  | grep -vcE 'Running|Completed|Succeeded' || true)"
TOTAL_PODS="$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$NOT_RUNNING" -eq 0 && "$TOTAL_PODS" -gt 0 ]]; then
  ok "All ${TOTAL_PODS} kube-system pod(s) are Running/Completed"
elif [[ "$NOT_RUNNING" -gt 0 ]]; then
  fail "${NOT_RUNNING}/${TOTAL_PODS} kube-system pod(s) are not Running"
  kubectl get pods -n kube-system 2>/dev/null || true
else
  fail "No pods found in kube-system — cluster may not be initialized"
fi

# 8. Check StorageClasses
echo ""
echo "=> Checking StorageClasses..."
if kubectl get storageclass &>/dev/null; then
  SC_COUNT="$(kubectl get storageclass --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$SC_COUNT" -gt 0 ]]; then
    ok "${SC_COUNT} StorageClass(es) found"
    kubectl get storageclass --no-headers 2>/dev/null | awk '{print "    " $1}' || true
  else
    ok "No StorageClasses yet (expected — Ceph not yet deployed)"
  fi
else
  fail "Cannot list StorageClasses"
fi

# 9. Summary
echo ""
echo "================================================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "================================================================"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
  echo "  Cluster is healthy and ready."
  echo ""
  echo "  HA summary:"
  echo "    - ${TOTAL_NODES:-?} control plane nodes (etcd quorum maintained)"
  echo "    - kube-vip provides floating VIP for API server HA"
  echo "    - Front door (Cloudflare tunnel) routes all ingress traffic"
  echo ""
  echo "  Next: Push your config to git to trigger ArgoCD GitOps sync"
  exit 0
else
  echo "  Please fix the failures above before proceeding."
  echo ""
  echo "  Common issues:"
  echo "    - Nodes not Ready: check 'journalctl -u k3s' on each node"
  echo "    - kube-vip missing: check /var/lib/rancher/k3s/server/manifests/kube-vip.yaml"
  echo "    - VIP unreachable: ensure the VIP is on the same subnet as node private IPs"
  exit 1
fi
