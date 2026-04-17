#!/usr/bin/env bash
set -euo pipefail

# Sovereign Platform — lathe cycle snapshot
# Budget: ~4000 chars, hard cap 6000

# macOS timeout shim
_timeout() {
  if command -v gtimeout &>/dev/null; then
    gtimeout "$@"
  elif command -v timeout &>/dev/null; then
    timeout "$@"
  else
    shift; "$@"
  fi
}

echo "# Project Snapshot"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# ── Git ────────────────────────────────────────────────────────────────────
echo "## Git Status"
git status --short
echo ""

echo "## Recent Commits"
git log --oneline -10
echo ""

# ── Sprint State ───────────────────────────────────────────────────────────
echo "## Sprint State"
python3 - <<'PYEOF' 2>/dev/null || echo "(sprint state unavailable)"
import json, os

with open('prd/manifest.json') as f:
    manifest = json.load(f)

complete = sum(1 for i in manifest['increments'] if i['status'] == 'complete')
active = [i for i in manifest['increments'] if i['status'] == 'active']
pending = sum(1 for i in manifest['increments'] if i['status'] == 'pending')

print(f"Complete increments: {complete} | Active: {len(active)} | Pending: {pending}")

for inc in active:
    sprint_file = inc.get('file', f"prd/increment-{inc['id']}-{inc['name']}.json")
    if not os.path.exists(sprint_file):
        print(f"Active: #{inc['id']} {inc['name']} (no sprint file)")
        continue
    with open(sprint_file) as f:
        sprint = json.load(f)
    stories = sprint.get('stories', [])
    done = sum(1 for s in stories if s.get('passes'))
    reviewed = sum(1 for s in stories if s.get('reviewed'))
    total = len(stories)
    print(f"Active: #{inc['id']} {inc['name']}")
    print(f"Stories: {done}/{total} pass | {reviewed}/{total} reviewed")
    # Show unreviewed-passing stories (awaiting ceremony)
    awaiting = [s['id'] for s in stories if s.get('passes') and not s.get('reviewed')]
    if awaiting:
        print(f"Awaiting review: {', '.join(awaiting)}")
    # Show not-yet-passing stories
    todo = [s['id'] for s in stories if not s.get('passes')]
    if todo:
        print(f"Not passing: {', '.join(todo)}")
PYEOF
echo ""

# ── Constitutional Gates ───────────────────────────────────────────────────
echo "## Constitutional Gates"

# G1 — ceremony scripts compile
G1_OUT=$(python3 - <<'PYEOF' 2>&1 || true
import py_compile, subprocess, sys
errors = []
for f in ['scripts/ralph/ceremonies.py', 'scripts/ralph/lib/orient.py', 'scripts/ralph/lib/gates.py']:
    try:
        py_compile.compile(f, doraise=True)
    except py_compile.PyCompileError as e:
        errors.append(str(e))
if errors:
    print("FAIL — " + "; ".join(errors))
    sys.exit(1)
# import smoke test
result = subprocess.run(['python3', '-c', 'from scripts.ralph.lib import orient, gates'],
                       capture_output=True, text=True)
if result.returncode != 0:
    print("FAIL — broken import: " + result.stderr.strip()[:120])
else:
    print("PASS")
PYEOF
)
echo "G1 (ceremony compile): $G1_OUT"

# G6 — zero external registry refs in chart templates
G6_HITS=$(grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ 2>/dev/null || true)
if [ -z "$G6_HITS" ]; then
  echo "G6 (autarky): PASS"
else
  HIT_COUNT=$(echo "$G6_HITS" | wc -l | tr -d ' ')
  echo "G6 (autarky): FAIL — $HIT_COUNT external registry refs"
  echo "$G6_HITS" | head -5
fi

# G7 — contract validator
G7_VALID=$(_timeout 15 python3 contract/validate.py contract/v1/tests/valid.yaml 2>&1 || true)
G7_INVALID=$(_timeout 15 python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml 2>&1; echo "exit:$?")
G7_INVALID_EXIT=$(echo "$G7_INVALID" | grep "exit:" | sed 's/exit://')
if echo "$G7_VALID" | grep -qi "error\|invalid\|fail"; then
  echo "G7 (contract): FAIL — valid.yaml rejected"
elif [ "${G7_INVALID_EXIT:-0}" -eq 0 ]; then
  echo "G7 (contract): FAIL — invalid contract accepted (autarky unenforced)"
else
  echo "G7 (contract): PASS"
fi
echo ""

# ── Helm Lint ──────────────────────────────────────────────────────────────
echo "## Helm Lint"
HELM_PASS=0; HELM_FAIL=0; HELM_FAIL_NAMES=""
for chart_dir in platform/charts/*/  cluster/kind/charts/*/; do
  [ -f "${chart_dir}Chart.yaml" ] || continue
  result=$(_timeout 30 helm lint "$chart_dir" 2>&1) && status=0 || status=1
  if [ $status -eq 0 ]; then
    HELM_PASS=$((HELM_PASS + 1))
  else
    HELM_FAIL=$((HELM_FAIL + 1))
    chart_name=$(basename "$chart_dir")
    HELM_FAIL_NAMES="$HELM_FAIL_NAMES $chart_name"
    echo "FAIL [$chart_name]: $(echo "$result" | grep -i "error\|fail" | head -3)"
  fi
done
if [ $HELM_FAIL -eq 0 ]; then
  echo "Pass: $HELM_PASS | Fail: 0"
else
  echo "Pass: $HELM_PASS | Fail: $HELM_FAIL ($HELM_FAIL_NAMES)"
fi
echo ""

# ── Shellcheck ─────────────────────────────────────────────────────────────
echo "## Shellcheck"
if command -v shellcheck &>/dev/null; then
  SC_FILES=$(find cluster platform scripts -name "*.sh" -not -path "*/node_modules/*" 2>/dev/null)
  SC_COUNT=$(echo "$SC_FILES" | grep -c "\.sh$" || true)
  SC_OUT=$(echo "$SC_FILES" | xargs -r shellcheck -S error 2>&1 || true)
  if [ -z "$SC_OUT" ]; then
    echo "Pass: $SC_COUNT scripts clean"
  else
    ERR_COUNT=$(echo "$SC_OUT" | grep -c "^In \|error" || true)
    echo "Errors in $SC_COUNT scripts:"
    echo "$SC_OUT" | head -10
  fi
else
  echo "(shellcheck not installed)"
fi
echo ""

# ── CI Config ─────────────────────────────────────────────────────────────
echo "## CI"
if [ -d .github/workflows ]; then
  echo -n "GitHub Actions workflows: "
  ls .github/workflows/ | tr '\n' ' '
  echo ""
else
  echo "No CI config found"
fi
