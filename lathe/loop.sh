#!/usr/bin/env bash
# lathe/loop.sh — One tool, continuous shaping.
#
# Each cycle: snapshot cluster state (bash) → one agent call (claude) → commit → repeat.
# Target: <5 minutes per cycle.
#
# Usage:
#   ./lathe/loop.sh start [--cycles N] [--tool claude|amp]
#   ./lathe/loop.sh stop
#   ./lathe/loop.sh status
#   ./lathe/loop.sh logs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$SCRIPT_DIR/state"
SKILLS_DIR="$SCRIPT_DIR/skills"
HISTORY_DIR="$STATE_DIR/history"
PID_FILE="$REPO_ROOT/.lathe.pid"
RETRO_INTERVAL=5
VM_SERVER="sovereign-0"

log() { echo "  [lathe] $(date '+%H:%M:%S') $*"; }

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
json.dump(data, open('$STATE_DIR/cycle.json', 'w'), indent=2)
"
}

archive_cycle() {
    local cycle="$1"
    local cycle_dir
    cycle_dir=$(printf "%s/cycle-%03d" "$HISTORY_DIR" "$cycle")
    mkdir -p "$cycle_dir"
    for f in snapshot.txt changelog.md; do
        [[ -f "$STATE_DIR/$f" ]] && cp "$STATE_DIR/$f" "$cycle_dir/"
    done
}

# ---------------------------------------------------------------------------
# Phase 1: Snapshot — collect cluster state with bash, no LLM
# ---------------------------------------------------------------------------

setup_kubeconfig() {
    # Set KUBECONFIG from Lima VM if available
    if limactl list "$VM_SERVER" --format '{{.Status}}' 2>/dev/null | grep -q "Running"; then
        KUBECONFIG=$(limactl list "$VM_SERVER" --format 'unix://{{.Dir}}/copied-from-guest/kubeconfig.yaml' 2>/dev/null)
        export KUBECONFIG
    fi
}

collect_snapshot() {
    log "Collecting cluster snapshot ..."
    local out="$STATE_DIR/snapshot.txt"

    {
        echo "# Cluster Snapshot"
        echo "Generated: $(date)"
        echo ""

        # Check Lima VMs
        echo "## Lima VMs"
        limactl list 2>/dev/null | grep -E 'sovereign-|NAME' || echo "(no VMs found)"
        echo ""

        echo "## Cluster Exists"
        if limactl list "$VM_SERVER" --format '{{.Status}}' 2>/dev/null | grep -q "Running"; then
            echo "yes — $VM_SERVER is Running"
            setup_kubeconfig
        else
            echo "NO — $VM_SERVER is not running. Use lima skill to create it."
            echo ""
            echo "## Pod Status"
            echo "(no cluster)"
            echo ""
            echo "## Helm Releases"
            echo "(no cluster)"
        fi
        echo ""

        # Only collect kubectl/helm data if kubeconfig is set and cluster responds
        if [[ -n "${KUBECONFIG:-}" ]] && timeout 5 kubectl cluster-info &>/dev/null; then
            echo "## Nodes"
            timeout 10 kubectl get nodes -o wide 2>&1 || echo "(kubectl failed)"
            echo ""

            echo "## Pod Status"
            timeout 10 kubectl get pods -A --no-headers 2>&1 | \
                awk '{printf "%-25s %-50s %-12s %s\n", $1, $2, $4, $5}' || echo "(kubectl failed)"
            echo ""

            echo "## Helm Releases"
            timeout 10 helm list -A 2>&1 || echo "(helm failed)"
            echo ""

            echo "## Recent Events (last 20)"
            timeout 10 kubectl get events -A --sort-by='.lastTimestamp' 2>&1 | tail -20 || echo "(no events)"
            echo ""

            # Capture logs from non-Running pods (capped: max 8 pods, 15 lines each)
            echo "## Failing Pod Logs"
            local failing_pods
            failing_pods=$(timeout 10 kubectl get pods -A --no-headers 2>/dev/null \
                | grep -v -E 'Running|Completed|Succeeded' \
                | head -8 \
                | awk '{print $1 "," $2}' || true)

            if [[ -z "$failing_pods" ]]; then
                echo "(all pods healthy)"
            else
                local pod_count=0
                while IFS=',' read -r ns pod; do
                    echo "### $ns/$pod"
                    echo '```'
                    timeout 5 kubectl logs -n "$ns" "$pod" --tail=15 2>&1 | head -15 || \
                        timeout 5 kubectl describe pod -n "$ns" "$pod" 2>&1 | tail -15 || \
                        echo "(no logs available)"
                    echo '```'
                    echo ""
                    pod_count=$((pod_count + 1))
                done <<< "$failing_pods"
                local total_failing
                total_failing=$(timeout 10 kubectl get pods -A --no-headers 2>/dev/null \
                    | grep -v -E 'Running|Completed|Succeeded' | wc -l | tr -d ' ')
                if (( total_failing > pod_count )); then
                    echo "(showing $pod_count of $total_failing failing pods)"
                fi
            fi

            echo "## Node Resources"
            timeout 10 kubectl top nodes 2>&1 || echo "(metrics-server not available)"
            echo ""
        fi
    } > "$out" 2>&1

    log "Snapshot written: $out"
}

