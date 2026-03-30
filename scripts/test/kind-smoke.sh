#!/usr/bin/env bash
# scripts/test/kind-smoke.sh
# Smoke test scaffold for PLATFORM-001 through PLATFORM-004.
# Encodes acceptance criteria for: cert-manager, sealed-secrets, Harbor, Keycloak.
# Usage: bash scripts/test/kind-smoke.sh [--context <kube-context>] [--dry-run]

set -euo pipefail

KUBE_CONTEXT=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

RESULTS=()

record_result() {
  local label="$1"
  local status="$2"
  RESULTS+=("${label}: ${status}")
}

kube() {
  if [[ -n "$KUBE_CONTEXT" ]]; then
    kubectl --context "$KUBE_CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

helm_ctx() {
  if [[ -n "$KUBE_CONTEXT" ]]; then
    helm --kube-context "$KUBE_CONTEXT" "$@"
  else
    helm "$@"
  fi
}

pods_all_running() {
  local namespace="$1"
  local pod_output
  pod_output=$(kube get pods -n "$namespace" --no-headers 2>&1 || true)
  if [[ -z "$pod_output" || "$pod_output" == *"No resources found"* ]]; then
    echo "FAIL: no pods in $namespace"
    return 1
  fi
  local not_running
  not_running=$(echo "$pod_output" | grep -v " Running " || true)
  if [[ -n "$not_running" ]]; then
    echo "FAIL: pods not all Running in $namespace"
    return 1
  fi
  return 0
}

# PLATFORM-001: cert-manager pods Running + Certificate reaches Ready=True
test_platform_001() {
  local label="PLATFORM-001 (cert-manager)"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would run: kubectl get pods -n cert-manager; kubectl get certificate -n cert-manager-test"
    record_result "$label" "PASS (dry-run)"
    return 0
  fi

  local pods_check
  if ! pods_check=$(pods_all_running cert-manager 2>&1); then
    record_result "$label" "FAIL (${pods_check})"
    return 0
  fi

  local cert_ready
  cert_ready=$(kube get certificate -n cert-manager-test --no-headers 2>&1 | grep "True" || true)
  if [[ -z "$cert_ready" ]]; then
    record_result "$label" "FAIL (no Ready=True certificate in cert-manager-test)"
    return 0
  fi

  record_result "$label" "PASS"
}

# PLATFORM-002: sealed-secrets pods Running + kubeseal encrypts a test secret
test_platform_002() {
  local label="PLATFORM-002 (sealed-secrets)"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would run: kubectl get pods -n sealed-secrets; kubeseal encrypt test secret"
    record_result "$label" "PASS (dry-run)"
    return 0
  fi

  local pods_check
  if ! pods_check=$(pods_all_running sealed-secrets 2>&1); then
    record_result "$label" "FAIL (${pods_check})"
    return 0
  fi

  if ! command -v kubeseal > /dev/null 2>&1; then
    record_result "$label" "FAIL (kubeseal not installed)"
    return 0
  fi

  local sealed_out
  sealed_out=$(printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"smoke-test","namespace":"default"},"data":{"key":"dmFsdWU="}}' | \
    kubeseal --controller-namespace sealed-secrets 2>&1 || true)
  if [[ -z "$sealed_out" ]]; then
    record_result "$label" "FAIL (kubeseal produced no output)"
    return 0
  fi

  record_result "$label" "PASS"
}

# PLATFORM-003: Harbor pods Running + Helm release deployed
test_platform_003() {
  local label="PLATFORM-003 (harbor)"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would run: kubectl get pods -n harbor; helm list -n harbor"
    record_result "$label" "PASS (dry-run)"
    return 0
  fi

  local pods_check
  if ! pods_check=$(pods_all_running harbor 2>&1); then
    record_result "$label" "FAIL (${pods_check})"
    return 0
  fi

  local helm_release
  helm_release=$(helm_ctx list -n harbor 2>&1 | grep "harbor" || true)
  if [[ -z "$helm_release" ]]; then
    record_result "$label" "FAIL (harbor Helm release not found)"
    return 0
  fi

  record_result "$label" "PASS"
}

# PLATFORM-004: Keycloak pods Running + Helm release deployed
test_platform_004() {
  local label="PLATFORM-004 (keycloak)"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would run: kubectl get pods -n keycloak; helm list -n keycloak"
    record_result "$label" "PASS (dry-run)"
    return 0
  fi

  local pods_check
  if ! pods_check=$(pods_all_running keycloak 2>&1); then
    record_result "$label" "FAIL (${pods_check})"
    return 0
  fi

  local helm_release
  helm_release=$(helm_ctx list -n keycloak 2>&1 | grep "keycloak" || true)
  if [[ -z "$helm_release" ]]; then
    record_result "$label" "FAIL (keycloak Helm release not found)"
    return 0
  fi

  record_result "$label" "PASS"
}

test_platform_001
test_platform_002
test_platform_003
test_platform_004

echo ""
echo "=== Kind Platform Smoke Test Results ==="
PASS_COUNT=0
FAIL_COUNT=0
if [[ "${#RESULTS[@]}" -gt 0 ]]; then
  for result in "${RESULTS[@]}"; do
    echo "  $result"
    if [[ "$result" == *": PASS"* ]]; then
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done
fi
echo ""
echo "Summary: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
