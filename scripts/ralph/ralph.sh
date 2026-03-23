#!/usr/bin/env bash
# ralph.sh — AI agent execution loop for the Sovereign Platform
# Usage: ./ralph.sh [--tool amp|claude] [--prd <path>] [--phase <N>] [max_iterations]
#
# PRD resolution order:
#   1. --prd <path>          explicit path to a sprint file
#   2. --phase <N>           resolves phases[N].file from prd/manifest.json
#   3. prd/manifest.json     auto-detect activeSprint if manifest exists
#   4. scripts/ralph/prd.json  legacy fallback
#
# Layer 2 — Failure feedback loop:
#   Before calling the AI each iteration, this script reads the sprint file and
#   builds a FAILURE CONTEXT section from any recorded gate failures
#   (_lastSmokeTestFailures, _lastProofOfWorkFailures, story reviewNotes).
#   This section is prepended to CLAUDE.md so the agent reads WHY the previous
#   attempt was stopped before it touches any files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Argument parsing ──────────────────────────────────────────────────────────
TOOL="amp"
MAX_ITERATIONS=10
PRD_OVERRIDE=""
PHASE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)      TOOL="$2";               shift 2 ;;
    --tool=*)    TOOL="${1#*=}";          shift   ;;
    --prd)       PRD_OVERRIDE="$2";       shift 2 ;;
    --prd=*)     PRD_OVERRIDE="${1#*=}";  shift   ;;
    --phase)     PHASE_OVERRIDE="$2";     shift 2 ;;
    --phase=*)   PHASE_OVERRIDE="${1#*=}"; shift  ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then MAX_ITERATIONS="$1"; fi
      shift ;;
  esac
done

if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'." >&2; exit 1
fi

