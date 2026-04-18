#!/usr/bin/env bash
# ha-gate.sh — Validates that platform charts satisfy HA requirements:
#   1. values.yaml has replicaCount >= 2 (skipped for ha_exception charts)
#   2. helm template output contains PodDisruptionBudget
#   3. helm template output contains podAntiAffinity (skipped for ha_exception charts)
#   4. all containers have resource requests and limits
#
# Usage:
#   scripts/ha-gate.sh                   # run full validation
#   scripts/ha-gate.sh --chart <name>    # validate a single chart by name
#   scripts/ha-gate.sh --dry-run         # list charts that will be checked, then exit

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
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --chart requires a chart name argument"
                exit 1
            fi
            CHART_FILTER="${2}"
            shift 2
            ;;
        *)
            echo "ERROR: unknown argument: ${1}"
            echo "Usage: ha-gate.sh [--dry-run] [--chart <name>]"
            exit 1
            ;;
    esac
done

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

# Filter to a single chart when --chart is given
if [[ -n "${CHART_FILTER}" ]]; then
    FILTERED=()
    for chart_dir in "${CHART_DIRS[@]}"; do
        if [[ "$(basename "${chart_dir}")" == "${CHART_FILTER}" ]]; then
            FILTERED+=("${chart_dir}")
        fi
    done
    if [[ "${#FILTERED[@]}" -eq 0 ]]; then
        echo "FAIL:${CHART_FILTER}:chart not found in platform/charts/ or cluster/kind/charts/"
        exit 1
    fi
    CHART_DIRS=("${FILTERED[@]}")
fi

if "${DRY_RUN}"; then
    echo "Charts to check (--dry-run):"
    for chart_dir in "${CHART_DIRS[@]}"; do
        echo "  $(basename "${chart_dir}")"
    done
    exit 0
fi

# Look up ha_exception status from VENDORS.yaml
# Returns "true" if the chart has ha_exception: true, "false" otherwise
is_ha_exception() {
    local chart_name="${1}"
    if [[ ! -f "${VENDORS_YAML}" ]]; then
        echo "false"
        return
    fi
    python3 - "${chart_name}" "${VENDORS_YAML}" <<'EOF'
import sys, yaml
chart = sys.argv[1]
vendors_path = sys.argv[2]
try:
    with open(vendors_path) as f:
        data = yaml.safe_load(f)
    for v in data.get('vendors', []):
        if v.get('name') == chart and v.get('ha_exception') is True:
            print('true')
            sys.exit(0)
except Exception:
    pass
print('false')
EOF
}

PASS_COUNT=0
FAIL_COUNT=0

for chart_dir in "${CHART_DIRS[@]}"; do
    chart_name="$(basename "${chart_dir}")"
    chart_fail=false

    local_ha_exception="$(is_ha_exception "${chart_name}")"

    # Check 1: replicaCount >= 2 in values.yaml (skip for ha_exception)
    values_file="${chart_dir}/values.yaml"
    if [[ ! -f "${values_file}" ]]; then
        echo "FAIL:${chart_name}:values.yaml missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    if [[ "${local_ha_exception}" == "true" ]]; then
        : # replicaCount check skipped — ha_exception in VENDORS.yaml
    else
        replica_count="$(grep -E '^replicaCount:' "${values_file}" | awk '{print $2}' | tr -d '[:space:]' || true)"
        if [[ -z "${replica_count}" ]]; then
            echo "FAIL:${chart_name}:replicaCount missing from values.yaml"
            chart_fail=true
        elif [[ "${replica_count}" -lt 2 ]] 2>/dev/null; then
            echo "FAIL:${chart_name}:replicaCount < 2"
            chart_fail=true
        fi
    fi

    # Check 2, 3, 4: render and inspect templates
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

    if [[ "${local_ha_exception}" == "true" ]]; then
        : # podAntiAffinity check skipped — ha_exception in VENDORS.yaml
    else
        if ! echo "${rendered}" | grep "podAntiAffinity" > /dev/null; then
            echo "FAIL:${chart_name}:no podAntiAffinity in rendered templates"
            chart_fail=true
        fi
    fi

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
