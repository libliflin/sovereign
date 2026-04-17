#!/usr/bin/env bash
# ha-gate.sh — Validates that all platform charts satisfy HA requirements:
#   1. values.yaml has replicaCount >= 2
#   2. helm template output contains PodDisruptionBudget
#   3. helm template output contains podAntiAffinity
#
# Usage:
#   scripts/ha-gate.sh                 # run full validation
#   scripts/ha-gate.sh --dry-run       # list charts that will be checked, then exit
#   scripts/ha-gate.sh --chart <name>  # validate a single chart in isolation

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_CHARTS_DIR="${REPO_ROOT}/platform/charts"
KIND_CHARTS_DIR="${REPO_ROOT}/cluster/kind/charts"
VENDORS_YAML="${REPO_ROOT}/platform/vendor/VENDORS.yaml"

DRY_RUN=false
CHART_FILTER=""

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --chart)
            CHART_FILTER="${2:-}"
            shift 2
            ;;
        *)
            echo "ERROR: unknown argument: ${1}"
            exit 1
            ;;
    esac
done

# ha_exception_for <chart_name> — returns "true" if chart has ha_exception in VENDORS.yaml
ha_exception_for() {
    local chart_name="${1}"
    if [[ ! -f "${VENDORS_YAML}" ]]; then
        echo "false"
        return
    fi
    python3 -c "
import yaml, sys
chart = sys.argv[1]
try:
    with open('${VENDORS_YAML}') as f:
        data = yaml.safe_load(f)
    for v in data.get('vendors', []):
        if v.get('name') == chart and v.get('ha_exception') is True:
            print('true')
            sys.exit(0)
except Exception:
    pass
print('false')
" "${chart_name}" 2>/dev/null || echo "false"
}

# Collect all chart directories (must contain Chart.yaml)
ALL_CHART_DIRS=()
for dir in "${PLATFORM_CHARTS_DIR}"/*/; do
    [[ -f "${dir}Chart.yaml" ]] && ALL_CHART_DIRS+=("${dir%/}")
done
for dir in "${KIND_CHARTS_DIR}"/*/; do
    [[ -f "${dir}Chart.yaml" ]] && ALL_CHART_DIRS+=("${dir%/}")
done

# Filter to a single chart if --chart was specified
CHART_DIRS=()
if [[ -n "${CHART_FILTER}" ]]; then
    for dir in "${ALL_CHART_DIRS[@]}"; do
        if [[ "$(basename "${dir}")" == "${CHART_FILTER}" ]]; then
            CHART_DIRS+=("${dir}")
        fi
    done
    if [[ "${#CHART_DIRS[@]}" -eq 0 ]]; then
        echo "FAIL:${CHART_FILTER}:chart not found in platform/charts/ or cluster/kind/charts/"
        exit 1
    fi
else
    CHART_DIRS=("${ALL_CHART_DIRS[@]}")
fi

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

    # Determine whether this chart has an ha_exception in VENDORS.yaml
    local_ha_exception="$(ha_exception_for "${chart_name}")"

    # Check 1: replicaCount >= 2 in values.yaml (skipped for ha_exception charts)
    values_file="${chart_dir}/values.yaml"
    if [[ ! -f "${values_file}" ]]; then
        echo "FAIL:${chart_name}:values.yaml missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    if [[ "${local_ha_exception}" != "true" ]]; then
        replica_count="$(grep -E '^replicaCount:' "${values_file}" | awk '{print $2}' | tr -d '[:space:]' || true)"
        if [[ -z "${replica_count}" ]]; then
            echo "FAIL:${chart_name}:replicaCount missing from values.yaml"
            chart_fail=true
        elif [[ "${replica_count}" -lt 2 ]] 2>/dev/null; then
            echo "FAIL:${chart_name}:replicaCount < 2"
            chart_fail=true
        fi
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

    # podAntiAffinity not required for ha_exception charts (architecturally single-instance)
    if [[ "${local_ha_exception}" != "true" ]]; then
        if ! echo "${rendered}" | grep "podAntiAffinity" > /dev/null; then
            echo "FAIL:${chart_name}:no podAntiAffinity in rendered templates"
            chart_fail=true
        fi
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
