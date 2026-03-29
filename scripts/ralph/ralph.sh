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
  if [[ -n "$ACTIVE" && "$ACTIVE" != "null" ]]; then
    PRD_FILE="$REPO_ROOT/$ACTIVE"
  else
    echo "Error: no activeSprint in $MANIFEST — run ceremonies.sh to plan a sprint first" >&2; exit 1
  fi
else
  echo "Error: $MANIFEST not found — run ceremonies.sh to initialise the project" >&2; exit 1
fi

echo "PRD file: $PRD_FILE"
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
    echo "   Archived to: $ARCHIVE_FOLDER"
  fi
fi

if [[ -f "$PRD_FILE" ]]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  [[ -n "$CURRENT_BRANCH" ]] && echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
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
  if [[ $total -eq 0 ]]; then return 0; fi

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
# ── Rate limit handler ────────────────────────────────────────────────────────
# Detects "You've hit your limit · resets Xam (Timezone)" in output.
# Sleeps until that time + 5min buffer. Returns 1 if limited, 0 if not.
# Callers should retry their claude/amp call after this returns 1.
handle_rate_limit() {
  local output="$1"
  echo "$output" | grep -q "You've hit your limit" || return 0

  echo ""
  echo "⏸  Rate limit reached."

  # Parse reset time via Python (handles all am/pm + timezone math)
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
    print(3600)  # fallback: 1 hour
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

target = now.replace(hour=hour, minute=5, second=0, microsecond=0)  # +5min buffer
if target <= now:
    target += timedelta(days=1)

print(int((target - now).total_seconds()))
PYEOF
  )
  rm -f "$out_tmp"

  # Validate — fall back to 1 hour if parse failed
  if [[ -z "$sleep_secs" ]] || ! [[ "$sleep_secs" =~ ^[0-9]+$ ]] || [[ "$sleep_secs" -le 0 ]]; then
    echo "   Could not parse reset time. Sleeping 1 hour."
    sleep_secs=3600
  fi

  # Show the wall-clock resume time in America/Detroit so you know when to come back
  local resume_time
  resume_time=$(python3 -c "
from datetime import datetime, timedelta
try:
    from zoneinfo import ZoneInfo
    tz = ZoneInfo('America/Detroit')
except Exception:
    from datetime import timezone, timedelta as td
    tz = timezone(td(hours=-5))
t = datetime.now(tz) + timedelta(seconds=${sleep_secs})
print(t.strftime('%I:%M %p %Z  (%a %b %-d)'))
" 2>/dev/null || echo "unknown")

  local h=$(( sleep_secs / 3600 ))
  local m=$(( (sleep_secs % 3600) / 60 ))
  echo "   ┌─────────────────────────────────────────────┐"
  echo "   │  Resume at: $resume_time"
  echo "   │  Waiting ${h}h ${m}m — 3-min increments (laptop-sleep safe)"
  echo "   └─────────────────────────────────────────────┘"
  echo ""

  local deadline=$(( $(date +%s) + sleep_secs ))
  while true; do
    local now remaining rh rm
    now=$(date +%s)
    [[ $now -ge $deadline ]] && break
    remaining=$(( deadline - now ))
    rh=$(( remaining / 3600 ))
    rm=$(( (remaining % 3600) / 60 ))
    printf "   ⏳ %dh %02dm remaining …\r" "$rh" "$rm"
    sleep 180
  done

  echo ""
  echo "▶  Resuming after rate limit reset."
  return 1  # signal: was rate limited — caller should retry
}

echo "Starting Ralph — tool: $TOOL — max iterations: $MAX_ITERATIONS"

# Pre-flight: check if there is actually anything to implement.
# If all stories already have passes:true, there is no work for the agent.
# Signal COMPLETE immediately so ceremonies.sh can move to smoke test.
if command -v jq &>/dev/null && [[ -f "$PRD_FILE" ]]; then
  STORIES_NEEDING_WORK=$(jq '[.stories[] | select(.passes == false)] | length' \
    "$PRD_FILE" 2>/dev/null || echo "1")
  if [[ "$STORIES_NEEDING_WORK" -eq 0 ]]; then
    echo ""
    echo "All stories already passing — no implementation work needed."
    echo "<promise>COMPLETE</promise>"
    exit 0
  fi
  echo "  Stories needing work: $STORIES_NEEDING_WORK"
