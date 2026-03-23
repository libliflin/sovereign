#!/usr/bin/env bash
# ceremonies.sh — Full sprint orchestrator for the Sovereign Platform
# Usage: ./ceremonies.sh [--phase N] [--tool claude|amp] [--max-retries 3] [--dry-run] [--skip-plan]
#
# Design principle:
#   BASH enforces binary gates (pre-flight, smoke test, proof-of-work, story state).
#   AI does reasoning and code generation (plan, SMART check, execute, retro).
#   The agent is NEVER asked to self-certify a binary fact. If a check fails, the
#   shell exits non-zero. No "flagging and proceeding."
#
# Full sequence:
#   0. PLAN        — AI populates sprint file from backlog (skipped if sprint already active)
#   1. PRE-FLIGHT  — BASH checks: required tools, cluster access, credentials (hard exit on fail)
#   2. SMART CHECK — AI scores stories; BASH reads JSON and hard-exits if any score < 3
#   3. EXECUTE     — ralph.sh loop (AI does the work)
#   4. SMOKE TEST  — BASH runs: helm lint, shellcheck, bash -n, kubectl --dry-run, JSON validate
#   5. PROOF CHECK — BASH runs: git ls-remote (branch pushed?), gh pr list (PR exists?)
#   6. REVIEW      — AI adversarial AC check; BASH reads story JSON to detect re-opened stories
#   7. RETRO       — AI extracts learnings to progress.txt
#   8. ADVANCE     — BASH updates manifest, advances to next phase
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/prd/manifest.json"

# ── Defaults ────────────────────────────────────────────────────────────────
TOOL="claude"
MAX_RETRIES=3
DRY_RUN=false
SKIP_PLAN=false
PHASE_OVERRIDE=""
RALPH_MAX_ITER=10

# ── Argument parsing ─────────────────────────────────────────────────────────
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
      exit 1
      ;;
  esac
done

if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'." >&2; exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required" >&2; exit 1
fi

# ── Resolve active sprint ────────────────────────────────────────────────────
resolve_sprint() {
  if [[ -n "$PHASE_OVERRIDE" ]]; then
    ACTIVE_SPRINT=$(jq -r ".phases[] | select(.id == $PHASE_OVERRIDE) | .file" "$MANIFEST" 2>/dev/null || echo "")
    if [[ -z "$ACTIVE_SPRINT" || "$ACTIVE_SPRINT" == "null" ]]; then
      echo "ERROR: Phase $PHASE_OVERRIDE not found in $MANIFEST" >&2; exit 1
    fi
  else
    ACTIVE_SPRINT=$(jq -r '.activeSprint // empty' "$MANIFEST" 2>/dev/null || echo "")
    if [[ -z "$ACTIVE_SPRINT" || "$ACTIVE_SPRINT" == "null" ]]; then
      echo "ERROR: No activeSprint in $MANIFEST and no --phase given." >&2
      echo "       Run with --skip-plan=false (default) to let the plan ceremony create one." >&2
      exit 1
    fi
  fi
  SPRINT_FILE="$REPO_ROOT/$ACTIVE_SPRINT"
  PHASE_NUM=$(jq -r '.currentPhase // "unknown"' "$MANIFEST" 2>/dev/null || echo "unknown")
  [[ -n "$PHASE_OVERRIDE" ]] && PHASE_NUM="$PHASE_OVERRIDE"
}

resolve_sprint

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_DIR="$REPO_ROOT/prd/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/phase-${PHASE_NUM}-${TIMESTAMP}.log"

