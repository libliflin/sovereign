#!/usr/bin/env bash
# ha-gate.sh — Validates that platform charts satisfy HA requirements:
#   1. rendered templates contain a Deployment or StatefulSet with replicas >= 2,
#      OR an HPA targeting one with minReplicas >= 2, OR a DaemonSet-only chart
#      (skipped for ha_exception charts declared in platform/vendor/VENDORS.yaml)
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

# Look up limits_exception status from VENDORS.yaml
# Returns "true" if the chart has limits_exception: true, "false" otherwise
# limits_exception is used for upstream charts where the chart template does not
# expose resource limits configuration for every container via values.yaml.
is_limits_exception() {
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
        if v.get('name') == chart and v.get('limits_exception') is True:
            print('true')
            sys.exit(0)
except Exception:
    pass
print('false')
EOF
}

PASS_COUNT=0
FAIL_COUNT=0

# Write replica-check script to a temp file so it can receive rendered YAML
# via pipe without conflicting with a heredoc (SC2259).
_REPLICA_CHECK_PY="$(mktemp)"
cat > "${_REPLICA_CHECK_PY}" << 'PYEOF'
import sys, yaml
content = sys.stdin.read()
try:
    docs = list(yaml.safe_load_all(content))
    max_r = 0
    has_ds = False
    has_deploy_or_sts = False
    hpa_min = 0
    for doc in docs:
        if not doc:
            continue
        kind = doc.get('kind', '')
        if kind == 'DaemonSet':
            has_ds = True
        elif kind == 'HorizontalPodAutoscaler':
            spec = doc.get('spec') or {}
            min_r = spec.get('minReplicas', 1)
            ref = spec.get('scaleTargetRef', {})
            if ref.get('kind') in ('Deployment', 'StatefulSet') and isinstance(min_r, int):
                if min_r > hpa_min:
                    hpa_min = min_r
        elif kind in ('Deployment', 'StatefulSet'):
            has_deploy_or_sts = True
            # replicas absent from spec means k8s defaults to 1
            r = (doc.get('spec') or {}).get('replicas', 1)
            if isinstance(r, int) and r > max_r:
                max_r = r
    if has_ds and not has_deploy_or_sts and hpa_min == 0:
        print('daemonset-only')
    else:
        print(max(max_r, hpa_min))
except Exception:
    print('0')
PYEOF
trap 'rm -f "${_REPLICA_CHECK_PY}"' EXIT

for chart_dir in "${CHART_DIRS[@]}"; do
    chart_name="$(basename "${chart_dir}")"
    chart_fail=false

    local_ha_exception="$(is_ha_exception "${chart_name}")"
    local_limits_exception="$(is_limits_exception "${chart_name}")"

    # Render templates — all four checks use the rendered output.
    # When a chart ships ci/ci-values.yaml, pass it to satisfy required fields.
    ci_values_args=""
    if [[ -f "${chart_dir}/ci/ci-values.yaml" ]]; then
        ci_values_args="-f ${chart_dir}/ci/ci-values.yaml"
    fi
    rendered=""
    # shellcheck disable=SC2086
    if ! rendered="$(helm template ${ci_values_args} "${chart_dir}" 2>/dev/null)"; then
        echo "FAIL:${chart_name}:helm template failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Skip stub charts — directories with Chart.yaml but no templates rendered.
    # Stubs establish the GitOps path for ArgoCD without a full chart implementation.
    # HA gates are deferred until the chart is implemented.
    if [[ -z "$(echo "${rendered}" | tr -d '[:space:]')" ]]; then
        echo "SKIP:${chart_name}:no templates rendered — stub chart, HA gates deferred"
        continue
    fi

    # Use grep without -q: grep -q exits on first match and causes SIGPIPE on
    # the echo side of the pipe under set -o pipefail when rendered is large.
    # grep without -q reads all stdin before exiting, avoiding SIGPIPE.

    # Detect whether the chart renders any pod-bearing workloads. Policy-only
    # charts (NetworkPolicy, RBAC, CRDs) have no pods to protect and no PDB
    # makes sense for them. When ha_exception is declared and no workloads are
    # present, skip the PDB requirement.
    has_pod_workloads="false"
    if echo "${rendered}" | grep -E "^kind: (Deployment|StatefulSet|DaemonSet|Job|CronJob)" > /dev/null 2>&1; then
        has_pod_workloads="true"
    fi

    # Check 1: HA replica count — inspect rendered Deployment/StatefulSet specs.
    # A chart passes when its rendered output contains at least one Deployment or
    # StatefulSet with spec.replicas >= 2, or an HPA targeting one with
    # minReplicas >= 2.  DaemonSet-only charts are inherently distributed and
    # pass unconditionally.  Charts that render no pod workloads follow the
    # ha_exception path: they pass only when ha_exception: true is declared in
    # VENDORS.yaml (e.g. policy-only charts, library charts).
    if [[ "${local_ha_exception}" == "true" ]]; then
        : # replica check skipped — ha_exception in VENDORS.yaml
    else
        replica_result="$(echo "${rendered}" | python3 "${_REPLICA_CHECK_PY}")"
        if [[ "${replica_result}" == "daemonset-only" ]]; then
            : # DaemonSet-only chart — one pod per node by design, inherently HA
        elif [[ -z "${replica_result}" ]] || ! [[ "${replica_result}" =~ ^[0-9]+$ ]] || [[ "${replica_result}" -lt 2 ]]; then
            echo "FAIL:${chart_name}:no Deployment or StatefulSet with replicas >= 2 in rendered templates"
            chart_fail=true
        fi
    fi

    if [[ "${local_ha_exception}" == "true" && "${has_pod_workloads}" == "false" ]]; then
        : # PDB check skipped — ha_exception with no pod workloads (policy-only chart)
    elif ! echo "${rendered}" | grep "PodDisruptionBudget" > /dev/null; then
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

    if [[ "${local_limits_exception}" == "true" ]]; then
        : # resource limits check skipped — limits_exception in VENDORS.yaml
          # upstream chart template does not expose resource limits for every container
    elif ! echo "${rendered}" | python3 "${REPO_ROOT}/scripts/check-limits.py" > /dev/null 2>&1; then
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
