#!/usr/bin/env bash
set -euo pipefail

# macOS/Linux timeout compat
_timeout() {
  if command -v gtimeout &>/dev/null; then gtimeout "$@"
  elif command -v timeout &>/dev/null; then timeout "$@"
  else shift; "$@"; fi
}

echo "# Project Snapshot"
echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# ── Git status ────────────────────────────────────────────────────────────────
echo "## Git Status"
git status --short
echo ""

# ── Recent commits ────────────────────────────────────────────────────────────
echo "## Recent Commits"
git log --oneline -10
echo ""

# ── Sprint ────────────────────────────────────────────────────────────────────
echo "## Sprint"
if [ -f prd/manifest.json ]; then
  python3 -c "
import json
with open('prd/manifest.json') as f: m = json.load(f)
incs = m.get('increments', [])
for i in incs:
    if i.get('status') == 'active':
        print(f\"  Active: #{i.get('id')} {i.get('name')} — {i.get('description','')[:80]}\")
        break
else:
    print('  No active increment found')
" 2>/dev/null || echo "  (manifest parse error)"
else
  echo "  No prd/manifest.json"
fi
echo ""

# ── Helm lint ─────────────────────────────────────────────────────────────────
echo "## Helm Lint"
LINT_PASS=0; LINT_FAIL=0; LINT_ERRORS=""
while IFS= read -r chart; do
  out=$(_timeout 10 helm lint "$chart/" 2>&1) \
    && LINT_PASS=$((LINT_PASS+1)) \
    || {
      LINT_FAIL=$((LINT_FAIL+1))
      name=$(basename "$chart")
      err=$(echo "$out" | grep -iE "error|warning" | head -2 | sed 's/^/    /')
      LINT_ERRORS+="  FAIL: $name"$'\n'"$err"$'\n'
    }
done < <(
  { ls platform/charts/*/Chart.yaml 2>/dev/null
    ls cluster/kind/charts/*/Chart.yaml 2>/dev/null; } \
    | sed 's|/Chart.yaml||' | sort
)
if [ "$LINT_FAIL" -eq 0 ]; then
  echo "OK — Pass: $LINT_PASS | Fail: 0"
else
  echo "FAIL — Pass: $LINT_PASS | Fail: $LINT_FAIL"
  echo "$LINT_ERRORS" | head -20
fi
echo ""

# ── Contract validator (G7) ───────────────────────────────────────────────────
echo "## Contract Validator (G7)"
CV_PASS=0; CV_FAIL=0; CV_OUT=""

# valid.yaml must pass
if _timeout 15 python3 contract/validate.py contract/v1/tests/valid.yaml >/dev/null 2>&1; then
  CV_PASS=$((CV_PASS+1))
else
  CV_FAIL=$((CV_FAIL+1))
  CV_OUT+="  FAIL: valid.yaml (expected pass)"$'\n'
fi

# invalid-*.yaml must fail (exit 1)
for f in contract/v1/tests/invalid-*.yaml; do
  name=$(basename "$f")
  if _timeout 15 python3 contract/validate.py "$f" >/dev/null 2>&1; then
    CV_FAIL=$((CV_FAIL+1))
    CV_OUT+="  FAIL: $name (expected reject but passed)"$'\n'
  else
    CV_PASS=$((CV_PASS+1))
  fi
done

if [ "$CV_FAIL" -eq 0 ]; then
  echo "OK — Pass: $CV_PASS | Fail: 0"
else
  echo "FAIL — Pass: $CV_PASS | Fail: $CV_FAIL"
  echo "$CV_OUT"
fi
echo ""

# ── Autarky — no external registry refs (G6) ─────────────────────────────────
echo "## Autarky (G6)"
EXT=$(grep -rn \
  "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ cluster/kind/charts/*/templates/ 2>/dev/null || true)
COUNT=$(echo "$EXT" | grep -c . || true)
if [ "$COUNT" -eq 0 ]; then
  echo "OK — No external registry references in chart templates"
else
  echo "FAIL — $COUNT external registry reference(s):"
  echo "$EXT" | head -5 | sed 's/^/  /'
fi
echo ""

# ── Shellcheck ────────────────────────────────────────────────────────────────
echo "## Shellcheck"
SC_OUT=$(find cluster platform scripts -name "*.sh" \
  -not -path "*/node_modules/*" \
  -not -path "*/__pycache__/*" \
  -print0 2>/dev/null \
  | xargs -0 shellcheck -S error 2>&1 || true)
if [ -z "$SC_OUT" ]; then
  echo "OK"
else
  ERR_COUNT=$(echo "$SC_OUT" | grep -c "^In " || true)
  echo "FAIL — $ERR_COUNT file(s) with errors"
  echo "$SC_OUT" | head -15 | sed 's/^/  /'
fi
echo ""

# ── State docs (G2) ───────────────────────────────────────────────────────────
echo "## State Docs (G2)"
for doc in docs/state/agent.md docs/state/architecture.md; do
  if [ -f "$doc" ]; then
    echo "  OK: $doc"
  else
    echo "  MISSING: $doc"
  fi
done
echo ""

# ── CI config ─────────────────────────────────────────────────────────────────
echo "## CI"
if ls .github/workflows/*.yml &>/dev/null 2>&1; then
  for f in .github/workflows/*.yml; do
    echo "  $(basename "$f")"
  done
else
  echo "  No CI config found"
fi
