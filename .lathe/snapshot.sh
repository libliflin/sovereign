#!/usr/bin/env bash
set -euo pipefail

# Portable timeout helper (macOS uses gtimeout from coreutils)
_t() {
  local secs="$1"; shift
  if command -v gtimeout &>/dev/null; then gtimeout "$secs" "$@"
  elif command -v timeout &>/dev/null; then timeout "$secs" "$@"
  else "$@"; fi
}

# ── Header ────────────────────────────────────────────────────────────────────
echo "# Project Snapshot"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo

# ── Git Status ────────────────────────────────────────────────────────────────
echo "## Git Status"
git status --short | head -30
echo

# ── Recent Commits ────────────────────────────────────────────────────────────
echo "## Recent Commits"
git log --oneline -10
echo

# ── Sprint State ──────────────────────────────────────────────────────────────
echo "## Sprint State"
ACTIVE_INCREMENT=$(python3 - <<'PYEOF'
import json, sys
with open("prd/manifest.json") as f:
    m = json.load(f)
active = [i for i in m["increments"] if i["status"] == "active"]
if active:
    a = active[0]
    print(f"Increment {a['id']} — {a['name']} (active)")
else:
    pending = [i for i in m["increments"] if i["status"] == "pending"]
    print(f"No active increment. Next pending: {pending[0]['id'] if pending else 'none'}")
PYEOF
)
echo "$ACTIVE_INCREMENT"

# Parse active sprint file for story counts
SPRINT_STATS=$(python3 - <<'PYEOF' 2>/dev/null || echo "  (no active sprint file)"
import json, glob
with open("prd/manifest.json") as f:
    m = json.load(f)
active = [i for i in m["increments"] if i["status"] == "active"]
if not active:
    print("  (no active increment)")
    exit()
a = active[0]
pattern = f"prd/increment-{a['id']}-*.json"
files = glob.glob(pattern)
if not files:
    print(f"  (sprint file not found: {pattern})")
    exit()
with open(files[0]) as f:
    sprint = json.load(f)
stories = sprint.get("stories", [])
total = len(stories)
done   = sum(1 for s in stories if s.get("passes") and s.get("reviewed"))
limbo  = sum(1 for s in stories if s.get("passes") and not s.get("reviewed"))
todo   = sum(1 for s in stories if not s.get("passes"))
print(f"Stories: {total} total | Done(pass+reviewed): {done} | Awaiting review: {limbo} | Todo: {todo}")
if limbo:
    print("  Awaiting review:")
    for s in stories:
        if s.get("passes") and not s.get("reviewed"):
            print(f"    - {s.get('id','?')}: {s.get('title','?')[:60]}")
if todo:
    print("  Todo:")
    for s in stories:
        if not s.get("passes"):
            print(f"    - {s.get('id','?')}: {s.get('title','?')[:60]}")
PYEOF
)
echo "$SPRINT_STATS"
echo

# ── Helm Lint ─────────────────────────────────────────────────────────────────
echo "## Helm Lint"
lint_pass=0; lint_fail=0; lint_errors=""
for chart in platform/charts/*/; do
  if _t 30 helm lint "$chart" &>/dev/null 2>&1; then
    ((lint_pass++)) || true
  else
    ((lint_fail++)) || true
    lint_errors+="  FAIL: $chart\n"
  fi
done
total_charts=$((lint_pass + lint_fail))
if [[ $lint_fail -eq 0 ]]; then
  echo "Pass: $lint_pass / $total_charts — all charts clean"
else
  echo "Pass: $lint_pass | Fail: $lint_fail (of $total_charts)"
  printf "%b" "$lint_errors" | head -10
fi
echo

# ── Tests — scripts/ralph/tests/ ─────────────────────────────────────────────
echo "## Tests — scripts/ralph/tests/"
TEST_FILES=(scripts/ralph/tests/test_*.py)
test_pass=0; test_fail=0; test_errors=""
for tf in "${TEST_FILES[@]}"; do
  [[ -f "$tf" ]] || continue
  out=$(_t 30 python3 "$tf" 2>&1) && {
    ((test_pass++)) || true
  } || {
    ((test_fail++)) || true
    test_errors+="  FAIL: $tf\n$(echo "$out" | grep -E "AssertionError|Error" | head -3 | sed 's/^/    /')\n"
  }
done
total_tests=$((test_pass + test_fail))
if [[ $total_tests -eq 0 ]]; then
  echo "No test files found"
elif [[ $test_fail -eq 0 ]]; then
  echo "Pass: $test_pass / $total_tests — all test files passed"
else
  echo "Pass: $test_pass | Fail: $test_fail (of $total_tests)"
  printf "%b" "$test_errors" | head -15
fi
echo

# ── Contract Validator (G7) ───────────────────────────────────────────────────
echo "## Contract Validator (G7)"
# valid.yaml must pass (exit 0)
if _t 15 python3 contract/validate.py contract/v1/tests/valid.yaml &>/dev/null 2>&1; then
  echo "  valid.yaml:                       PASS"
else
  echo "  valid.yaml:                       FAIL (should be valid)"
fi
# invalid*.yaml must fail (exit non-zero)
contract_invalid_ok=0; contract_invalid_bad=0
for inv in contract/v1/tests/invalid-*.yaml; do
  name=$(basename "$inv")
  if _t 15 python3 contract/validate.py "$inv" &>/dev/null 2>&1; then
    echo "  $name: FAIL (validator should have rejected this)"
    ((contract_invalid_bad++)) || true
  else
    ((contract_invalid_ok++)) || true
  fi
done
echo "  Invalid fixtures rejected correctly: $contract_invalid_ok / $((contract_invalid_ok + contract_invalid_bad))"
echo

# ── Autarky Gate (G6) ─────────────────────────────────────────────────────────
echo "## Autarky Gate (G6) — No external registry refs in chart templates"
AUTARKY=$(grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ 2>/dev/null | head -10) || true
if [[ -z "$AUTARKY" ]]; then
  echo "PASS — no external registry refs"
else
  echo "FAIL — external registry refs found:"
  echo "$AUTARKY"
fi
echo

# ── CI Workflows ──────────────────────────────────────────────────────────────
echo "## CI Workflows"
for f in .github/workflows/*.yml .forgejo/workflows/*.yml; do
  [[ -f "$f" ]] && echo "  $f"
done
echo