# ── Resolve PRD file path ─────────────────────────────────────────────────────
MANIFEST="$REPO_ROOT/prd/manifest.json"
if [[ -n "$PRD_OVERRIDE" ]]; then
  [[ "$PRD_OVERRIDE" = /* ]] && PRD_FILE="$PRD_OVERRIDE" || PRD_FILE="$REPO_ROOT/$PRD_OVERRIDE"
elif [[ -n "$PHASE_OVERRIDE" ]] && [[ -f "$MANIFEST" ]] && command -v jq &>/dev/null; then
  PHASE_FILE=$(jq -r ".phases[] | select(.id == $PHASE_OVERRIDE) | .file" "$MANIFEST" 2>/dev/null || echo "")
  if [[ -z "$PHASE_FILE" || "$PHASE_FILE" == "null" ]]; then
    echo "Error: Phase $PHASE_OVERRIDE not found in $MANIFEST" >&2; exit 1
  fi
  PRD_FILE="$REPO_ROOT/$PHASE_FILE"
elif [[ -f "$MANIFEST" ]] && command -v jq &>/dev/null; then
  ACTIVE=$(jq -r '.activeSprint // empty' "$MANIFEST" 2>/dev/null || echo "")
  [[ -n "$ACTIVE" && "$ACTIVE" != "null" ]] && PRD_FILE="$REPO_ROOT/$ACTIVE" || PRD_FILE="$SCRIPT_DIR/prd.json"
else
  PRD_FILE="$SCRIPT_DIR/prd.json"
fi

echo "PRD file: $PRD_FILE"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# ── Archive previous run if branch changed ────────────────────────────────────
if [[ -f "$PRD_FILE" && -f "$LAST_BRANCH_FILE" ]]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  if [[ -n "$CURRENT_BRANCH" && -n "$LAST_BRANCH" && "$CURRENT_BRANCH" != "$LAST_BRANCH" ]]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME="${LAST_BRANCH#ralph/}"
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [[ -f "$PRD_FILE" ]]      && cp "$PRD_FILE"      "$ARCHIVE_FOLDER/"
    [[ -f "$PROGRESS_FILE" ]] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)"   >> "$PROGRESS_FILE"
    echo "---"                >> "$PROGRESS_FILE"
  fi
fi

if [[ -f "$PRD_FILE" ]]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  [[ -n "$CURRENT_BRANCH" ]] && echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
fi

if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)"   >> "$PROGRESS_FILE"
  echo "---"                >> "$PROGRESS_FILE"
fi

# ── Layer 2: Build failure context from sprint file ───────────────────────────
# Reads _lastSmokeTestFailures, _lastProofOfWorkFailures, and story reviewNotes
# from the sprint JSON. Outputs markdown to a temp file (empty if no failures).
build_failure_context() {
  local sprint_file="$1"
  local out_file="$2"

  # Start empty — we only write if there are real failures
  true > "$out_file"

  [[ ! -f "$sprint_file" ]] && return 0
  ! command -v jq &>/dev/null && return 0

  local smoke_count proof_count review_count
  smoke_count=$(jq '._lastSmokeTestFailures // [] | length' "$sprint_file" 2>/dev/null || echo 0)
  proof_count=$(jq '._lastProofOfWorkFailures // [] | length' "$sprint_file" 2>/dev/null || echo 0)

  # Stories re-opened by review: passes:false AND have a gate-stamped reviewNote
  review_count=$(jq '[
    .stories[] |
    select(
      .passes == false and
      ((.reviewNotes // []) | map(
        select(
          startswith("[REVIEW") or startswith("[SMOKE") or
          startswith("[PROOF")  or startswith("[BLOCKED]")
        )
      ) | length > 0)
    )
  ] | length' "$sprint_file" 2>/dev/null || echo 0)

  local total=$(( smoke_count + proof_count + review_count ))
  [[ $total -eq 0 ]] && return 0

  cat >> "$out_file" <<'HEADER'

---
## ⚠ FAILURE CONTEXT — READ THIS BEFORE TOUCHING ANY FILES

The previous execution attempt was halted by a gate check in ceremonies.sh.
The specific failures are listed below. The same shell commands will re-run
after your changes — claiming something is fixed without fixing it will trigger
another reset and waste an iteration.

Fix every issue listed. Do not re-do work that is already passing.

HEADER

  if [[ $smoke_count -gt 0 ]]; then
    echo "### Smoke Test Failures (${smoke_count} failing checks)" >> "$out_file"
    echo "" >> "$out_file"
    jq -r '._lastSmokeTestFailures[] |
      "**\(.type)** on `\(.target)`",
      "```",
      (.output // "(no output captured)"),
      "```",
      ""' "$sprint_file" 2>/dev/null >> "$out_file" || true
  fi

  if [[ $proof_count -gt 0 ]]; then
    echo "### Proof-of-Work Failures (${proof_count} checks)" >> "$out_file"
    echo "" >> "$out_file"
    jq -r '._lastProofOfWorkFailures[] |
      "- **\(.type)**: \(.detail)"' "$sprint_file" 2>/dev/null >> "$out_file" || true
    echo "" >> "$out_file"
  fi

  if [[ $review_count -gt 0 ]]; then
    echo "### Stories Re-opened by Review" >> "$out_file"
    echo "" >> "$out_file"
    jq -r '.stories[] |
      select(
        .passes == false and
        ((.reviewNotes // []) | map(
          select(
            startswith("[REVIEW") or startswith("[SMOKE") or
            startswith("[PROOF")  or startswith("[BLOCKED]")
          )
        ) | length > 0)
      ) |
      "**\(.id): \(.title)**",
      (
        .reviewNotes[] |
        select(
          startswith("[REVIEW") or startswith("[SMOKE") or
          startswith("[PROOF")  or startswith("[BLOCKED]")
        ) |
        "  - \(.)"
      ),
      ""' "$sprint_file" 2>/dev/null >> "$out_file" || true
  fi

  echo "---" >> "$out_file"
  echo "" >> "$out_file"
}

# ── Execution loop ────────────────────────────────────────────────────────────
echo "Starting Ralph — tool: $TOOL — max iterations: $MAX_ITERATIONS"

PROMPT_TMP=$(mktemp /tmp/ralph-prompt-XXXXXX.md)
trap 'rm -f "$PROMPT_TMP"' EXIT

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  echo "================================================================"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "================================================================"

  # Build prompt = CLAUDE.md + failure context (if any)
  cat "$SCRIPT_DIR/CLAUDE.md" > "$PROMPT_TMP"
  build_failure_context "$PRD_FILE" /tmp/ralph-failure-context-$$.md
  cat /tmp/ralph-failure-context-$$.md >> "$PROMPT_TMP"
  rm -f /tmp/ralph-failure-context-$$.md

  FAILURE_LINES=$(wc -l < "$PROMPT_TMP")
  CLAUDE_LINES=$(wc -l < "$SCRIPT_DIR/CLAUDE.md")
  CONTEXT_LINES=$(( FAILURE_LINES - CLAUDE_LINES ))
  if [[ $CONTEXT_LINES -gt 2 ]]; then
    echo "  ⚠ Failure context injected: ${CONTEXT_LINES} lines of gate failure details"
  fi

  OUTPUT=""
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(amp --dangerously-allow-all < "$PROMPT_TMP" 2>&1 | tee /dev/stderr) || true
  else
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$PROMPT_TMP" 2>&1 | tee /dev/stderr) || true
  fi

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