log()  { echo "$*" | tee -a "$LOG_FILE"; }
log_sep() { log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
die()  { log ""; log "FATAL: $*"; log "Ceremonies aborted. Log: $LOG_FILE"; exit 1; }

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
  0. PLAN        — AI: populates sprint from backlog (skipped if sprint already active)
  1. PRE-FLIGHT  — BASH: which helm/kubectl/kind/shellcheck/gh, docker info, kind cluster exists
                   Hard exit if a required tool is missing. No "flagging and proceeding."
  2. SMART CHECK — AI scores stories; BASH reads JSON, hard-exits if any score < 3
  3. EXECUTE     — ralph.sh --prd $ACTIVE_SPRINT --tool $TOOL $RALPH_MAX_ITER
  4. SMOKE TEST  — BASH: helm lint charts/, shellcheck bootstrap/, kubectl --dry-run, jq validate
                   Hard exit if any artifact fails. Marks failing stories passes:false in JSON.
  5. PROOF CHECK — BASH: git ls-remote origin <branch>, gh pr list --head <branch>
                   Hard exit if branch not pushed or no PR exists.
  6. REVIEW      — AI adversarial AC check; BASH reads story JSON to detect re-opened stories
  7. RETRO       — AI extracts learnings to progress.txt
  8. ADVANCE     — BASH: updates manifest, sets next phase active

No files modified (--dry-run).
EOF
  exit 0
fi

# ── Helper: run an AI ceremony (reasoning only — no binary verification) ──────
run_ceremony() {
  local name="$1"
  local file="$2"
  log_sep
  log "  AI CEREMONY: $name"
  log_sep
  if [[ "$TOOL" == "claude" ]]; then
    claude --dangerously-skip-permissions --print < "$file" 2>&1 | tee -a "$LOG_FILE" || true
  else
    amp --dangerously-allow-all < "$file" 2>&1 | tee -a "$LOG_FILE" || true
  fi
}

# ── Helper: story state queries (bash reads JSON — agent doesn't self-report) ─
stories_total()    { jq '.stories | length' "$SPRINT_FILE" 2>/dev/null || echo "0"; }
stories_passing()  { jq '[.stories[] | select(.passes == true)] | length' "$SPRINT_FILE" 2>/dev/null || echo "0"; }
stories_reviewed() { jq '[.stories[] | select(.reviewed == true)] | length' "$SPRINT_FILE" 2>/dev/null || echo "0"; }
stories_reopened() {
  # A story was re-opened if passes was true before execute but is now false.
  # We detect this by counting stories where passes:false AND attempts > 0
  jq '[.stories[] | select(.passes == false and (.attempts // 0) > 0)] | length' \
    "$SPRINT_FILE" 2>/dev/null || echo "0"
}

# ═══════════════════════════════════════════════════════════════════════════════
log ""
log "══════════════════════════════════════════════════════════════════"
log "  PHASE $PHASE_NUM SPRINT CEREMONIES  —  $(date)"
log "  Sprint : $ACTIVE_SPRINT"
log "  Log    : $LOG_FILE"
log "══════════════════════════════════════════════════════════════════"

# ── STEP 0: PLAN ─────────────────────────────────────────────────────────────
# Run sprint planning if: no sprint file yet, or active phase is still "pending"
PHASE_STATUS=$(jq -r ".phases[] | select(.file == \"$ACTIVE_SPRINT\") | .status" \
  "$MANIFEST" 2>/dev/null || echo "unknown")

if [[ "$SKIP_PLAN" == false ]] && { [[ ! -f "$SPRINT_FILE" ]] || [[ "$PHASE_STATUS" == "pending" ]]; }; then
  log ""
  log "STEP 0/8 — SPRINT PLANNING"
  log "Sprint file not found or phase is 'pending'. Running plan ceremony..."
  log "(The agent will read backlog.json, score stories, and write the sprint file.)"
  log ""
  run_ceremony "Sprint Planning" "$SCRIPT_DIR/ceremonies/plan.md"

  # Hard check: sprint file must now exist
  resolve_sprint  # re-read manifest in case activeSprint changed
  [[ -f "$SPRINT_FILE" ]] || die "Plan ceremony ran but sprint file still missing: $SPRINT_FILE"
  log ""
  log "✓ Sprint file created: $SPRINT_FILE ($(stories_total) stories)"
else
  log ""
  log "STEP 0/8 — SPRINT PLANNING: skipped (sprint file exists, phase=$PHASE_STATUS)"
fi

# ── STEP 1: PRE-FLIGHT (BASH enforced — no AI involved) ───────────────────────
log ""
log "STEP 1/8 — PRE-FLIGHT (bash-enforced)"
log_sep
PREFLIGHT_FAIL=0

check_tool() {
  local tool="$1" required="${2:-true}"
  if command -v "$tool" &>/dev/null; then
    log "  ✓ $tool"
  elif [[ "$required" == "true" ]]; then
    log "  ✗ MISSING (required): $tool"
    PREFLIGHT_FAIL=1
  else
    log "  ~ MISSING (optional): $tool"
  fi
}

log "  Core tools:"
check_tool jq
check_tool git
check_tool helm
check_tool kubectl
check_tool gh

log "  Code quality tools:"
check_tool shellcheck

log "  Kind/Docker (required if sprint has kind-integration stories):"
NEEDS_KIND=$(jq -e '[.stories[].requiredCapabilities[]? | select(. == "kind")] | length > 0' \
  "$SPRINT_FILE" 2>/dev/null && echo "true" || echo "false")

if [[ "$NEEDS_KIND" == "true" ]]; then
  check_tool kind
  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      log "  ✓ Docker daemon running"
    else
      log "  ✗ Docker daemon NOT running — required for kind stories"
      PREFLIGHT_FAIL=1
    fi
  else
    log "  ✗ MISSING (required for kind stories): docker"
    PREFLIGHT_FAIL=1
  fi

  log "  Checking for active kind cluster..."
  if command -v kind &>/dev/null && kind get clusters 2>/dev/null | grep -q "sovereign"; then
    log "  ✓ kind cluster 'sovereign-*' exists"
  else
    log "  ✗ No kind cluster found matching 'sovereign-*'"
    log "    Run: ./kind/setup.sh"
    log "    Stories requiring 'kind' capability cannot proceed without it."
    PREFLIGHT_FAIL=1
  fi
else
  log "  ~ kind/Docker: not required by any story in this sprint"
fi

log "  git remote connectivity:"
if git ls-remote origin HEAD &>/dev/null 2>&1; then
  log "  ✓ git remote 'origin' reachable"
else
  log "  ✗ git remote 'origin' not reachable — proof-of-work check will fail"
  PREFLIGHT_FAIL=1
fi

if [[ $PREFLIGHT_FAIL -ne 0 ]]; then
  die "Pre-flight failed. Fix the issues above and re-run ceremonies.sh."
fi
log ""
log "✓ Pre-flight passed — all required capabilities present."

# ── STEP 2: SMART CHECK ───────────────────────────────────────────────────────
log ""
log "STEP 2/8 — SMART CHECK"
log "  (AI scores stories; bash reads the JSON and hard-exits if any score < 3)"
log ""

run_ceremony "SMART Check" "$SCRIPT_DIR/ceremonies/smart-check.md"

# Bash reads the result — not a signal file, not prose
NOT_SMART=$(jq '[.stories[] | select(
  (.smart.specific   // 0) < 3 or
  (.smart.measurable // 0) < 3 or
  (.smart.achievable // 0) < 3 or
  (.smart.relevant   // 0) < 3 or
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

# ── STEP 3+4+5: EXECUTE → SMOKE TEST → PROOF CHECK → REVIEW loop ─────────────
RETRY=0
while [[ $RETRY -le $MAX_RETRIES ]]; do
  [[ $RETRY -gt 0 ]] && log "" && log "─── RETRY $RETRY of $MAX_RETRIES ───────────────────────────────────────────"

  # ── 3: EXECUTE ──────────────────────────────────────────────────────────────
  log ""
  log "STEP 3/8 — EXECUTE"
  log "  Running ralph.sh --prd $ACTIVE_SPRINT --tool $TOOL $RALPH_MAX_ITER"
  log ""
  RALPH_EXIT=0
  "$SCRIPT_DIR/ralph.sh" --prd "$ACTIVE_SPRINT" --tool "$TOOL" "$RALPH_MAX_ITER" \
    2>&1 | tee -a "$LOG_FILE" || RALPH_EXIT=$?
  [[ $RALPH_EXIT -ne 0 ]] && log "  WARNING: ralph.sh exited $RALPH_EXIT (may have hit max iterations)"
  log ""
  log "  Stories passing after execute: $(stories_passing) / $(stories_total)"

  # ── 4: SMOKE TEST (bash — no AI) ────────────────────────────────────────────
  log ""
  log "STEP 4/8 — SMOKE TEST (bash-enforced)"
  log_sep
  SMOKE_FAIL=0

  # helm lint all implemented charts
  log "  helm lint:"
  CHART_FAIL=0
  for chart_yaml in "$REPO_ROOT"/charts/*/Chart.yaml; do
    chart_dir=$(dirname "$chart_yaml")
    chart_name=$(basename "$chart_dir")
    if helm lint "$chart_dir" --quiet 2>&1 | tee -a "$LOG_FILE"; then
      log "    ✓ $chart_name"
    else
      log "    ✗ FAIL: $chart_name"
      CHART_FAIL=1
      SMOKE_FAIL=1
    fi
  done
  [[ $CHART_FAIL -eq 0 ]] && log "    all charts passed"

  # bash -n syntax check + shellcheck lint on all bootstrap/scripts .sh files
  log "  shellcheck + bash syntax:"
  SHELL_FAIL=0
  while IFS= read -r -d '' script; do
    rel="${script#"$REPO_ROOT/"}"
    if bash -n "$script" 2>&1 | tee -a "$LOG_FILE" && \
       shellcheck "$script" 2>&1 | tee -a "$LOG_FILE"; then
      log "    ✓ $rel"
    else
      log "    ✗ FAIL: $rel"
      SHELL_FAIL=1
      SMOKE_FAIL=1
    fi
  done < <(find "$REPO_ROOT/bootstrap" "$REPO_ROOT/scripts" \
    -name "*.sh" -not -path "*/.git/*" -print0 2>/dev/null)
  [[ $SHELL_FAIL -eq 0 ]] && log "    all scripts passed"

  # JSON validation for all prd files
  log "  JSON validation (prd/):"
  JSON_FAIL=0
  while IFS= read -r -d '' json_file; do
    rel="${json_file#"$REPO_ROOT/"}"
    if jq empty "$json_file" 2>&1 | tee -a "$LOG_FILE"; then
      log "    ✓ $rel"
    else
      log "    ✗ FAIL: invalid JSON: $rel"
      JSON_FAIL=1
      SMOKE_FAIL=1
    fi
  done < <(find "$REPO_ROOT/prd" -name "*.json" -not -path "*/.git/*" -print0 2>/dev/null)
  [[ $JSON_FAIL -eq 0 ]] && log "    all JSON files valid"

  # ArgoCD app YAML validation (kubectl dry-run)
  if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null 2>&1; then
    log "  kubectl apply --dry-run (argocd-apps/):"
    YAML_FAIL=0
    while IFS= read -r -d '' yaml_file; do
      rel="${yaml_file#"$REPO_ROOT/"}"
      if kubectl apply --dry-run=client -f "$yaml_file" 2>&1 | tee -a "$LOG_FILE"; then
        log "    ✓ $rel"
      else
        log "    ✗ FAIL: $rel"
        YAML_FAIL=1
        SMOKE_FAIL=1
      fi
    done < <(find "$REPO_ROOT/argocd-apps" -name "*.yaml" -print0 2>/dev/null)
    [[ $YAML_FAIL -eq 0 ]] && log "    all ArgoCD manifests valid"
  else
    log "  ~ kubectl dry-run skipped (no cluster reachable)"
  fi

  if [[ $SMOKE_FAIL -ne 0 ]]; then
    log ""
    log "SMOKE TEST FAILED — marking all passes:true stories back to false"
    # Reset passes:true stories to passes:false so execute must re-attempt them
    python3 - "$SPRINT_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    sprint = json.load(f)
changed = 0
for story in sprint['stories']:
    if story.get('passes') is True:
        story['passes'] = False
        story['reviewNotes'] = story.get('reviewNotes', [])
        story['reviewNotes'].append('[SMOKE-TEST-FAIL] Artifacts failed smoke test — reset for re-execution.')
        changed += 1
with open(sys.argv[1], 'w') as f:
    json.dump(sprint, f, indent=2)
print(f'Reset {changed} stories to passes:false.')
PYEOF
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
  log "STEP 5/8 — PROOF OF WORK CHECK (bash-enforced)"
  log_sep
  PROOF_FAIL=0

  SPRINT_BRANCH=$(jq -r '.branchName // empty' "$SPRINT_FILE" 2>/dev/null || echo "")

  if [[ -z "$SPRINT_BRANCH" ]]; then
    log "  WARN: No branchName in sprint file. Checking per-story branches..."
    # Check each story's branchName if set
    while IFS= read -r story_branch; do
      [[ -z "$story_branch" || "$story_branch" == "null" ]] && continue
      if git ls-remote --heads origin "$story_branch" 2>/dev/null | grep -q .; then
        log "  ✓ pushed: $story_branch"
      else
        log "  ✗ NOT pushed: $story_branch"
        PROOF_FAIL=1
      fi
    done < <(jq -r '.stories[].branchName // empty' "$SPRINT_FILE" 2>/dev/null)
  else
    log "  Checking branch '$SPRINT_BRANCH' is pushed to origin..."
    if git ls-remote --heads origin "$SPRINT_BRANCH" 2>/dev/null | grep -q .; then
      log "  ✓ Branch '$SPRINT_BRANCH' exists on origin"
    else
      log "  ✗ Branch '$SPRINT_BRANCH' NOT found on origin"
      log "    The agent must 'git push' before marking stories passes:true."
      PROOF_FAIL=1
    fi

    if command -v gh &>/dev/null; then
      log "  Checking for PR on branch '$SPRINT_BRANCH'..."
      PR_NUM=$(gh pr list --head "$SPRINT_BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
      if [[ -n "$PR_NUM" && "$PR_NUM" != "null" ]]; then
        log "  ✓ PR #$PR_NUM exists for '$SPRINT_BRANCH'"
      else
        log "  ✗ No PR found for branch '$SPRINT_BRANCH'"
        log "    The agent must 'gh pr create' before marking stories passes:true."
        PROOF_FAIL=1
      fi
    fi
  fi

  if [[ $PROOF_FAIL -ne 0 ]]; then
    log ""
    log "PROOF OF WORK FAILED — resetting all passes:true stories"
    python3 - "$SPRINT_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    sprint = json.load(f)
changed = 0
for story in sprint['stories']:
    if story.get('passes') is True:
        story['passes'] = False
        story['reviewNotes'] = story.get('reviewNotes', [])
        story['reviewNotes'].append('[PROOF-FAIL] Branch not pushed or no PR — reset for re-execution.')
        changed += 1
with open(sys.argv[1], 'w') as f:
    json.dump(sprint, f, indent=2)
print(f'Reset {changed} stories to passes:false.')
PYEOF
    RETRY=$((RETRY + 1))
    if [[ $RETRY -le $MAX_RETRIES ]]; then
      log "  Retrying execute (attempt $RETRY of $MAX_RETRIES)..."
      continue
    else
      die "Proof-of-work check failed after $MAX_RETRIES retries. Agent must push + create PR."
    fi
  fi
  log ""
  log "✓ Proof of work verified — branch pushed and PR exists."

  # ── 6: REVIEW ───────────────────────────────────────────────────────────────
  log ""
  log "STEP 6/8 — REVIEW"
  log "  (AI checks ACs adversarially; bash reads story JSON to detect re-opened stories)"
  log ""

  PASSING_BEFORE_REVIEW=$(stories_passing)
  run_ceremony "Review" "$SCRIPT_DIR/ceremonies/review.md"

  # Bash reads story JSON directly — no signal file, no grep on prose
  PASSING_AFTER_REVIEW=$(stories_passing)
  REOPENED=$(stories_reopened)

  log ""
  log "  Passing before review : $PASSING_BEFORE_REVIEW"
  log "  Passing after review  : $PASSING_AFTER_REVIEW"
  log "  Re-opened by review   : $REOPENED"

  if [[ "$REOPENED" -gt 0 ]] || [[ "$PASSING_AFTER_REVIEW" -lt "$PASSING_BEFORE_REVIEW" ]]; then
    RETRY=$((RETRY + 1))
    if [[ $RETRY -gt $MAX_RETRIES ]]; then
      log ""
      log "Max retries ($MAX_RETRIES) exceeded with $REOPENED stories still failing review."
      python3 - "$SPRINT_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    sprint = json.load(f)
for story in sprint['stories']:
    if not story.get('reviewed') and not story.get('passes'):
        story['reviewNotes'] = story.get('reviewNotes', [])
        story['reviewNotes'].append(
            f"[BLOCKED] Max retries exceeded after {story.get('attempts', 0)} attempt(s). "
            "Manual intervention required.")
with open(sys.argv[1], 'w') as f:
    json.dump(sprint, f, indent=2)
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

NOT_ACCEPTED=$(jq '[.stories[] | select(.reviewed != true)] | length' "$SPRINT_FILE" 2>/dev/null || echo "99")
if [[ "$NOT_ACCEPTED" -gt 0 ]]; then
  log ""
  log "WARNING: $NOT_ACCEPTED stories not yet accepted (reviewed:true)."
  log "  Re-run ceremonies.sh --skip-plan to retry without re-planning."
  log ""
  log "Sprint ceremonies complete (with $NOT_ACCEPTED unaccepted stories)."
  log "Log: $LOG_FILE"
  exit 1
fi

ADVANCE_SCRIPT="$REPO_ROOT/prd/advance.sh"
if [[ -x "$ADVANCE_SCRIPT" ]]; then
  log "All stories accepted. Running prd/advance.sh..."
  "$ADVANCE_SCRIPT" 2>&1 | tee -a "$LOG_FILE"
else
  log "  ~ prd/advance.sh not found or not executable — skipping phase advancement."
  log "    Manually update $MANIFEST to advance to the next phase."
fi

log ""
log "══════════════════════════════════════════════════════════════════"
log "  SPRINT COMPLETE — Phase $PHASE_NUM accepted ✓"
log "  $(stories_total) stories delivered."
log "  Log: $LOG_FILE"
log "══════════════════════════════════════════════════════════════════"
