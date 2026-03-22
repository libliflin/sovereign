#!/usr/bin/env bash
# verify.sh — Post-bootstrap health check for the Sovereign Platform
# Usage: ./bootstrap/verify.sh
set -euo pipefail

PASS=0
FAIL=0

ok() {
  echo "  [OK]  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  [FAIL] $1"
  FAIL=$((FAIL + 1))
}

echo "================================================================"
echo "  Sovereign Platform — Bootstrap Verification"
echo "================================================================"
echo ""

# 1. Check kubectl
echo "=> Checking kubectl..."
if command -v kubectl &>/dev/null; then
  ok "kubectl found: $(kubectl version --client --short 2>/dev/null | head -1)"
else
  fail "kubectl not found — install kubectl and set KUBECONFIG"
fi

# 2. Check cluster connectivity
echo "=> Checking cluster connectivity..."
if kubectl cluster-info &>/dev/null; then
  ok "kubectl can connect to the cluster"
else
  fail "kubectl cannot connect — check KUBECONFIG and cluster status"
fi

# 3. Check nodes are Ready
echo "=> Checking nodes..."
if kubectl get nodes &>/dev/null; then
  NOT_READY="$(kubectl get nodes --no-headers 2>/dev/null | grep -vc ' Ready' || true)"
  TOTAL_NODES="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$NOT_READY" -eq 0 && "$TOTAL_NODES" -gt 0 ]]; then
    ok "All $TOTAL_NODES node(s) are Ready"
  else
    fail "$NOT_READY / $TOTAL_NODES node(s) are not Ready"
    kubectl get nodes
  fi
else
  fail "Cannot list nodes"
fi

# 4. Check kube-system pods
echo "=> Checking kube-system pods..."
NOT_RUNNING="$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
  | grep -vcE 'Running|Completed|Succeeded' || true)"
if [[ "$NOT_RUNNING" -eq 0 ]]; then
  ok "All kube-system pods are Running/Completed"
else
  fail "$NOT_RUNNING kube-system pod(s) are not Running"
  kubectl get pods -n kube-system
fi

# 5. Check StorageClass (if Ceph is expected)
echo "=> Checking StorageClasses..."
if kubectl get storageclass &>/dev/null; then
  SC_COUNT="$(kubectl get storageclass --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$SC_COUNT" -gt 0 ]]; then
    ok "$SC_COUNT StorageClass(es) found"
  else
    ok "No StorageClasses yet (expected — Ceph not installed in Phase 1)"
  fi
else
  fail "Cannot list StorageClasses"
fi

# 6. Summary
echo ""
echo "================================================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "================================================================"

if [[ "$FAIL" -eq 0 ]]; then
  echo "  Cluster is healthy and ready for bootstrap Phase 1."
  echo ""
  echo "  Next: Run the bootstrap Phase 1 scripts to install:"
  echo "    - Cilium (CNI)"
  echo "    - Crossplane"
  echo "    - cert-manager"
  echo "    - Sealed Secrets"
  exit 0
else
  echo "  Please fix the failures above before proceeding."
  exit 1
fi
