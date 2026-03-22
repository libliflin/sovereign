#!/usr/bin/env bash
# ceremonies.sh — Full sprint orchestrator for the Sovereign Platform
# Usage: ./ceremonies.sh [--phase N] [--tool claude|amp] [--max-retries 3] [--dry-run]
#
# Sequence:
#   1. SMART CHECK  — abort if any story scores < 3 on any SMART dimension
#   2. EXECUTE      — run ralph.sh until all stories pass or max-iterations hit
#   3. REVIEW       — verify ACs independently; retry EXECUTE if stories re-opened
#   4. RETRO        — extract learnings, close sprint in manifest
#   5. ADVANCE      — run prd/advance.sh to move to next phase (if all stories accepted)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/prd/manifest.json"

# ── Defaults ────────────────────────────────────────────────────────────────
TOOL="claude"
MAX_RETRIES=3
DRY_RUN=false
PHASE_OVERRIDE=""
RALPH_MAX_ITER=10

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --phase)       PHASE_OVERRIDE="$2"; shift 2 ;;
    --phase=*)     PHASE_OVERRIDE="${1#*=}"; shift ;;
    --tool)        TOOL="$2"; shift 2 ;;
    --tool=*)      TOOL="${1#*=}"; shift ;;
    --max-retries) MAX_RETRIES="$2"; shift 2 ;;
    --max-retries=*) MAX_RETRIES="${1#*=}"; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--phase N] [--tool claude|amp] [--max-retries 3] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

# ── Validate tool ─────────────────────────────────────────────────────────────
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'." >&2
  exit 1
fi

# ── Resolve active sprint ────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required" >&2; exit 1
fi

if [[ -n "$PHASE_OVERRIDE" ]]; then
  ACTIVE_SPRINT=$(jq -r ".phases[] | select(.id == $PHASE_OVERRIDE) | .file" "$MANIFEST" 2>/dev/null || echo "")
  if [[ -z "$ACTIVE_SPRINT" || "$ACTIVE_SPRINT" == "null" ]]; then
    echo "ERROR: Phase $PHASE_OVERRIDE not found in $MANIFEST" >&2; exit 1
  fi
else
  ACTIVE_SPRINT=$(jq -r '.activeSprint' "$MANIFEST")
fi

SPRINT_FILE="$REPO_ROOT/$ACTIVE_SPRINT"
PHASE_NUM=$(jq -r '.currentPhase' "$MANIFEST")
if [[ -n "$PHASE_OVERRIDE" ]]; then
  PHASE_NUM="$PHASE_OVERRIDE"
fi

# ── Set up logging ────────────────────────────────────────────────────────────
LOG_DIR="$REPO_ROOT/prd/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/phase-${PHASE_NUM}-${TIMESTAMP}.log"

log() {
  echo "$*" | tee -a "$LOG_FILE"
}

REVIEW_SIGNAL="/tmp/sovereign-review-signal"

# ── DRY RUN: print plan and exit ──────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  echo "=== ceremonies.sh DRY RUN ==="
  echo ""
  echo "Active sprint : $ACTIVE_SPRINT"
  echo "Sprint file   : $SPRINT_FILE"
  echo "Tool          : $TOOL"
  echo "Max retries   : $MAX_RETRIES"
  echo "Log file      : $LOG_FILE"
  echo ""
  echo "Steps that WOULD execute:"
  echo "  1. SMART CHECK  — run: claude < $SCRIPT_DIR/ceremonies/smart-check.md"
  echo "                    abort if any story scores < 3 on any SMART dimension"
  echo "  2. EXECUTE      — run: $SCRIPT_DIR/ralph.sh --prd $ACTIVE_SPRINT --tool $TOOL $RALPH_MAX_ITER"
  echo "                    until all stories pass or max iterations hit"
  echo "  3. REVIEW       — run: claude < $SCRIPT_DIR/ceremonies/review.md"
  echo "                    retry EXECUTE up to $MAX_RETRIES times if stories re-opened"
  echo "  4. RETRO        — run: claude < $SCRIPT_DIR/ceremonies/retro.md"
  echo "  5. ADVANCE      — run: $REPO_ROOT/prd/advance.sh"
  echo ""
  echo "No files modified (--dry-run)."
  exit 0
fi

# ── Helper: run a claude ceremony ────────────────────────────────────────────
run_ceremony() {
  local name="$1"
  local file="$2"
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "  CEREMONY: $name"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "$TOOL" == "claude" ]]; then
    claude --dangerously-skip-permissions --print < "$file" 2>&1 | tee -a "$LOG_FILE" || true
  else
    amp --dangerously-allow-all < "$file" 2>&1 | tee -a "$LOG_FILE" || true
  fi
}

# ── STEP 1: SMART CHECK ───────────────────────────────────────────────────────
log ""
log "=============================================================="
log "  PHASE $PHASE_NUM SPRINT CEREMONIES  —  $(date)"
log "  Sprint: $ACTIVE_SPRINT"
log "  Log   : $LOG_FILE"
log "=============================================================="

log ""
log "STEP 1/5 — SMART CHECK"

run_ceremony "SMART Check" "$SCRIPT_DIR/ceremonies/smart-check.md"

