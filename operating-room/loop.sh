#!/usr/bin/env bash
# operating-room/loop.sh — The programmer loop.
#
# Sequences four agents: operator → counsel → surgeon (every cycle)
# and retro (every 5 cycles). Each agent gets its prompt + relevant
# state files piped to claude.
#
# Usage:
#   ./loop.sh start [--cycles N] [--tool claude|amp]
#   ./loop.sh stop
#   ./loop.sh status
#   ./loop.sh logs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$SCRIPT_DIR/state"
AGENTS_DIR="$SCRIPT_DIR/agents"
HISTORY_DIR="$STATE_DIR/history"
PID_FILE="$REPO_ROOT/.operating-room.pid"
RETRO_INTERVAL=5

log() { echo "  [loop] $*"; }

# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

get_cycle() {
    if [[ -f "$STATE_DIR/cycle.json" ]]; then
        python3 -c "import json; print(json.load(open('$STATE_DIR/cycle.json')).get('cycle', 1))"
    else
        echo 1
    fi
}

set_cycle() {
    local cycle="$1"
    local status="${2:-running}"
    python3 -c "
import json
from datetime import datetime, timezone
data = {'cycle': $cycle, 'status': '$status', 'updatedAt': datetime.now(timezone.utc).isoformat()}
if __import__('os').path.exists('$STATE_DIR/cycle.json'):
    old = json.load(open('$STATE_DIR/cycle.json'))
    data['agents'] = old.get('agents', {})
else:
    data['agents'] = {}
json.dump(data, open('$STATE_DIR/cycle.json', 'w'), indent=2)
"
}

record_agent() {
    local agent="$1"
    local exit_code="$2"
    python3 -c "
import json
from datetime import datetime, timezone
data = json.load(open('$STATE_DIR/cycle.json'))
data.setdefault('agents', {})['$agent'] = {
    'lastRun': datetime.now(timezone.utc).isoformat(),
    'exitCode': $exit_code
}
json.dump(data, open('$STATE_DIR/cycle.json', 'w'), indent=2)
"
}

archive_cycle() {
    local cycle="$1"
    local cycle_dir
    cycle_dir=$(printf "$HISTORY_DIR/cycle-%03d" "$cycle")
    mkdir -p "$cycle_dir"
    for f in report.md directive.md changelog.md; do
        [[ -f "$STATE_DIR/$f" ]] && cp "$STATE_DIR/$f" "$cycle_dir/"
    done
}

# ---------------------------------------------------------------------------
# Agent invocation
# ---------------------------------------------------------------------------

run_agent() {
    local agent_name="$1"
    local cycle="$2"
    local tool="${3:-claude}"

    log "Running $agent_name (cycle $cycle) ..."

    # Assemble prompt: base prompt + injected state
    local prompt=""
    prompt+="$(cat "$AGENTS_DIR/${agent_name}.md")"
    prompt+=$'\n\n'

    # Inject relevant state files based on agent
    case "$agent_name" in
        operator)
            if [[ -f "$STATE_DIR/changelog.md" ]]; then
                prompt+="---"$'\n'
                prompt+="## Previous Cycle Changelog"$'\n\n'
                prompt+="$(cat "$STATE_DIR/changelog.md")"
                prompt+=$'\n\n'
            fi
            ;;
        counsel)
            if [[ -f "$STATE_DIR/report.md" ]]; then
                prompt+="---"$'\n'
                prompt+="## Operator Report"$'\n\n'
                prompt+="$(cat "$STATE_DIR/report.md")"
                prompt+=$'\n\n'
            fi
            if [[ -f "$STATE_DIR/directive.md" ]]; then
                prompt+="---"$'\n'
                prompt+="## Previous Directive"$'\n\n'
                prompt+="$(cat "$STATE_DIR/directive.md")"
                prompt+=$'\n\n'
            fi
            ;;
        surgeon)
            if [[ -f "$STATE_DIR/directive.md" ]]; then
                prompt+="---"$'\n'
                prompt+="## Counsel Directive"$'\n\n'
                prompt+="$(cat "$STATE_DIR/directive.md")"
                prompt+=$'\n\n'
            fi
            if [[ -f "$STATE_DIR/report.md" ]]; then
                prompt+="---"$'\n'
                prompt+="## Operator Report"$'\n\n'
                prompt+="$(cat "$STATE_DIR/report.md")"
                prompt+=$'\n\n'
            fi
            ;;
        retro)
            # Inject last RETRO_INTERVAL cycles from history
            local start_cycle=$((cycle - RETRO_INTERVAL))
            (( start_cycle < 1 )) && start_cycle=1
            for (( c=start_cycle; c<cycle; c++ )); do
                local cdir
                cdir=$(printf "$HISTORY_DIR/cycle-%03d" "$c")
                if [[ -d "$cdir" ]]; then
                    prompt+="---"$'\n'
                    prompt+="## Cycle $c"$'\n\n'
                    for f in report.md directive.md changelog.md; do
                        if [[ -f "$cdir/$f" ]]; then
                            prompt+="### $f"$'\n'
                            prompt+='```'$'\n'
                            prompt+="$(cat "$cdir/$f")"
                            prompt+=$'\n''```'$'\n\n'
                        fi
                    done
                fi
            done
            # Inject current agent prompts so retro can review/modify them
            for agent_file in operator.md counsel.md surgeon.md; do
                prompt+="---"$'\n'
                prompt+="## Current $agent_file"$'\n'
                prompt+='```'$'\n'
                prompt+="$(cat "$AGENTS_DIR/$agent_file")"
                prompt+=$'\n''```'$'\n\n'
            done
            ;;
    esac

    # Invoke claude
    local output
    local exit_code=0

    if [[ "$tool" == "claude" ]]; then
        output=$(echo "$prompt" | claude --dangerously-skip-permissions --print 2>&1) || exit_code=$?
    else
        output=$(echo "$prompt" | amp --dangerously-allow-all 2>&1) || exit_code=$?
    fi

    # Stream to terminal
    echo "$output"

    # Rate limit detection
    if echo "$output" | grep -q "You've hit your limit"; then
        log "Rate limited. Sleeping 1 hour ..."
        sleep 3600
        run_agent "$agent_name" "$cycle" "$tool"
        return
    fi

    record_agent "$agent_name" "$exit_code"
    log "$agent_name complete (exit $exit_code)."
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

