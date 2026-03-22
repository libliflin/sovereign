#!/usr/bin/env bash
# prd/advance.sh — Mark active phase complete and activate the next phase
# Usage: ./prd/advance.sh [--dry-run]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/prd/manifest.json"
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required" >&2; exit 1
fi

ACTIVE_SPRINT=$(jq -r '.activeSprint' "$MANIFEST")
CURRENT_PHASE=$(jq -r '.currentPhase' "$MANIFEST")

echo "=== Phase Advancement ==="
echo "Active sprint : $ACTIVE_SPRINT"
echo "Current phase : $CURRENT_PHASE"

# Guard: all stories must be passes:true and reviewed:true
if [[ -f "$REPO_ROOT/$ACTIVE_SPRINT" ]]; then
  NOT_DONE=$(jq '[.stories[] | select(.passes != true or .reviewed != true)] | length' "$REPO_ROOT/$ACTIVE_SPRINT")
  if [[ "$NOT_DONE" -gt 0 ]]; then
    echo ""
    echo "ERROR: Cannot advance — $NOT_DONE stories in the active sprint are not yet accepted." >&2
    echo "Run the review ceremony first: claude < scripts/ralph/ceremonies/review.md" >&2
    jq '.stories[] | select(.passes != true or .reviewed != true) | "  - \(.id): passes=\(.passes) reviewed=\(.reviewed)"' "$REPO_ROOT/$ACTIVE_SPRINT" -r >&2
    exit 1
  fi
fi

# Find next pending phase
NEXT_PHASE=$((CURRENT_PHASE + 1))
NEXT_FILE=$(jq -r ".phases[] | select(.id == $NEXT_PHASE) | .file" "$MANIFEST")

if [[ -z "$NEXT_FILE" || "$NEXT_FILE" == "null" ]]; then
  echo "All phases complete! No next phase found."
  if [[ "$DRY_RUN" == false ]]; then
    jq ".phases[$CURRENT_PHASE].status = \"complete\" |
        .phases[$CURRENT_PHASE].endDate = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" \
      "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
  fi
  exit 0
fi

echo "Next phase    : $NEXT_PHASE → $NEXT_FILE"
echo ""

# Calculate metrics for completed phase
if [[ -f "$REPO_ROOT/$ACTIVE_SPRINT" ]]; then
  TOTAL=$(jq '.stories | length' "$REPO_ROOT/$ACTIVE_SPRINT")
  ACCEPTED=$(jq '[.stories[] | select(.reviewed == true)] | length' "$REPO_ROOT/$ACTIVE_SPRINT")
  POINTS=$(jq '[.stories[] | select(.reviewed == true) | .points] | add // 0' "$REPO_ROOT/$ACTIVE_SPRINT")
  PASS_RATE=$(echo "scale=2; $ACCEPTED / $TOTAL * 100" | bc)
  echo "Sprint metrics: $ACCEPTED/$TOTAL stories accepted, ${POINTS} points, ${PASS_RATE}% first-review pass rate"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "[DRY RUN] Would:"
  echo "  - Set phase $CURRENT_PHASE status → complete"
  echo "  - Set phase $NEXT_PHASE status → active"
  echo "  - Set activeSprint → $NEXT_FILE"
  echo "  - Set currentPhase → $NEXT_PHASE"
  echo "  - Append sprint summary to sprintHistory[]"
  exit 0
fi

END_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Update manifest
jq \
  --arg end "$END_DATE" \
  --argjson phase "$CURRENT_PHASE" \
  --argjson next "$NEXT_PHASE" \
  --arg nextFile "$NEXT_FILE" \
  --argjson points "${POINTS:-0}" \
  --arg passRate "${PASS_RATE:-0}" \
  '
  .phases[$phase].status = "complete" |
  .phases[$phase].endDate = $end |
  .phases[$phase].pointsCompleted = $points |
  .phases[$phase].reviewPassRate = ($passRate | tonumber) |
  .phases[$next].status = "active" |
  .activeSprint = $nextFile |
  .currentPhase = $next |
  .sprintHistory += [{
    "phase": $phase,
    "endDate": $end,
    "pointsCompleted": $points,
    "reviewPassRate": ($passRate | tonumber)
  }]
  ' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

echo ""
echo "✓ Phase $CURRENT_PHASE marked complete"
echo "✓ Phase $NEXT_PHASE is now active"
echo "✓ Active sprint → $NEXT_FILE"
echo ""
echo "Next step: run the planning ceremony to populate $NEXT_FILE"
echo "  claude < scripts/ralph/ceremonies/plan.md"