# Check if any story has a SMART dimension < 3
NOT_SMART=$(jq '[.stories[] | select(
  .smart.specific < 3 or
  .smart.measurable < 3 or
  .smart.achievable < 3 or
  .smart.relevant < 3 or
  .smart.timeBound < 3
)] | length' "$SPRINT_FILE" 2>/dev/null || echo "0")

if [[ "$NOT_SMART" -gt 0 ]]; then
  log ""
  log "ERROR: $NOT_SMART stories have SMART dimensions < 3. Cannot proceed with execution."
  log "Fix the following stories (see smart.notes for details):"
  jq -r '.stories[] | select(
    .smart.specific < 3 or .smart.measurable < 3 or
    .smart.achievable < 3 or .smart.relevant < 3 or .smart.timeBound < 3
  ) | "  - \(.id): \(.title) — \(.smart.notes)"' "$SPRINT_FILE" 2>/dev/null | tee -a "$LOG_FILE" || true
  log ""
  log "Refine those stories and re-run ceremonies.sh."
  exit 1
fi

log "✓ SMART check passed — all stories are sprint-ready."

# ── STEP 2+3: EXECUTE + REVIEW LOOP ─────────────────────────────────────────
RETRY=0
while [[ $RETRY -le $MAX_RETRIES ]]; do
  if [[ $RETRY -gt 0 ]]; then
    log ""
    log "STEP 2/5 — EXECUTE (retry $RETRY of $MAX_RETRIES)"
  else
    log ""
    log "STEP 2/5 — EXECUTE"
  fi

  # Run ralph
  log "Running ralph.sh --prd $ACTIVE_SPRINT --tool $TOOL $RALPH_MAX_ITER ..."
  RALPH_EXIT=0
  "$SCRIPT_DIR/ralph.sh" --prd "$ACTIVE_SPRINT" --tool "$TOOL" "$RALPH_MAX_ITER" \
    2>&1 | tee -a "$LOG_FILE" || RALPH_EXIT=$?

  if [[ $RALPH_EXIT -ne 0 ]]; then
    log "WARNING: ralph.sh exited with code $RALPH_EXIT (may have hit max iterations)"
  fi

  # Run review ceremony
  log ""
  log "STEP 3/5 — REVIEW"
  rm -f "$REVIEW_SIGNAL"

  run_ceremony "Review" "$SCRIPT_DIR/ceremonies/review.md"

  # Check if stories were re-opened
  if [[ -f "$REVIEW_SIGNAL" ]] && grep -q "STORIES_REOPENED=true" "$REVIEW_SIGNAL"; then
    RETRY=$((RETRY + 1))
    if [[ $RETRY -gt $MAX_RETRIES ]]; then
      log ""
      log "ERROR: Max retries ($MAX_RETRIES) exceeded with stories still failing review."
      log "Marking remaining failing stories as blocked..."

      # Mark still-failing stories as blocked
      python3 - "$SPRINT_FILE" <<'PYEOF'
import json, sys

sprint_file = sys.argv[1]
with open(sprint_file) as f:
    sprint = json.load(f)

for story in sprint['stories']:
    if not story.get('reviewed') and not story.get('passes'):
        story['reviewNotes'] = story.get('reviewNotes', [])
        story['reviewNotes'].append(
            f"[BLOCKED] Max retries exceeded after {story.get('attempts', 0)} attempts. "
            "Manual intervention required."
        )

with open(sprint_file, 'w') as f:
    json.dump(sprint, f, indent=2)

print("Blocked stories updated in sprint file.")
PYEOF
      break
    fi

    log ""
    log "Stories were re-opened by review ceremony. Retrying execution ($RETRY of $MAX_RETRIES)..."
  else
    log ""
    log "✓ Review ceremony passed — no stories re-opened."
    break
  fi
done

# ── STEP 4: RETRO ─────────────────────────────────────────────────────────────
log ""
log "STEP 4/5 — RETRO"

run_ceremony "Retrospective" "$SCRIPT_DIR/ceremonies/retro.md"

# ── STEP 5: ADVANCE ───────────────────────────────────────────────────────────
log ""
log "STEP 5/5 — ADVANCE"

# Check if all non-blocked stories are reviewed:true
NOT_ACCEPTED=$(jq '[.stories[] | select(.reviewed != true)] | length' "$SPRINT_FILE" 2>/dev/null || echo "99")

if [[ "$NOT_ACCEPTED" -gt 0 ]]; then
  log ""
  log "WARNING: $NOT_ACCEPTED stories are not yet accepted (reviewed:true)."
  log "Skipping phase advancement. Fix remaining stories and re-run ceremonies.sh."
  log ""
  log "Sprint ceremonies complete (with incomplete stories)."
  log "Log: $LOG_FILE"
  exit 0
fi

log "All stories accepted. Running prd/advance.sh..."
"$REPO_ROOT/prd/advance.sh" 2>&1 | tee -a "$LOG_FILE"

log ""
log "=============================================================="
log "  SPRINT COMPLETE — Phase $PHASE_NUM finished"
log "  Log: $LOG_FILE"
log "=============================================================="