is_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

cmd_start() {
    local max_cycles=0  # 0 = unlimited
    local tool="claude"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cycles) max_cycles="$2"; shift 2 ;;
            --tool)   tool="$2"; shift 2 ;;
            *)        echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    if is_running; then
        echo "Already running (PID $(cat "$PID_FILE")). Use 'stop' first."
        exit 1
    fi

    mkdir -p "$STATE_DIR" "$HISTORY_DIR"

    echo ""
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║  OPERATING ROOM — starting programmer loop   ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo ""

    (
        trap 'exit 0' SIGTERM

        # Ensure cluster is up
        log "Ensuring cluster ..."
        "$SCRIPT_DIR/cluster.sh" start

        local cycle
        cycle=$(get_cycle)
        local cycles_run=0

        while true; do
            echo ""
            echo "═══════════════════════════════════════════════"
            echo "  CYCLE $cycle"
            echo "═══════════════════════════════════════════════"
            echo ""

            set_cycle "$cycle" "running"

            # Retro every N cycles (but not on cycle 1)
            if (( cycle > 1 )) && (( cycle % RETRO_INTERVAL == 0 )); then
                run_agent "retro" "$cycle" "$tool"

                # Check for escalation
                if [[ -f "$STATE_DIR/retro.md" ]] \
                    && grep -q "HUMAN_REVIEW_NEEDED" "$STATE_DIR/retro.md"; then
                    log "ESCALATION: retro flagged HUMAN_REVIEW_NEEDED. Pausing."
                    set_cycle "$cycle" "escalated"
                    exit 1
                fi
            fi

            # The core loop: operator → counsel → surgeon
            run_agent "operator" "$cycle" "$tool"
            run_agent "counsel" "$cycle" "$tool"
            run_agent "surgeon" "$cycle" "$tool"

            # Archive this cycle
            archive_cycle "$cycle"

            set_cycle "$cycle" "complete"
            cycle=$((cycle + 1))
            set_cycle "$cycle" "pending"
            cycles_run=$((cycles_run + 1))

            # Check cycle limit
            if (( max_cycles > 0 )) && (( cycles_run >= max_cycles )); then
                log "Completed $cycles_run cycles. Stopping."
                exit 0
            fi

            # Brief pause between cycles (backgrounded for clean SIGTERM)
            sleep 5 &
            wait $! || exit 0
        done
    ) &

    echo $! > "$PID_FILE"
    echo "  Started (PID $!). Tool: $tool"
    echo ""
    echo "  Watch:  $0 status"
    echo "  Stop:   $0 stop"
}

cmd_stop() {
    if ! is_running; then
        echo "Not running."
        [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
        return 0
    fi
    local pid
    pid=$(cat "$PID_FILE")

    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true

    local _
    for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done

    if kill -0 "$pid" 2>/dev/null; then
        pkill -9 -P "$pid" 2>/dev/null || true
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    echo "Stopped (PID $pid)."
}

cmd_status() {
    echo "=== Operating Room ==="
    if is_running; then
        echo "  Running — PID $(cat "$PID_FILE")"
    else
        echo "  Stopped"
    fi

    echo ""
    echo "=== Cycle ==="
    if [[ -f "$STATE_DIR/cycle.json" ]]; then
        python3 -c "
import json
c = json.load(open('$STATE_DIR/cycle.json'))
print(f\"  Cycle: {c.get('cycle', '?')}  Status: {c.get('status', '?')}\")
for name, info in c.get('agents', {}).items():
    print(f\"  {name:10s} last run: {info.get('lastRun', '?')[:19]}  exit: {info.get('exitCode', '?')}\")
"
    else
        echo "  No cycles run yet."
    fi

    echo ""
    echo "=== Cluster ==="
    "$SCRIPT_DIR/cluster.sh" status 2>/dev/null || echo "  (cluster.sh not available)"

    echo ""
    echo "=== Last Report Summary ==="
    if [[ -f "$STATE_DIR/report.md" ]]; then
        grep -A5 "^## Summary" "$STATE_DIR/report.md" 2>/dev/null \
            | head -10 | sed 's/^/  /'
    else
        echo "  No report yet."
    fi
}

cmd_logs() {
    if [[ -f "$STATE_DIR/report.md" ]]; then
        echo "=== Latest Operator Report ==="
        cat "$STATE_DIR/report.md"
    fi
    echo ""
    if [[ -f "$STATE_DIR/directive.md" ]]; then
        echo "=== Latest Counsel Directive ==="
        cat "$STATE_DIR/directive.md"
    fi
    echo ""
    if [[ -f "$STATE_DIR/changelog.md" ]]; then
        echo "=== Latest Surgeon Changelog ==="
        cat "$STATE_DIR/changelog.md"
    fi
}

# ---------------------------------------------------------------------------
case "${1:-help}" in
    start)  shift; cmd_start "$@" ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    logs)   cmd_logs ;;
    *)
        echo "Usage: $0 start [--cycles N] [--tool claude|amp] | stop | status | logs"
        exit 1
        ;;
esac
