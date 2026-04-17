#!/usr/bin/env bash
set -euo pipefail

# Portable timeout: use gtimeout on macOS if available, else timeout, else none
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
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# ── Git Status ─────────────────────────────────────────────────────────────
echo "## Git Status"
git status --short | head -20
echo ""

# ── Recent Commits ─────────────────────────────────────────────────────────
echo "## Recent Commits"
git log --oneline -10
echo ""

# ── Active Sprint ──────────────────────────────────────────────────────────
echo "## Active Sprint"
python3 - <<'PYEOF' 2>/dev/null || echo "  (could not read manifest)"
import json, glob, os

manifest = json.load(open("prd/manifest.json"))
active = [i for i in manifest["increments"] if i.get("status") == "active"]
if not active:
    print("  No active increment")
else:
    inc = active[0]
    print(f"  Increment {inc['id']}: {inc['name']}")
    f = inc.get("file")
    if f and os.path.exists(f):
        data = json.load(open(f))
        stories = data.get("stories", [])
        passing = sum(1 for s in stories if s.get("passes"))
        reviewed = sum(1 for s in stories if s.get("reviewed"))
        print(f"  Stories: {len(stories)} | Passing: {passing} | Reviewed: {reviewed} | Pending: {len(stories)-passing}")
        failing = [s for s in stories if not s.get("passes")]
        for s in failing[:3]:
            print(f"    - [{s.get('id','?')}] {s.get('title','?')[:60]}")
PYEOF
echo ""

# ── Constitutional Gates ───────────────────────────────────────────────────
echo "## Constitutional Gates"

# G1: ceremonies.py compiles + imports resolve
g1_out=$(bash -c 'python3 -m py_compile scripts/ralph/ceremonies.py 2>&1 && python3 -m py_compile scripts/ralph/lib/orient.py 2>&1 && python3 -m py_compile scripts/ralph/lib/gates.py 2>&1 && PYTHONPATH=. python3 -c "from scripts.ralph.lib import orient, gates" 2>&1' || true)
if [ -z "$g1_out" ]; then
  echo "  G1 PASS — ceremonies.py compiles, imports resolve"
else
  echo "  G1 FAIL — $g1_out" | head -3
fi

# G6: no external registry refs in chart templates
g6_out=$(grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/*/templates/ 2>/dev/null || true)
if [ -z "$g6_out" ]; then
  echo "  G6 PASS — no external registries in chart templates"
else
  echo "  G6 FAIL — external registry refs found:"
  echo "$g6_out" | head -5
fi

# G7: contract validator test suite
g7_valid=$( python3 contract/validate.py contract/v1/tests/valid.yaml > /dev/null 2>&1 && echo "ok" || echo "fail")
g7_invalid=$(python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml > /dev/null 2>&1 && echo "accepted" || echo "rejected")
if [ "$g7_valid" = "ok" ] && [ "$g7_invalid" = "rejected" ]; then
  echo "  G7 PASS — contract validator enforces sovereignty invariants"
else
  [ "$g7_valid" != "ok" ]      && echo "  G7 FAIL — valid.yaml rejected by validator"
  [ "$g7_invalid" = "accepted" ] && echo "  G7 FAIL — invalid contract accepted (autarky invariant unenforced)"
fi

echo ""

# ── Helm Lint ──────────────────────────────────────────────────────────────
echo "## Helm Lint"
if ! command -v helm &>/dev/null; then
  echo "  helm not found — skipping"
else
  charts=()
  while IFS= read -r f; do charts+=("$(dirname "$f")"); done < <(find platform/charts cluster/kind/charts -name "Chart.yaml" 2>/dev/null | sort)
  total=0; passed=0; failed=0; failures=()
  for chart in "${charts[@]}"; do
    total=$((total+1))
    out=$(_timeout 30 helm lint "$chart/" 2>&1 || true)
    if echo "$out" | grep -q "^Error\|error\|FAILED"; then
      failed=$((failed+1))
      failures+=("$chart")
    else
      passed=$((passed+1))
    fi
  done
  if [ "$failed" -eq 0 ]; then
    echo "  PASS — $passed/$total charts lint clean"
  else
    echo "  FAIL — $failed/$total charts failed:"
    for f in "${failures[@]}"; do echo "    - $f"; done
  fi
fi
echo ""

# ── Shellcheck ─────────────────────────────────────────────────────────────
echo "## Shellcheck"
if ! command -v shellcheck &>/dev/null; then
  echo "  shellcheck not found — skipping"
else
  sc_out=$(find scripts/ralph cluster platform -name "*.sh" -not -path "*/node_modules/*" -print0 2>/dev/null \
    | xargs -0 shellcheck -S error 2>&1 || true)
  if [ -z "$sc_out" ]; then
    echo "  PASS — all scripts clean"
  else
    err_count=$(echo "$sc_out" | grep -c "^In " || true)
    echo "  FAIL — $err_count script(s) with errors"
    echo "$sc_out" | head -8
  fi
fi
echo ""

# ── Autarky Check ──────────────────────────────────────────────────────────
echo "## Autarky (external registry refs in templates)"
ext_refs=$(grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ cluster/kind/charts/*/templates/ 2>/dev/null || true)
if [ -z "$ext_refs" ]; then
  echo "  PASS — no external registry references"
else
  echo "  FAIL — external refs found:"
  echo "$ext_refs" | head -5
fi
echo ""

# ── CI Config ─────────────────────────────────────────────────────────────
echo "## CI"
ci_files=$(find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | sort)
if [ -n "$ci_files" ]; then
  echo "$ci_files" | while read -r f; do echo "  $f"; done
else
  echo "  No CI workflows found"
fi
echo ""
