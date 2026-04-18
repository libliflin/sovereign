#!/usr/bin/env bash
set -euo pipefail

# Portable timeout: macOS ships gtimeout via coreutils, Linux has timeout
_timeout() {
  if command -v gtimeout &>/dev/null; then
    gtimeout "$@"
  elif command -v timeout &>/dev/null; then
    timeout "$@"
  else
    shift; "$@"
  fi
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "# Project Snapshot"
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# ── Git status ───────────────────────────────────────────────────────────────
echo "## Git Status"
git status --short | head -30
echo ""

# ── Recent commits ───────────────────────────────────────────────────────────
echo "## Recent Commits"
git log --oneline -10
echo ""

# ── Helm lint (all charts) ───────────────────────────────────────────────────
echo "## Helm Lint"
CHART_DIRS=$(
  { ls platform/charts/*/Chart.yaml 2>/dev/null; ls cluster/kind/charts/*/Chart.yaml 2>/dev/null; } \
    | sed 's|/Chart.yaml||' | sort || true
)
HELM_PASS=0; HELM_FAIL=0; HELM_ERRORS=""
for chart in $CHART_DIRS; do
  result=$(_timeout 30 helm lint "$chart/" 2>&1 || true)
  if echo "$result" | grep -q "^Error\|^\[ERROR\]"; then
    HELM_FAIL=$((HELM_FAIL + 1))
    HELM_ERRORS="${HELM_ERRORS}  FAIL: ${chart}\n"
    HELM_ERRORS="${HELM_ERRORS}$(echo "$result" | grep -E "^Error|\[ERROR\]" | head -3 | sed 's/^/    /')\n"
  else
    HELM_PASS=$((HELM_PASS + 1))
  fi
done
HELM_TOTAL=$((HELM_PASS + HELM_FAIL))
if [ "$HELM_FAIL" -eq 0 ]; then
  echo "OK — ${HELM_TOTAL} charts lint clean"
else
  echo "FAIL — ${HELM_PASS}/${HELM_TOTAL} passed"
  printf "%b" "$HELM_ERRORS"
fi
echo ""

# ── Autarky gate (no external registry refs) ─────────────────────────────────
echo "## Autarky Gate (G6)"
EXT_REFS=$(grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ 2>/dev/null | head -10 || true)
if [ -z "$EXT_REFS" ]; then
  echo "OK — no external registry references in chart templates"
else
  echo "FAIL — external registry references found:"
  echo "$EXT_REFS"
fi
echo ""

# ── Contract validator ───────────────────────────────────────────────────────
echo "## Contract Validator (G7)"
VALID_OUT=$(_timeout 15 python3 contract/validate.py contract/v1/tests/valid.yaml 2>&1 || true)
INVALID_OUT=$(_timeout 15 python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml 2>&1; echo "exit:$?")
VALID_OK=false; INVALID_OK=false
echo "$VALID_OUT" | grep -qi "valid\|pass\|ok" && VALID_OK=true || true
echo "$INVALID_OUT" | grep -q "exit:1" && INVALID_OK=true || true
if $VALID_OK && $INVALID_OK; then
  echo "OK — valid accepted, invalid rejected"
else
  echo "FAIL"
  [ "$VALID_OK" = false ] && echo "  valid.yaml: $VALID_OUT"
  [ "$INVALID_OK" = false ] && echo "  invalid-egress-not-blocked.yaml: should exit 1 but did not"
fi
echo ""

# ── Shellcheck ───────────────────────────────────────────────────────────────
echo "## Shellcheck"
if command -v shellcheck &>/dev/null; then
  SC_OUT=$(find cluster platform scripts -name "*.sh" -not -path "*/node_modules/*" \
    -print0 2>/dev/null | xargs -0 shellcheck -S error 2>&1 || true)
  if [ -z "$SC_OUT" ]; then
    echo "OK — no errors"
  else
    ERR_COUNT=$(echo "$SC_OUT" | grep -c "^In\|error:" || true)
    echo "FAIL — ${ERR_COUNT} error(s)"
    echo "$SC_OUT" | head -15
  fi
else
  echo "SKIP — shellcheck not installed"
fi
echo ""

# ── sovereign-pm: typecheck ──────────────────────────────────────────────────
echo "## sovereign-pm Typecheck"
cd platform/sovereign-pm
TC_OUT=$(_timeout 60 npm run typecheck --silent 2>&1 || true)
if echo "$TC_OUT" | grep -qE "error TS|Found [0-9]+ error"; then
  ERR_COUNT=$(echo "$TC_OUT" | grep -cE "error TS" || true)
  echo "FAIL — ${ERR_COUNT} TypeScript error(s)"
  echo "$TC_OUT" | grep -E "error TS" | head -8
else
  echo "OK — no type errors"
fi
echo ""

# ── sovereign-pm: lint ───────────────────────────────────────────────────────
echo "## sovereign-pm Lint"
LINT_OUT=$(_timeout 60 npm run lint --silent 2>&1 || true)
if echo "$LINT_OUT" | grep -qE "warning|error"; then
  W=$(echo "$LINT_OUT" | grep -c "warning" || true)
  E=$(echo "$LINT_OUT" | grep -c " error " || true)
  echo "FAIL — ${E} error(s), ${W} warning(s)"
  echo "$LINT_OUT" | head -10
else
  echo "OK — no lint issues"
fi
echo ""

# ── sovereign-pm: tests ──────────────────────────────────────────────────────
echo "## sovereign-pm Tests"
TEST_OUT=$(_timeout 90 npm test --silent -- --forceExit 2>&1 || true)
PASS=$(echo "$TEST_OUT" | grep -oE "[0-9]+ passed" | tail -1 || true)
FAIL=$(echo "$TEST_OUT" | grep -oE "[0-9]+ failed" | tail -1 || true)
SKIP=$(echo "$TEST_OUT" | grep -oE "[0-9]+ skipped" | tail -1 || true)
if [ -z "$FAIL" ]; then
  echo "OK — ${PASS:-0 passed}${SKIP:+ | $SKIP}"
else
  echo "FAIL — ${PASS:-0 passed} | ${FAIL}${SKIP:+ | $SKIP}"
  echo "$TEST_OUT" | grep -E "FAIL|●" | head -10
fi
cd "$ROOT"
echo ""

# ── CI config ────────────────────────────────────────────────────────────────
echo "## CI Config"
ls .github/workflows/*.yml 2>/dev/null | sed 's|.github/workflows/||' | tr '\n' '  ' || echo "none"
echo ""

# ── Sprint state ─────────────────────────────────────────────────────────────
echo "## Sprint State"
if command -v python3 &>/dev/null && [ -f prd/manifest.json ]; then
  python3 - <<'PYEOF'
import json, sys
with open('prd/manifest.json') as f:
    m = json.load(f)
inc = m.get('active_increment', 'unknown')
sprint_file = f"prd/increment-{inc}.json" if isinstance(inc, int) else None
print(f"Active increment: {inc}")
if sprint_file:
    try:
        with open(sprint_file) as f:
            sprint = json.load(f)
        stories = sprint.get('stories', [])
        done = sum(1 for s in stories if s.get('passes') and s.get('reviewed'))
        passing = sum(1 for s in stories if s.get('passes') and not s.get('reviewed'))
        todo = sum(1 for s in stories if not s.get('passes'))
        print(f"Stories: {done} done | {passing} passing/unreviewed | {todo} todo — total {len(stories)}")
    except FileNotFoundError:
        print(f"Sprint file not found: {sprint_file}")
PYEOF
else
  echo "prd/manifest.json not found"
fi
echo ""
