#!/usr/bin/env bash
# cost-gate.sh — validates that chart resource requests fit within per-node budget.
#
# Reads resources.requests.cpu and resources.requests.memory from each chart's
# values.yaml, sums them, and fails if the total exceeds the configured budget.
#
# Budget defaults (override via environment):
#   COST_GATE_MAX_CPU     = 4       (cores)
#   COST_GATE_MAX_MEMORY  = 8192    (MiB)
#
# Usage:
#   bash scripts/gates/cost-gate.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHARTS_DIR="${REPO_ROOT}/platform/charts"

MAX_CPU="${COST_GATE_MAX_CPU:-4}"
MAX_MEMORY_MIB="${COST_GATE_MAX_MEMORY:-8192}"

# Parse a single values.yaml and print "cpu_millicores memory_mib" for the chart
parse_values() {
    local values_file="$1"
    python3 - "${values_file}" <<'PYEOF'
import sys
import re

try:
    import yaml
except ImportError:
    print("0 0")
    sys.exit(0)

def parse_cpu(val):
    """Convert CPU string to millicores."""
    if val is None:
        return 0
    s = str(val).strip()
    if s.endswith('m'):
        return int(s[:-1])
    try:
        return int(float(s) * 1000)
    except ValueError:
        return 0

def parse_memory_mib(val):
    """Convert memory string to MiB."""
    if val is None:
        return 0
    s = str(val).strip()
    units = {
        'Ki': 1/1024, 'Mi': 1, 'Gi': 1024,
        'K': 1/1024 * 1000, 'M': 1000/1024, 'G': 1000*1000/1024,
        'k': 1/1024 * 1000, 'm': 1000/1024, 'g': 1000*1000/1024,
    }
    for suffix, factor in sorted(units.items(), key=lambda x: -len(x[0])):
        if s.endswith(suffix):
            try:
                return int(float(s[:-len(suffix)]) * factor)
            except ValueError:
                return 0
    try:
        return int(int(s) / (1024 * 1024))
    except ValueError:
        return 0

try:
    with open(sys.argv[1]) as f:
        v = yaml.safe_load(f) or {}
except Exception:
    print("0 0")
    sys.exit(0)

cpu_mc = 0
mem_mib = 0

resources = v.get('resources', {})
if isinstance(resources, dict):
    requests = resources.get('requests', {})
    if isinstance(requests, dict):
        cpu_mc += parse_cpu(requests.get('cpu'))
        mem_mib += parse_memory_mib(requests.get('memory'))

print(f"{cpu_mc} {mem_mib}")
PYEOF
}

TOTAL_CPU_MC=0
TOTAL_MEM_MIB=0
CHART_COUNT=0

echo "Per-chart resource requests (cpu millicores / memory MiB):"
echo "------------------------------------------------------------"

for values_file in "${CHARTS_DIR}"/*/values.yaml; do
    chart_name="$(basename "$(dirname "${values_file}")")"
    result="$(parse_values "${values_file}")"
    cpu_mc="$(echo "${result}" | awk '{print $1}')"
    mem_mib="$(echo "${result}" | awk '{print $2}')"

    cpu_cores="$(awk "BEGIN { printf \"%.3f\", ${cpu_mc}/1000 }")"
    printf "  %-30s  cpu: %s cores (%s m)  memory: %s MiB\n" \
        "${chart_name}" "${cpu_cores}" "${cpu_mc}" "${mem_mib}"

    TOTAL_CPU_MC=$((TOTAL_CPU_MC + cpu_mc))
    TOTAL_MEM_MIB=$((TOTAL_MEM_MIB + mem_mib))
    CHART_COUNT=$((CHART_COUNT + 1))
done

TOTAL_CPU_CORES="$(awk "BEGIN { printf \"%.3f\", ${TOTAL_CPU_MC}/1000 }")"
TOTAL_MEM_GIB="$(awk "BEGIN { printf \"%.2f\", ${TOTAL_MEM_MIB}/1024 }")"

echo "------------------------------------------------------------"
echo "Total (${CHART_COUNT} charts):"
echo "  CPU:    ${TOTAL_CPU_CORES} cores (${TOTAL_CPU_MC} m)  budget: ${MAX_CPU} cores"
echo "  Memory: ${TOTAL_MEM_GIB} GiB (${TOTAL_MEM_MIB} MiB)  budget: $(awk "BEGIN { printf \"%.2f\", ${MAX_MEMORY_MIB}/1024 }") GiB"
echo ""

CPU_FAIL=false
MEM_FAIL=false

if awk "BEGIN { exit (${TOTAL_CPU_MC} > ${MAX_CPU}*1000) ? 0 : 1 }"; then
    echo "  FAIL: total CPU ${TOTAL_CPU_CORES} cores exceeds budget ${MAX_CPU} cores"
    CPU_FAIL=true
fi
if awk "BEGIN { exit (${TOTAL_MEM_MIB} > ${MAX_MEMORY_MIB}) ? 0 : 1 }"; then
    echo "  FAIL: total memory ${TOTAL_MEM_GIB} GiB exceeds budget $(awk "BEGIN { printf \"%.2f\", ${MAX_MEMORY_MIB}/1024 }") GiB"
    MEM_FAIL=true
fi

if "${CPU_FAIL}" || "${MEM_FAIL}"; then
    echo "FAIL"
    exit 1
fi

echo "PASS"
