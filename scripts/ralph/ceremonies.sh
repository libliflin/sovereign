#!/usr/bin/env bash
# ceremonies.sh — Full sprint orchestrator for the Sovereign Platform
# Usage: ./ceremonies.sh [--phase N] [--tool claude|amp] [--max-retries 3] [--dry-run] [--skip-plan]
#
# Architecture:
#   BASH enforces all binary gates. AI handles reasoning + code generation only.
#   Gate failures write structured JSON to the sprint file so the next execute
#   iteration starts with a specific failure brief (ralph.sh Layer 2).
#
# Full sequence:
#   0. PLAN        — AI populates sprint from backlog (skipped if sprint active)
#   1. PRE-FLIGHT  — BASH: tools, cluster, credentials. Hard exit + remediation on fail.
#   2. SMART CHECK — AI scores; BASH reads JSON, hard-exits if any score < 3
#   3. EXECUTE     — ralph.sh (AI generates code, reads failure context from sprint file)
#                    Clears stale failure context at start of each attempt.
#   4. SMOKE TEST  — BASH: helm lint, bash syntax, shellcheck, jq, kubectl --dry-run
#                    Writes specific failure output to sprint._lastSmokeTestFailures[]
#   5. PROOF CHECK — BASH: git ls-remote + gh pr list
#                    Writes specific failure detail to sprint._lastProofOfWorkFailures[]
#   6. REVIEW      — AI adversarial AC check; BASH reads story JSON (no signal files)
#   7. RETRO       — AI extracts learnings to progress.txt
#   8. ADVANCE     — BASH updates manifest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/prd/manifest.json"

# ── Defaults ──────────────────────────────────────────────────────────────────
TOOL="claude"
MAX_RETRIES=3
DRY_RUN=false
SKIP_PLAN=false
PHASE_OVERRIDE=""
RALPH_MAX_ITER=10

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --phase)         PHASE_OVERRIDE="$2"; shift 2 ;;
    --phase=*)       PHASE_OVERRIDE="${1#*=}"; shift ;;
    --tool)          TOOL="$2"; shift 2 ;;
    --tool=*)        TOOL="${1#*=}"; shift ;;
    --max-retries)   MAX_RETRIES="$2"; shift 2 ;;
    --max-retries=*) MAX_RETRIES="${1#*=}"; shift ;;
    --dry-run)       DRY_RUN=true; shift ;;
    --skip-plan)     SKIP_PLAN=true; shift ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--phase N] [--tool claude|amp] [--max-retries 3] [--dry-run] [--skip-plan]" >&2
      exit 1 ;;
  esac
done

if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'." >&2; exit 1
fi
command -v jq &>/dev/null || { echo "ERROR: jq is required" >&2; exit 1; }

# ── Resolve active sprint ─────────────────────────────────────────────────────
resolve_sprint() {
  if [[ -n "$PHASE_OVERRIDE" ]]; then
    ACTIVE_SPRINT=$(jq -r ".phases[] | select(.id == $PHASE_OVERRIDE) | .file" \
      "$MANIFEST" 2>/dev/null || echo "")
    [[ -z "$ACTIVE_SPRINT" || "$ACTIVE_SPRINT" == "null" ]] && \
      { echo "ERROR: Phase $PHASE_OVERRIDE not found in $MANIFEST" >&2; exit 1; }
  else
    ACTIVE_SPRINT=$(jq -r '.activeSprint // empty' "$MANIFEST" 2>/dev/null || echo "")
    [[ -z "$ACTIVE_SPRINT" || "$ACTIVE_SPRINT" == "null" ]] && \
      { echo "ERROR: No activeSprint in $MANIFEST — use --phase N or run plan ceremony first" >&2; exit 1; }
  fi
  SPRINT_FILE="$REPO_ROOT/$ACTIVE_SPRINT"
  PHASE_NUM=$(jq -r '.currentPhase // "unknown"' "$MANIFEST" 2>/dev/null || echo "unknown")
  if [[ -n "$PHASE_OVERRIDE" ]]; then PHASE_NUM="$PHASE_OVERRIDE"; fi
}

resolve_sprint

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_DIR="$REPO_ROOT/prd/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/phase-${PHASE_NUM}-${TIMESTAMP}.log"

