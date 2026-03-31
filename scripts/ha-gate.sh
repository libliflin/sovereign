#!/usr/bin/env bash
# ha-gate.sh — Validates that all platform charts satisfy HA requirements:
#   1. values.yaml has replicaCount >= 2
#   2. helm template output contains PodDisruptionBudget
#   3. helm template output contains podAntiAffinity
#
# Usage:
#   scripts/ha-gate.sh            # run full validation
#   scripts/ha-gate.sh --dry-run  # list charts that will be checked, then exit

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_CHARTS_DIR="${REPO_ROOT}/platform/charts"
KIND_CHARTS_DIR="${REPO_ROOT}/cluster/kind/charts"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Collect all chart directories (must contain Chart.yaml)
CHART_DIRS=()
for dir in "${PLATFORM_CHARTS_DIR}"/*/; do
    [[ -f "${dir}Chart.yaml" ]] && CHART_DIRS+=("${dir%/}")
done
for dir in "${KIND_CHARTS_DIR}"/*/; do
    [[ -f "${dir}Chart.yaml" ]] && CHART_DIRS+=("${dir%/}")
done

if [[ "${#CHART_DIRS[@]}" -eq 0 ]]; then
    echo "ERROR: no chart directories found"
    exit 1
fi

if "${DRY_RUN}"; then
    echo "Charts to check (--dry-run):"
    for chart_dir in "${CHART_DIRS[@]}"; do
        echo "  $(basename "${chart_dir}")"
    done
    exit 0
fi

PASS_COUNT=0
FAIL_COUNT=0

for chart_dir in "${CHART_DIRS[@]}"; do
    chart_name="$(basename "${chart_dir}")"
    chart_fail=false

    # Check 1: replicaCount >= 2 in values.yaml
    values_file="${chart_dir}/values.yaml"
    if [[ ! -f "${values_file}" ]]; then
        echo "FAIL:${chart_name}:values.yaml missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    replica_count="$(grep -E '^replicaCount:' "${values_file}" | awk '{print $2}' | tr -d '[:space:]' || true)"
    if [[ -z "${replica_count}" ]]; then
        echo "FAIL:${chart_name}:replicaCount missing from values.yaml"
        chart_fail=true
    elif [[ "${replica_count}" -lt 2 ]] 2>/dev/null; then
        echo "FAIL:${chart_name}:replicaCount < 2"
        chart_fail=true
    fi

    # Check 2 & 3: PodDisruptionBudget and podAntiAffinity in rendered templates
    rendered=""
    if ! rendered="$(helm template "${chart_dir}" 2>/dev/null)"; then
        echo "FAIL:${chart_name}:helm template failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Use grep without -q: grep -q exits on first match and causes SIGPIPE on
    # the echo side of the pipe under set -o pipefail when rendered is large.
    # grep without -q reads all stdin before exiting, avoiding SIGPIPE.
    if ! echo "${rendered}" | grep "PodDisruptionBudget" > /dev/null; then
        echo "FAIL:${chart_name}:no PodDisruptionBudget in rendered templates"
        chart_fail=true
    fi

    if ! echo "${rendered}" | grep "podAntiAffinity" > /dev/null; then
        echo "FAIL:${chart_name}:no podAntiAffinity in rendered templates"
        chart_fail=true
    fi

    # Check 4: all containers have resource requests and limits
    if ! echo "${rendered}" | python3 "${REPO_ROOT}/scripts/check-limits.py" > /dev/null 2>&1; then
        limits_output="$(echo "${rendered}" | python3 "${REPO_ROOT}/scripts/check-limits.py" 2>&1 || true)"
        echo "FAIL:${chart_name}:resource limits check failed"
        echo "${limits_output}"
        chart_fail=true
    fi

    if "${chart_fail}"; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "PASS:${chart_name}"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
done

echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    exit 1
fi