# ---------------------------------------------------------------------------
# Phase 2: Agent — single claude --print call
# ---------------------------------------------------------------------------

run_agent() {
    local cycle="$1"
    local tool="${2:-claude}"

    log "Running agent (cycle $cycle) ..."

    # Assemble prompt: agent identity + all skills + snapshot + context
    local prompt=""
    prompt+="$(cat "$SCRIPT_DIR/agent.md")"
    prompt+=$'\n\n'

    # Inject all skills
    for skill_file in "$SKILLS_DIR"/*.md; do
        if [[ -f "$skill_file" ]]; then
            prompt+="---"$'\n'
            prompt+="# Skill: $(basename "$skill_file" .md)"$'\n\n'
            prompt+="$(cat "$skill_file")"
            prompt+=$'\n\n'
        fi
    done

    # Inject permanent decisions (if any)
    if [[ -f "$STATE_DIR/decisions.md" ]]; then
        prompt+="---"$'\n'
        prompt+="# PERMANENT DECISIONS — DO NOT REVISIT"$'\n\n'
        prompt+="$(cat "$STATE_DIR/decisions.md")"
        prompt+=$'\n\n'
    fi

    # Inject current snapshot
    prompt+="---"$'\n'
    prompt+="# Current Cluster Snapshot"$'\n\n'
    if [[ -f "$STATE_DIR/snapshot.txt" ]]; then
        prompt+="$(cat "$STATE_DIR/snapshot.txt")"
    else
        prompt+="(no snapshot collected)"
    fi
    prompt+=$'\n\n'

    # Inject previous cycle changelog
    local prev_cycle=$((cycle - 1))
    local prev_dir
    prev_dir=$(printf "%s/cycle-%03d" "$HISTORY_DIR" "$prev_cycle")
    if [[ -f "$prev_dir/changelog.md" ]]; then
        prompt+="---"$'\n'
        prompt+="# Previous Cycle Changelog (Cycle $prev_cycle)"$'\n\n'
        prompt+="$(cat "$prev_dir/changelog.md")"
        prompt+=$'\n\n'
    fi

    # Every N cycles: inject last N changelogs for pattern detection
    if (( cycle > 1 )) && (( cycle % RETRO_INTERVAL == 0 )); then
        prompt+="---"$'\n'
        prompt+="# Retro Mode — Last $RETRO_INTERVAL Cycles"$'\n'
        prompt+="Review the last $RETRO_INTERVAL cycles for patterns. Are we stuck? Making progress? Repeating the same fix?"$'\n\n'
        local start_cycle=$((cycle - RETRO_INTERVAL))
        (( start_cycle < 1 )) && start_cycle=1
        for (( c=start_cycle; c<cycle; c++ )); do
            local cdir
            cdir=$(printf "%s/cycle-%03d" "$HISTORY_DIR" "$c")
            if [[ -f "$cdir/changelog.md" ]]; then
                prompt+="## Cycle $c"$'\n'
                prompt+='```'$'\n'
                prompt+="$(cat "$cdir/changelog.md")"
                prompt+=$'\n''```'$'\n\n'
            fi
        done
    fi

    # Invoke
    local log_dir="$STATE_DIR/logs"
    mkdir -p "$log_dir"
    local log_file="$log_dir/cycle-$(printf '%03d' "$cycle").log"

    log "Prompt assembled. Invoking $tool ..."
    local exit_code=0

    if [[ "$tool" == "claude" ]]; then
        echo "$prompt" | claude --dangerously-skip-permissions --print 2>&1 \
            | tee "$log_file" || exit_code=$?
    else
        echo "$prompt" | amp --dangerously-allow-all 2>&1 \
            | tee "$log_file" || exit_code=$?
    fi

    # Rate limit detection — end cycle, don't sleep inside
    if grep -q "You've hit your limit" "$log_file" 2>/dev/null; then
        log "Rate limited. Ending cycle early. Will retry next cycle."
        echo "RATE_LIMITED" > "$STATE_DIR/rate-limited"
        return 1
    fi

    rm -f "$STATE_DIR/rate-limited"
    log "Agent complete (exit $exit_code). Log: $log_file"
    return "$exit_code"
}

# ---------------------------------------------------------------------------
# Rate limit backoff
# ---------------------------------------------------------------------------

wait_for_rate_limit() {
    if [[ ! -f "$STATE_DIR/rate-limited" ]]; then
        return 0
    fi
    log "Rate limited from previous cycle. Waiting 5 minutes before retry ..."
    local waited=0
    while (( waited < 300 )); do
        sleep 30 &
        wait $! || return 0
        waited=$((waited + 30))
        log "Rate limit cooldown: $((300 - waited))s remaining ..."
    done
    rm -f "$STATE_DIR/rate-limited"
    log "Cooldown complete. Resuming."
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

is_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

cmd_start() {
    local max_cycles=0
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

    mkdir -p "$STATE_DIR" "$HISTORY_DIR" "$STATE_DIR/logs"

    echo ""
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║  LATHE — starting continuous shaping   ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo ""

    (
        trap 'exit 0' SIGTERM

        # Redirect to log file to prevent SIGPIPE on terminal close
        exec >> "$STATE_DIR/logs/stream.log" 2>&1

        local cycle
        cycle=$(get_cycle)
        local cycles_run=0

        while true; do
            echo ""
            echo "═══════════════════════════════════════════════"
            echo "  CYCLE $cycle — $(date '+%Y-%m-%d %H:%M:%S')"
            echo "═══════════════════════════════════════════════"
            echo ""

            # Rate limit backoff from previous cycle
            wait_for_rate_limit

            set_cycle "$cycle" "running"

            # Phase 0: Fetch queued downloads from previous cycle
            if [[ -f "$SCRIPT_DIR/fetch.sh" ]] && [[ -f "$STATE_DIR/downloads.json" ]]; then
                local pending
                pending=$(python3 -c "import json; q=json.load(open('$STATE_DIR/downloads.json')); print(len([e for e in q if not e.get('done')]))" 2>/dev/null || echo 0)
                if (( pending > 0 )); then
                    log "Processing $pending queued downloads ..."
                    "$SCRIPT_DIR/fetch.sh" || log "WARN: some downloads failed (non-fatal)"
                fi
            fi

            # Phase 1: Snapshot (~30s)
            collect_snapshot

            # Phase 2: Agent (~3-4min)
            run_agent "$cycle" "$tool" || true

            # Phase 3: Commit + archive (~10s)
            cd "$REPO_ROOT"
            if ! git diff --quiet HEAD 2>/dev/null || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
                git add -A
                git commit -m "lathe: cycle ${cycle}" || true
                git push origin main 2>/dev/null || log "WARN: push failed (non-fatal)"
            fi

            archive_cycle "$cycle"
            set_cycle "$cycle" "complete"
            cycle=$((cycle + 1))
            cycles_run=$((cycles_run + 1))

            if (( max_cycles > 0 )) && (( cycles_run >= max_cycles )); then
                log "Completed $cycles_run cycles. Stopping."
                exit 0
            fi

            sleep 5 &
            wait $! || exit 0
        done
    ) &

    echo $! > "$PID_FILE"
    echo "  Started (PID $!). Tool: $tool"
    echo ""
    echo "  Logs:    tail -f $STATE_DIR/logs/stream.log"
    echo "  Status:  $0 status"
    echo "  Stop:    $0 stop"
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
    echo "=== Lathe ==="
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        local elapsed
        elapsed=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ' || echo "?")
        echo "  Running — PID $pid, uptime $elapsed"
    else
        echo "  Stopped"
    fi

    echo ""
    if [[ -f "$STATE_DIR/cycle.json" ]]; then
        python3 -c "
import json
c = json.load(open('$STATE_DIR/cycle.json'))
print(f\"  Cycle: {c.get('cycle', '?')}  Status: {c.get('status', '?')}\")
print(f\"  Updated: {c.get('updatedAt', '?')[:19]}\")
"
    fi

    if [[ -f "$STATE_DIR/rate-limited" ]]; then
        echo "  ** RATE LIMITED — waiting for cooldown **"
    fi

    echo ""
    local latest
    latest=$(ls -t "$STATE_DIR/logs"/cycle-*.log 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        echo "  Latest log: $latest"
        echo "  Last 5 lines:"
        tail -5 "$latest" | sed 's/^/    /'
    fi
}

cmd_logs() {
    local latest
    latest=$(ls -t "$STATE_DIR/logs"/cycle-*.log 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        echo "=== Latest: $(basename "$latest") ==="
        echo ""
        tail -80 "$latest"
        echo ""
        echo "---"
        echo "  Tail live:  tail -f $latest"
        echo "  Stream:     tail -f $STATE_DIR/logs/stream.log"
    else
        echo "  No logs yet."
    fi
}

# ---------------------------------------------------------------------------
case "${1:-help}" in
    start)   shift; cmd_start "$@" ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    logs)    cmd_logs ;;
    *)
        echo "Usage: $0 start [--cycles N] [--tool claude|amp] | stop | status | logs"
        exit 1
        ;;
esac