log()     { echo "$*" | tee -a "$LOG_FILE"; }
log_sep() { log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
die()     { log ""; log "FATAL: $*"; log "Ceremonies aborted. Log: $LOG_FILE"; exit 1; }

# ── Story state helpers (bash reads JSON — agent never self-reports) ───────────
stories_total()    { jq '.stories | length' "$SPRINT_FILE" 2>/dev/null || echo "0"; }
stories_passing()  { jq '[.stories[] | select(.passes == true)] | length'  "$SPRINT_FILE" 2>/dev/null || echo "0"; }
stories_reviewed() { jq '[.stories[] | select(.reviewed == true)] | length' "$SPRINT_FILE" 2>/dev/null || echo "0"; }
stories_reopened() {
  jq '[.stories[] | select(.passes == false and (.attempts // 0) > 0)] | length' \
    "$SPRINT_FILE" 2>/dev/null || echo "0"
}

# ── Helper: write a JSON array to sprint file field (uses temp file to avoid quoting issues) ──
write_sprint_failures() {
  local field="$1"      # e.g. _lastSmokeTestFailures
  local array_file="$2" # path to file containing JSON array
  python3 - "$SPRINT_FILE" "$field" "$array_file" <<'PYEOF'
import json, sys
sprint_file, field, array_file = sys.argv[1], sys.argv[2], sys.argv[3]
with open(sprint_file) as f:  sprint = json.load(f)
with open(array_file) as f:   failures = json.load(f)
if failures:
    sprint[field] = failures
else:
    sprint.pop(field, None)
with open(sprint_file, 'w') as f:
    json.dump(sprint, f, indent=2)
print(f"  {field}: {len(failures)} entry/entries written to sprint file.")
PYEOF
}

# ── Helper: clear all failure context fields (called at start of each execute) ─
clear_failure_context() {
  python3 - "$SPRINT_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f: sprint = json.load(f)
sprint.pop('_lastSmokeTestFailures', None)
sprint.pop('_lastProofOfWorkFailures', None)
with open(sys.argv[1], 'w') as f: json.dump(sprint, f, indent=2)
PYEOF
}

# ── Helper: reset all passing stories to passes:false with a reason ───────────
reset_passing_stories() {
  local reason="$1"
  python3 - "$SPRINT_FILE" "$reason" <<'PYEOF'
import json, sys
sprint_file, reason = sys.argv[1], sys.argv[2]
with open(sprint_file) as f: sprint = json.load(f)
changed = 0
for story in sprint['stories']:
    if story.get('passes') is True:
        story['passes'] = False
        story.setdefault('reviewNotes', []).append(reason)
        changed += 1
with open(sprint_file, 'w') as f: json.dump(sprint, f, indent=2)
print(f"  Reset {changed} stories to passes:false.")
PYEOF
}

# ── Rate limit handler ────────────────────────────────────────────────────────
# Detects "You've hit your limit · resets Xam (Timezone)" in output.
# Sleeps until that time + 5min buffer. Returns 1 if limited, 0 if not.
handle_rate_limit() {
  local output="$1"
  echo "$output" | grep -q "You've hit your limit" || return 0

  log ""
  log "⏸  Rate limit reached."

  local sleep_secs out_tmp
  out_tmp=$(mktemp /tmp/sovereign-rl-XXXXXX.txt)
  echo "$output" > "$out_tmp"
  sleep_secs=$(python3 - "$out_tmp" 2>/dev/null <<'PYEOF'
import sys, re
from datetime import datetime, timedelta

with open(sys.argv[1]) as f:
    output = f.read()

m = re.search(r'resets (\d{1,2}(?:am|pm)) \(([^)]+)\)', output, re.IGNORECASE)

if not m:
    print(3600)
    sys.exit(0)

reset_str = m.group(1).lower()
tz_name   = m.group(2)
print(f"   Resets at: {m.group(1)} ({tz_name})", file=sys.stderr)

try:
    from zoneinfo import ZoneInfo
    tz = ZoneInfo(tz_name)
    now = datetime.now(tz)
except Exception:
    from datetime import timezone
    now = datetime.now(timezone.utc)
    print(f"   Warning: unknown timezone '{tz_name}', falling back to UTC", file=sys.stderr)

is_pm = reset_str.endswith('pm')
hour  = int(reset_str[:-2])
if is_pm and hour != 12:
    hour += 12
elif not is_pm and hour == 12:
    hour = 0

target = now.replace(hour=hour, minute=5, second=0, microsecond=0)
if target <= now:
    target += timedelta(days=1)

print(int((target - now).total_seconds()))
PYEOF
  )
  rm -f "$out_tmp"

  if [[ -z "$sleep_secs" ]] || ! [[ "$sleep_secs" =~ ^[0-9]+$ ]] || [[ "$sleep_secs" -le 0 ]]; then
    log "   Could not parse reset time. Sleeping 1 hour."
    sleep_secs=3600
  fi

  local h=$(( sleep_secs / 3600 ))
  local m=$(( (sleep_secs % 3600) / 60 ))
  log "   Sleeping ${h}h ${m}m (5min buffer after reset)"
  sleep "$sleep_secs"
  log ""
  log "▶  Resuming after rate limit reset."
  return 1  # signal: was rate limited — caller should retry
}

# ── Helper: run an AI ceremony (reasoning only — bash verifies outcomes) ───────
# Retries automatically on rate limit without consuming a ceremony attempt.
run_ceremony() {
  local name="$1"
  local file="$2"
  log_sep
  log "  AI CEREMONY: $name"
  log_sep

  local output
  while true; do
    output=""
    if [[ "$TOOL" == "claude" ]]; then
      output=$(claude --dangerously-skip-permissions --print < "$file" 2>&1 | tee -a "$LOG_FILE") || true
    else
      output=$(amp --dangerously-allow-all < "$file" 2>&1 | tee -a "$LOG_FILE") || true
    fi

    handle_rate_limit "$output" && break
    log "  Retrying ceremony: $name"
  done
}

# ── DRY RUN ───────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  cat <<EOF
=== ceremonies.sh DRY RUN ===

Active sprint : $ACTIVE_SPRINT
Sprint file   : $SPRINT_FILE
Tool          : $TOOL
Max retries   : $MAX_RETRIES
Log file      : $LOG_FILE

Steps that WOULD execute:
  0. PLAN        — AI: backlog → sprint file (skipped if sprint active/exists)
  1. PRE-FLIGHT  — BASH: required tools, docker+kind, git remote (hard exit + remediation)
  2. SMART CHECK — AI scores stories; BASH hard-exits if any score < 3
  3. EXECUTE     — ralph.sh with failure context injected into prompt
                   (stale failure context cleared at start of each attempt)
  4. SMOKE TEST  — BASH: helm lint, bash -n, shellcheck, jq, kubectl --dry-run
                   Failures written to sprint._lastSmokeTestFailures[]
  5. PROOF CHECK — BASH: git ls-remote, gh pr list
                   Failures written to sprint._lastProofOfWorkFailures[]
  6. REVIEW      — AI adversarial AC check; BASH reads story JSON for re-opens
  7. RETRO       — AI learnings extraction
  8. ADVANCE     — BASH manifest update

No files modified (--dry-run).
EOF
  exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
log ""
log "══════════════════════════════════════════════════════════════════"
log "  PHASE $PHASE_NUM SPRINT CEREMONIES  —  $(date)"
log "  Sprint : $ACTIVE_SPRINT"
log "  Log    : $LOG_FILE"
log "══════════════════════════════════════════════════════════════════"

# ── Restore sprint file if previous run left it dirty ────────────────────────
# ceremonies.sh can exit mid-run (via die()) while the sprint file has been
# modified by a smoke-test reset (stories set to passes:false). Always restore
# from committed state so we never inherit stale resets from an aborted run.
if [[ -f "$SPRINT_FILE" ]]; then
  if ! git -C "$REPO_ROOT" diff --quiet HEAD -- "$ACTIVE_SPRINT" 2>/dev/null; then
    log ""
    log "  ⚠ Sprint file has uncommitted changes — restoring from HEAD."
    log "    (Previous ceremonies.sh likely exited during a smoke-test reset.)"
    log "    Commit intentional story updates before running ceremonies.sh."
    git -C "$REPO_ROOT" restore -- "$ACTIVE_SPRINT" 2>/dev/null || true
    log "  ✓ Sprint file restored to committed state."
  fi
fi

# ── STEP 0: PLAN ──────────────────────────────────────────────────────────────
PHASE_STATUS=$(jq -r ".phases[] | select(.file == \"$ACTIVE_SPRINT\") | .status" \
  "$MANIFEST" 2>/dev/null || echo "unknown")

if [[ "$SKIP_PLAN" == false ]] && { [[ ! -f "$SPRINT_FILE" ]] || [[ "$PHASE_STATUS" == "pending" ]]; }; then
  log ""
  log "STEP 0/8 — SPRINT PLANNING"
  log "  Phase status: $PHASE_STATUS. Sprint file: $([ -f "$SPRINT_FILE" ] && echo exists || echo MISSING)"
  log "  Running plan ceremony to select stories from backlog..."
  run_ceremony "Sprint Planning" "$SCRIPT_DIR/ceremonies/plan.md"
  resolve_sprint
  [[ -f "$SPRINT_FILE" ]] || die "Plan ceremony ran but sprint file still missing: $SPRINT_FILE"
  log ""
  log "✓ Sprint file ready: $SPRINT_FILE ($(stories_total) stories)"
else
  log ""
  log "STEP 0/8 — SPRINT PLANNING: skipped (sprint exists, phase=$PHASE_STATUS)"
fi

# ── STEP 1: PRE-FLIGHT (BASH — no AI, hard exit with remediation) ─────────────
log ""
log "STEP 1/8 — PRE-FLIGHT (bash-enforced)"
log_sep
PREFLIGHT_FAIL=0

check_tool() {
  local tool="$1" required="${2:-true}" fix="${3:-}"
  if command -v "$tool" &>/dev/null; then
    log "  ✓ $tool ($(command -v "$tool"))"
  elif [[ "$required" == "true" ]]; then
    log "  ✗ MISSING (required): $tool"
    if [[ -n "$fix" ]]; then log "    → Fix: $fix"; fi
    PREFLIGHT_FAIL=1
  else
    log "  ~ MISSING (optional): $tool"
    if [[ -n "$fix" ]]; then log "    → To install: $fix"; fi
  fi
}

log "  Core tools:"
check_tool jq       true "brew install jq"
check_tool git      true "brew install git"
check_tool helm     true "brew install helm"
check_tool kubectl  true "brew install kubectl"
check_tool gh       true "brew install gh && gh auth login --web"

log "  Code quality:"
check_tool shellcheck true "brew install shellcheck"
check_tool yq         true "brew install yq"

log "  Kind/Docker:"
NEEDS_KIND=$(jq -e '[.stories[].requiredCapabilities[]? | select(. == "kind")] | length > 0' \
  "$SPRINT_FILE" 2>/dev/null && echo "true" || echo "false")

if [[ "$NEEDS_KIND" == "true" ]]; then
  check_tool kind true "brew install kind"

  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      log "  ✓ Docker daemon running"
    else
      log "  ✗ Docker daemon not running"
      log "    → Fix: open Docker Desktop (or: systemctl start docker)"
      PREFLIGHT_FAIL=1
    fi
  else
    log "  ✗ MISSING (required for kind stories): docker"
    log "    → Fix: install Docker Desktop from https://www.docker.com/products/docker-desktop"
    PREFLIGHT_FAIL=1
  fi

  log "  Checking for active kind cluster..."
  if command -v kind &>/dev/null && kind get clusters 2>/dev/null | grep -q "sovereign"; then
    CLUSTER=$(kind get clusters 2>/dev/null | grep "sovereign" | head -1)
    log "  ✓ kind cluster '$CLUSTER' exists"
  else
    log "  ✗ No kind cluster found matching 'sovereign-*'"
    log "    → Fix: ./kind/setup.sh"
    log "    → Expected cluster name: sovereign-test (single-node) or sovereign-ha (3-node)"
    log "    → Estimated setup time: ~3 minutes"
    PREFLIGHT_FAIL=1
  fi
else
  log "  ~ kind/Docker not required by any story in this sprint"
fi

log "  git remote:"
if git -C "$REPO_ROOT" ls-remote origin HEAD &>/dev/null 2>&1; then
  REMOTE_URL=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "unknown")
  log "  ✓ origin reachable ($REMOTE_URL)"