fi

# ── Ensure story branch exists and is up-to-date with main ────────────────────
# Stories specify a branchName. If that branch already exists (from a previous
# sprint), it may be stale. Always merge latest main into it so the agent
# never works on an outdated codebase.
if command -v jq &>/dev/null && [[ -f "$PRD_FILE" ]]; then
  # Use the first non-passing story's branch, or fall back to sprint-level branchName
  STORY_BRANCH=$(jq -r '
    (.stories[] | select(.passes == false) | .branchName // empty) // .branchName // empty
  ' "$PRD_FILE" 2>/dev/null | head -1)

  if [[ -n "$STORY_BRANCH" ]]; then
    echo "  Branch: $STORY_BRANCH"
    git fetch origin main 2>/dev/null || true

    # Stash any uncommitted changes so checkout doesn't fail
    STASHED=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
      git stash push -m "ralph: auto-stash before branch sync" 2>/dev/null && STASHED=true
    fi

    if git rev-parse --verify "origin/$STORY_BRANCH" &>/dev/null; then
      # Branch exists remotely — check it out and merge main
      git checkout "$STORY_BRANCH" 2>/dev/null || git checkout -b "$STORY_BRANCH" "origin/$STORY_BRANCH"
      git merge origin/main --no-edit -m "sync: merge main into $STORY_BRANCH" || {
        echo "  ERROR: merge conflict syncing main into $STORY_BRANCH — needs manual resolution" >&2
        exit 1
      }
      echo "  ✓ Merged latest main into $STORY_BRANCH"
    elif git rev-parse --verify "$STORY_BRANCH" &>/dev/null; then
      # Branch exists locally only — check it out and merge main
      git checkout "$STORY_BRANCH"
      git merge origin/main --no-edit -m "sync: merge main into $STORY_BRANCH" || {
        echo "  ERROR: merge conflict syncing main into $STORY_BRANCH — needs manual resolution" >&2
        exit 1
      }
      echo "  ✓ Merged latest main into $STORY_BRANCH (local)"
    else
      # Branch doesn't exist — create from main
      git checkout -b "$STORY_BRANCH" origin/main
      echo "  ✓ Created $STORY_BRANCH from main"
    fi

    # Restore stashed changes (sprint file updates from ceremonies)
    if [[ "$STASHED" == "true" ]]; then
      git stash pop 2>/dev/null || echo "  WARNING: stash pop failed — may need manual resolution"
    fi
  fi
fi

PROMPT_TMP=$(mktemp /tmp/ralph-prompt-XXXXXX)
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

  # Inner loop: retry this iteration if rate limited (does not consume iteration count)
  while true; do
    OUTPUT=""
    if [[ "$TOOL" == "amp" ]]; then
      OUTPUT=$(amp --dangerously-allow-all < "$PROMPT_TMP" 2>&1 | tee /dev/stderr) || true
    else
      OUTPUT=$(claude --dangerously-skip-permissions --print < "$PROMPT_TMP" 2>&1 | tee /dev/stderr) || true
    fi

    handle_rate_limit "$OUTPUT" && break  # not rate limited — proceed
    # Was rate limited — handle_rate_limit already slept; retry same iteration
  done

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"

    # Clean up: return to main and delete the story branch locally
    if [[ -n "${STORY_BRANCH:-}" ]]; then
      git checkout main 2>/dev/null || true
      git pull origin main 2>/dev/null || true
      git branch -d "$STORY_BRANCH" 2>/dev/null && echo "  ✓ Deleted local branch $STORY_BRANCH" || true
      git remote prune origin 2>/dev/null || true
    fi
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
# Return to main even on max-iterations — don't leave on a stale branch
git checkout main 2>/dev/null || true
exit 1
