#!/usr/bin/env bash
set -euo pipefail

# macOS compatibility: prefer gtimeout (coreutils), fall back to timeout, then no-op
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
echo

# ── Git Status ────────────────────────────────────────────────────────────────
echo "## Git Status"
git status --short
echo

# ── Recent Commits ────────────────────────────────────────────────────────────
echo "## Recent Commits"
git log --oneline -10
echo

# ── Sprint State ──────────────────────────────────────────────────────────────
echo "## Sprint State"
python3 - <<'PYEOF'
import json, glob, sys

manifest = json.load(open('prd/manifest.json'))
increments = manifest.get('increments', [])
active = manifest.get('activeIncrement')

if active is None:
    # Prefer status=active, then any non-complete
    for inc in reversed(increments):
        if inc.get('status') == 'active':
            active = inc['id']
            break
    if active is None:
        for inc in reversed(increments):
            if inc.get('status') not in ('complete', 'pending'):
                active = inc['id']
                break

if active is None:
    complete = sum(1 for i in increments if i.get('status') == 'complete')
    print(f"No active increment. {complete}/{len(increments)} increments complete.")
    sys.exit(0)

inc_meta = next((i for i in increments if i['id'] == active), {})
name = inc_meta.get('name', '?')

files = glob.glob(f'prd/increment-{active}-*.json')
if not files:
    print(f"Increment {active} ({name}): no sprint file found")
    sys.exit(0)

sprint = json.load(open(files[0]))
stories = sprint.get('stories', [])
total = len(stories)
passes = sum(1 for s in stories if s.get('passes'))
reviewed = sum(1 for s in stories if s.get('reviewed'))
limbo = [s for s in stories if s.get('passes') and not s.get('reviewed')]

print(f"Increment {active} ({name}): {passes}/{total} pass | {reviewed} reviewed | {len(limbo)} limbo")
for s in limbo[:3]:
    print(f"  LIMBO {s.get('id','?')}: {s.get('title','?')}")
PYEOF
echo

# ── Constitutional Gates ──────────────────────────────────────────────────────
echo "## Constitutional Gates"

# G1 — ceremony scripts compile + imports resolve
if python3 -m py_compile scripts/ralph/ceremonies.py scripts/ralph/lib/orient.py scripts/ralph/lib/gates.py 2>/dev/null \
   && PYTHONPATH=. python3 -c "from scripts.ralph.lib import orient, gates" 2>/dev/null; then
  echo "G1 (delivery machine): PASS"
else
  echo "G1 (delivery machine): FAIL"
  python3 -m py_compile scripts/ralph/ceremonies.py scripts/ralph/lib/orient.py scripts/ralph/lib/gates.py 2>&1 | head -5 || true
fi

# G6 — no external registry refs in chart templates
G6_OUT=$(grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ 2>/dev/null || true)
if [ -z "$G6_OUT" ]; then
  echo "G6 (autarky): PASS"
else
  echo "G6 (autarky): FAIL"
  echo "$G6_OUT" | head -5
fi

# G7 — contract validator enforces sovereignty invariants
G7_VALID=0; G7_INVALID=0
python3 contract/validate.py contract/v1/tests/valid.yaml >/dev/null 2>&1 || G7_VALID=1
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml >/dev/null 2>&1 && G7_INVALID=1 || true
if [ "$G7_VALID" -eq 0 ] && [ "$G7_INVALID" -eq 0 ]; then
  echo "G7 (contract): PASS"
else
  echo "G7 (contract): FAIL (valid_rejected=$G7_VALID invalid_accepted=$G7_INVALID)"
fi

# G8 — Istio PeerAuthentication renders STRICT mTLS
G8_RENDERED=$(helm template platform/charts/istio/ 2>/dev/null || true)
if echo "$G8_RENDERED" | grep -q "kind: PeerAuthentication" \
   && echo "$G8_RENDERED" | grep -q "mode: STRICT"; then
  echo "G8 (mTLS STRICT): PASS"
else
  echo "G8 (mTLS STRICT): FAIL — PeerAuthentication mode: STRICT not found in rendered istio chart"