else
  log "  ✗ git remote 'origin' not reachable"
  log "    → Fix: check VPN/network, or: git remote set-url origin <correct-url>"
  PREFLIGHT_FAIL=1
fi

if command -v gh &>/dev/null; then
  if gh auth status &>/dev/null 2>&1; then
    GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
    log "  ✓ gh authenticated as: $GH_USER"
  else
    log "  ✗ gh not authenticated (required for PR proof-of-work check)"
    log "    → Fix: gh auth login --web"
    PREFLIGHT_FAIL=1
  fi
fi

[[ $PREFLIGHT_FAIL -ne 0 ]] && die "Pre-flight failed. Fix the issues above and re-run ceremonies.sh."
log ""
log "✓ Pre-flight passed — all required capabilities present."

# ── STEP 2: SMART CHECK ───────────────────────────────────────────────────────
log ""
log "STEP 2/8 — SMART CHECK"
log "  (AI scores stories; bash reads the JSON and hard-exits if any score < 3)"

run_ceremony "SMART Check" "$SCRIPT_DIR/ceremonies/smart-check.md"

NOT_SMART=$(jq '[.stories[] | select(
  (.smart.specific   // 0) < 3 or (.smart.measurable // 0) < 3 or
  (.smart.achievable // 0) < 3 or (.smart.relevant   // 0) < 3 or
  (.smart.timeBound  // 0) < 3
)] | length' "$SPRINT_FILE" 2>/dev/null || echo "0")

if [[ "$NOT_SMART" -gt 0 ]]; then
  log ""
  log "SMART CHECK FAILED: $NOT_SMART stories scored < 3 on at least one dimension:"
  jq -r '.stories[] | select(
    (.smart.specific   // 0) < 3 or (.smart.measurable // 0) < 3 or
    (.smart.achievable // 0) < 3 or (.smart.relevant   // 0) < 3 or
    (.smart.timeBound  // 0) < 3
  ) | "  - \(.id): \(.title)\n    \(.smart.notes // "(no notes)")"' \
    "$SPRINT_FILE" 2>/dev/null | tee -a "$LOG_FILE" || true
  die "Refine failing stories and re-run ceremonies.sh."
fi
log ""
log "✓ SMART check passed — all $(stories_total) stories are sprint-ready."

# ── STEP 3-6: EXECUTE → SMOKE → PROOF → REVIEW loop ─────────────────────────
RETRY=0
while [[ $RETRY -le $MAX_RETRIES ]]; do
  [[ $RETRY -gt 0 ]] && log "" && log "─── RETRY $RETRY of $MAX_RETRIES ───────────────────────────────────────────"

  # ── 3: EXECUTE ──────────────────────────────────────────────────────────────
  log ""
  log "STEP 3/8 — EXECUTE"

  # Check state before calling ralph — if everything already passes, skip execute.
  # This prevents ralph from running 10 iterations asking "what should I do?"
  NEEDS_WORK=$(jq '[.stories[] | select(.passes == false)] | length' \
    "$SPRINT_FILE" 2>/dev/null || echo "1")

  if [[ "$NEEDS_WORK" -eq 0 ]]; then
    log "  All $(stories_total) stories already passing — skipping execute."
    log "  Proceeding directly to smoke test."
  else
    log "  Stories needing work: $NEEDS_WORK / $(stories_total)"
    log "  Clearing stale failure context from previous attempt..."
    clear_failure_context

    log "  Running ralph.sh --prd $ACTIVE_SPRINT --tool $TOOL $RALPH_MAX_ITER"
    log "  (ralph.sh will inject current failure context into agent prompt if any)"
    log ""
    RALPH_EXIT=0
    "$SCRIPT_DIR/ralph.sh" --prd "$ACTIVE_SPRINT" --tool "$TOOL" "$RALPH_MAX_ITER" \
      2>&1 | tee -a "$LOG_FILE" || RALPH_EXIT=$?
    [[ $RALPH_EXIT -ne 0 ]] && log "  WARNING: ralph.sh exited $RALPH_EXIT (may have hit max iterations)"
    log ""
    log "  Stories passing after execute: $(stories_passing) / $(stories_total)"
  fi

  # ── 4: SMOKE TEST (bash — no AI) ────────────────────────────────────────────
  log ""
  log "STEP 4/8 — SMOKE TEST (bash-enforced)"
  log_sep
  SMOKE_FAIL=0
  SMOKE_FAILURES=()  # bash array; each element is a JSON object

  # 4a: helm lint
  log "  helm lint:"
  CHART_FAIL=0
  for chart_yaml in "$REPO_ROOT"/charts/*/Chart.yaml; do
    chart_dir=$(dirname "$chart_yaml")
    chart_name=$(basename "$chart_dir")
    HELM_EXIT=0
    HELM_OUT=$(helm lint "$chart_dir" 2>&1) || HELM_EXIT=$?
    echo "$HELM_OUT" | tee -a "$LOG_FILE"
    if [[ $HELM_EXIT -eq 0 ]]; then
      log "    ✓ $chart_name"
    else
      log "    ✗ FAIL: $chart_name"
      OUT_JSON=$(printf '%s' "$HELM_OUT" | head -c 3000 | jq -Rs '.')
      SMOKE_FAILURES+=("{\"type\":\"helm-lint\",\"target\":\"charts/${chart_name}\",\"output\":${OUT_JSON}}")
      CHART_FAIL=1; SMOKE_FAIL=1
    fi
  done
  [[ $CHART_FAIL -eq 0 ]] && log "    all charts passed"

  # 4b: bash -n syntax + shellcheck lint on all scripts
  log "  bash syntax + shellcheck:"
  SHELL_FAIL_LOCAL=0
  while IFS= read -r -d '' script; do
    rel="${script#"$REPO_ROOT/"}"
    BASH_EXIT=0; SC_EXIT=0
    BASH_OUT=$(bash -n "$script" 2>&1) || BASH_EXIT=$?
    SC_OUT=$(shellcheck "$script" 2>&1) || SC_EXIT=$?
    if [[ $BASH_EXIT -eq 0 && $SC_EXIT -eq 0 ]]; then
      log "    ✓ $rel"
    else
      log "    ✗ FAIL: $rel"
      COMBINED="bash -n output:
${BASH_OUT}
shellcheck output:
${SC_OUT}"
      OUT_JSON=$(printf '%s' "$COMBINED" | head -c 3000 | jq -Rs '.')
      SMOKE_FAILURES+=("{\"type\":\"shellcheck\",\"target\":\"${rel}\",\"output\":${OUT_JSON}}")
      SHELL_FAIL_LOCAL=1; SMOKE_FAIL=1
    fi
  done < <(find "$REPO_ROOT/bootstrap" "$REPO_ROOT/scripts" \
    -name "*.sh" -not -path "*/.git/*" -print0 2>/dev/null)
  [[ $SHELL_FAIL_LOCAL -eq 0 ]] && log "    all scripts passed"

  # 4c: JSON validation
  log "  JSON validation (prd/):"
  JSON_FAIL_LOCAL=0
  while IFS= read -r -d '' json_file; do
    rel="${json_file#"$REPO_ROOT/"}"
    JQ_EXIT=0
    JQ_OUT=$(jq empty "$json_file" 2>&1) || JQ_EXIT=$?
    if [[ $JQ_EXIT -eq 0 ]]; then
      log "    ✓ $rel"
    else
      log "    ✗ FAIL: $rel"
      OUT_JSON=$(printf '%s' "$JQ_OUT" | jq -Rs '.')
      SMOKE_FAILURES+=("{\"type\":\"json-invalid\",\"target\":\"${rel}\",\"output\":${OUT_JSON}}")
      JSON_FAIL_LOCAL=1; SMOKE_FAIL=1
    fi
  done < <(find "$REPO_ROOT/prd" -name "*.json" -not -path "*/.git/*" -print0 2>/dev/null)
  [[ $JSON_FAIL_LOCAL -eq 0 ]] && log "    all JSON files valid"

  # 4d: YAML syntax check for argocd-apps/ manifests
  # ArgoCD Application/AppProject CRDs may not be installed in the test cluster, so
  # kubectl dry-run cannot be used. Validate YAML syntax with yq instead — it parses
  # the YAML without needing any CRD schema, catching malformed manifests at the gate.
  log "  YAML syntax check (argocd-apps/):"
  YAML_FAIL=0
  while IFS= read -r -d '' yaml_file; do
    rel="${yaml_file#"$REPO_ROOT/"}"
    YAML_EXIT=0
    yq e '.' "$yaml_file" > /dev/null 2>&1 || YAML_EXIT=$?
    if [[ $YAML_EXIT -eq 0 ]]; then
      log "    ✓ $rel"
    else
      YAML_ERR=$(yq e '.' "$yaml_file" 2>&1 | head -c 3000)
      log "    ✗ FAIL: $rel"
      OUT_JSON=$(printf '%s' "$YAML_ERR" | jq -Rs '.')
      SMOKE_FAILURES+=("{\"type\":\"yaml-syntax\",\"target\":\"${rel}\",\"output\":${OUT_JSON}}")
      YAML_FAIL=1; SMOKE_FAIL=1
    fi
  done < <(find "$REPO_ROOT/argocd-apps" -name "*.yaml" -print0 2>/dev/null)
  [[ $YAML_FAIL -eq 0 ]] && log "    all ArgoCD manifests valid"

  # Write smoke test results to sprint file (clears on pass, records specifics on fail)
  SMOKE_TMP=$(mktemp /tmp/sovereign-smoke-XXXXXX.json)
  if [[ ${#SMOKE_FAILURES[@]} -gt 0 ]]; then
    printf '%s\n' "${SMOKE_FAILURES[@]}" | jq -s '.' > "$SMOKE_TMP"
  else
    echo "[]" > "$SMOKE_TMP"
  fi
  write_sprint_failures "_lastSmokeTestFailures" "$SMOKE_TMP" | tee -a "$LOG_FILE"
  rm -f "$SMOKE_TMP"

  if [[ $SMOKE_FAIL -ne 0 ]]; then
    log ""
    log "SMOKE TEST FAILED (${#SMOKE_FAILURES[@]} check(s) failed)"
    log "  Failure details written to sprint._lastSmokeTestFailures[]"
    log "  ralph.sh will inject these into the agent prompt on next execute."
    reset_passing_stories "[SMOKE-TEST-FAIL] Gates failed — see _lastSmokeTestFailures in sprint file." \
      | tee -a "$LOG_FILE"
    RETRY=$((RETRY + 1))
    if [[ $RETRY -le $MAX_RETRIES ]]; then
      log "  Retrying execute (attempt $RETRY of $MAX_RETRIES)..."
      continue
    else
      die "Smoke test failed after $MAX_RETRIES retries. Manual intervention required."
    fi
  fi
  log ""
  log "✓ Smoke test passed."

  # ── 5: PROOF OF WORK (bash — git ls-remote + gh pr list) ─────────────────
  log ""
  log "STEP 5/8 — PROOF OF WORK (bash-enforced)"
  log_sep
  PROOF_FAIL=0
  PROOF_FAILURES=()

  SPRINT_BRANCH=$(jq -r '.branchName // empty' "$SPRINT_FILE" 2>/dev/null || echo "")

  check_branch_pushed() {
    local branch="$1"
    if [[ -z "$branch" ]]; then return 0; fi
    # Branch still exists on remote (open PR or not yet deleted)
    if git -C "$REPO_ROOT" ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
      log "  ✓ pushed: origin/$branch"
      return 0
    fi
    # Branch was deleted after squash-merge — check if a merged PR exists for it
    if command -v gh &>/dev/null; then
      local merged_pr
      merged_pr=$(gh pr list --state merged --head "$branch" --json number --jq '.[0].number' 2>/dev/null || echo "")
      if [[ -n "$merged_pr" && "$merged_pr" != "null" ]]; then
        log "  ✓ pushed: origin/$branch (branch deleted post-merge — PR #$merged_pr merged)"
        return 0
      fi
    fi
    log "  ✗ NOT pushed: $branch"
    log "    → Fix: git push origin $branch"
    PROOF_FAILURES+=("{\"type\":\"branch-not-pushed\",\"detail\":\"Branch '${branch}' not found on origin. Run: git push origin ${branch}\"}")
    PROOF_FAIL=1
  }

  check_pr_exists() {
    local branch="$1"
    if [[ -z "$branch" ]]; then return 0; fi
    if ! command -v gh &>/dev/null; then return 0; fi
    local pr_num
    # Check open PRs first, then merged (squash-merge deletes the branch)
    pr_num=$(gh pr list --state all --head "$branch" --json number --jq '.[0].number' 2>/dev/null || echo "")
    if [[ -n "$pr_num" && "$pr_num" != "null" ]]; then
      log "  ✓ PR #$pr_num exists for $branch"
    else
      log "  ✗ No PR found for: $branch"
      log "    → Fix: gh pr create --head $branch --base main --title '...'"
      PROOF_FAILURES+=("{\"type\":\"no-pr\",\"detail\":\"No pull request found for branch '${branch}'. Run: gh pr create --head ${branch} --base main\"}")
      PROOF_FAIL=1
    fi
  }

  if [[ -n "$SPRINT_BRANCH" ]]; then
    log "  Sprint branch: $SPRINT_BRANCH"
    check_branch_pushed "$SPRINT_BRANCH"
    check_pr_exists "$SPRINT_BRANCH"
  else
    log "  No sprint-level branchName — checking per-story branches..."
    while IFS= read -r story_branch; do
      [[ -z "$story_branch" || "$story_branch" == "null" ]] && continue
      check_branch_pushed "$story_branch"
      check_pr_exists "$story_branch"
    done < <(jq -r '.stories[] | select(.passes == true) | .branchName // empty' \
      "$SPRINT_FILE" 2>/dev/null)
  fi

  # Write proof failures to sprint file
  PROOF_TMP=$(mktemp /tmp/sovereign-proof-XXXXXX.json)
  if [[ ${#PROOF_FAILURES[@]} -gt 0 ]]; then
    printf '%s\n' "${PROOF_FAILURES[@]}" | jq -s '.' > "$PROOF_TMP"
  else
    echo "[]" > "$PROOF_TMP"
  fi
  write_sprint_failures "_lastProofOfWorkFailures" "$PROOF_TMP" | tee -a "$LOG_FILE"
  rm -f "$PROOF_TMP"

  if [[ $PROOF_FAIL -ne 0 ]]; then
    log ""
    log "PROOF OF WORK FAILED (${#PROOF_FAILURES[@]} check(s) failed)"
    log "  Failure details written to sprint._lastProofOfWorkFailures[]"
    log "  ralph.sh will inject these into the agent prompt on next execute."
    reset_passing_stories "[PROOF-FAIL] Branch not pushed or no PR — see _lastProofOfWorkFailures." \
      | tee -a "$LOG_FILE"
    RETRY=$((RETRY + 1))
    if [[ $RETRY -le $MAX_RETRIES ]]; then
      log "  Retrying execute (attempt $RETRY of $MAX_RETRIES)..."
      continue
    else
      die "Proof-of-work failed after $MAX_RETRIES retries. Agent must push + create PR."
    fi
  fi
  log ""
  log "✓ Proof of work verified — all branches pushed and PRs exist."

  # ── 6: REVIEW ───────────────────────────────────────────────────────────────
  log ""
  log "STEP 6/8 — REVIEW"
  log "  (AI checks ACs adversarially; bash reads story JSON to detect re-opens)"

  PASSING_BEFORE=$(stories_passing)
  run_ceremony "Review" "$SCRIPT_DIR/ceremonies/review.md"

  PASSING_AFTER=$(stories_passing)
  REOPENED=$(stories_reopened)
  log ""
  log "  Passing before review : $PASSING_BEFORE"
  log "  Passing after review  : $PASSING_AFTER"
  log "  Re-opened by review   : $REOPENED"

  if [[ "$REOPENED" -gt 0 ]] || [[ "$PASSING_AFTER" -lt "$PASSING_BEFORE" ]]; then
    RETRY=$((RETRY + 1))
    if [[ $RETRY -gt $MAX_RETRIES ]]; then
      python3 - "$SPRINT_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f: sprint = json.load(f)
for story in sprint['stories']:
    if not story.get('reviewed') and not story.get('passes'):
        story.setdefault('reviewNotes', []).append(
            f"[BLOCKED] Max retries exceeded after {story.get('attempts', 0)} attempt(s). Manual intervention required.")
with open(sys.argv[1], 'w') as f: json.dump(sprint, f, indent=2)
print("Blocked stories updated.")
PYEOF
      break
    fi
    log "  Stories re-opened. Retrying from execute (attempt $RETRY of $MAX_RETRIES)..."
    continue
  fi

  log ""
  log "✓ Review passed — $(stories_passing)/$(stories_total) stories accepted."
  break
done

# ── STEP 7: RETRO ─────────────────────────────────────────────────────────────
log ""
log "STEP 7/8 — RETRO"
run_ceremony "Retrospective" "$SCRIPT_DIR/ceremonies/retro.md"

# ── STEP 8: ADVANCE ───────────────────────────────────────────────────────────
log ""
log "STEP 8/8 — ADVANCE"

NOT_ACCEPTED=$(jq '[.stories[] | select(.reviewed != true)] | length' \
  "$SPRINT_FILE" 2>/dev/null || echo "99")
if [[ "$NOT_ACCEPTED" -gt 0 ]]; then
  log ""
  log "WARNING: $NOT_ACCEPTED stories not yet accepted (reviewed:true)."
  log "  Re-run ceremonies.sh --skip-plan to retry without re-planning."
  log "  Sprint log: $LOG_FILE"
  exit 1
fi

ADVANCE_SCRIPT="$REPO_ROOT/prd/advance.sh"
if [[ -x "$ADVANCE_SCRIPT" ]]; then
  log "All stories accepted. Running prd/advance.sh..."
  "$ADVANCE_SCRIPT" 2>&1 | tee -a "$LOG_FILE"
else
  log "  ~ prd/advance.sh not found/executable — manually advance $MANIFEST"
fi

log ""
log "══════════════════════════════════════════════════════════════════"
log "  SPRINT COMPLETE ✓ — Phase $PHASE_NUM accepted"
log "  $(stories_total) stories delivered."
log "  Log: $LOG_FILE"
log "══════════════════════════════════════════════════════════════════"