fi

# G9 — all platform charts satisfy HA requirements
G9_OUT=$(bash scripts/ha-gate.sh 2>&1 || true)
G9_FAILED=$(echo "$G9_OUT" | grep -c "^FAIL:" || true)
if [ "$G9_FAILED" -eq 0 ]; then
  echo "G9 (HA gate): PASS"
else
  echo "G9 (HA gate): FAIL — $G9_FAILED charts failing"
  echo "$G9_OUT" | grep "^FAIL:" | head -5
fi
echo

# ── Python Tests ──────────────────────────────────────────────────────────────
echo "## Python Tests"
TEST_PASS=0; TEST_FAIL=0; TEST_ERRORS=""
for f in scripts/ralph/tests/test_*.py; do
  OUT=$(cd "$(dirname "$f")" && _timeout 30 python3 "$(basename "$f")" 2>&1) || true
  if echo "$OUT" | grep -q "^All tests passed\." ; then
    PASSES=$(echo "$OUT" | grep -c "^PASS:" || true)
    TEST_PASS=$((TEST_PASS + PASSES))
  else
    # Count PASS lines even on partial failure
    PASSES=$(echo "$OUT" | grep -c "^PASS:" || true)
    TEST_PASS=$((TEST_PASS + PASSES))
    TEST_FAIL=$((TEST_FAIL + 1))
    TEST_ERRORS="${TEST_ERRORS}$(echo "$OUT" | grep -v "^PASS:" | tail -5)\n"
  fi
done
echo "Pass: $TEST_PASS | Fail: $TEST_FAIL"
if [ "$TEST_FAIL" -gt 0 ]; then
  echo "$TEST_ERRORS" | head -10
fi
echo

# ── Shellcheck ────────────────────────────────────────────────────────────────
echo "## Shellcheck"
if command -v shellcheck &>/dev/null; then
  SC_FILES=$(find scripts/ralph cluster/kind platform bootstrap -name "*.sh" 2>/dev/null | head -40)
  SC_COUNT=$(echo "$SC_FILES" | wc -l | tr -d ' ')
  SC_OUT=$(echo "$SC_FILES" | xargs shellcheck -S error 2>&1 || true)
  if [ -z "$SC_OUT" ]; then
    echo "OK — $SC_COUNT scripts clean"
  else
    ERRORS=$(echo "$SC_OUT" | grep -c "^" || true)
    echo "FAIL — $ERRORS lines of errors"
    echo "$SC_OUT" | head -8
  fi
else
  echo "shellcheck not installed — skipped"
fi
echo

# ── Helm Charts ───────────────────────────────────────────────────────────────
echo "## Helm Charts"
CHART_COUNT=$(find platform/charts cluster/kind/charts -name "Chart.yaml" 2>/dev/null | wc -l | tr -d ' ')
echo "Charts: $CHART_COUNT total"

# Lint the most recently touched chart (not _globals)
RECENT=$(find platform/charts -name "Chart.yaml" ! -path "*/_globals/*" \
  -newer platform/charts/_globals/Chart.yaml 2>/dev/null \
  | head -5 | xargs -I{} dirname {} 2>/dev/null || true)
if [ -n "$RECENT" ]; then
  LINT_FAIL=0
  for chart in $RECENT; do
    LINT_OUT=$(_timeout 30 helm lint "$chart" 2>&1) || LINT_FAIL=1
    if echo "$LINT_OUT" | grep -qE "^\[ERROR\]"; then
      echo "FAIL lint: $chart"
      echo "$LINT_OUT" | grep "\[ERROR\]" | head -3
    fi
  done
  [ "$LINT_FAIL" -eq 0 ] && echo "OK — recently-modified charts lint clean"
else
  echo "No recently-modified charts to lint"
fi
echo

# ── CI ────────────────────────────────────────────────────────────────────────
echo "## CI Workflows"
CI_FILES=$(find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | sort || true)
if [ -n "$CI_FILES" ]; then
  echo "$CI_FILES" | xargs -I{} basename {} | sed 's/^/  /'
else
  echo "  (none)"
fi
