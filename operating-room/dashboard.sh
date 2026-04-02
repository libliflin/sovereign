#!/usr/bin/env bash
# operating-room/dashboard.sh — Tmux dashboard for the operating room.
#
# Layout:
#   ┌─ Agent Output (stream) ──────────────────────────────────────────┐
#   │  Live output from operator/counsel/surgeon                        │
#   ├─ Process Monitor ───────────────────────┬─ Cycle Monitor ─────────┤
#   │  Loop PID, Claude agents, helm/kubectl  │  Cycle state, pods      │
#   └─────────────────────────────────────────┴─────────────────────────┘
#
# Usage:
#   ./dashboard.sh [--cycles N]   # start loop + dashboard
#   ./dashboard.sh --attach-only  # attach to existing session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION="operating-room"
CYCLES=50

while [[ $# -gt 0 ]]; do
    case "$1" in
        --attach-only)
            tmux attach-session -t "$SESSION" 2>/dev/null || {
                echo "No '$SESSION' session. Run without --attach-only to create one."
                exit 1
            }
            exit 0
            ;;
        --cycles) CYCLES="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Kill any existing session
tmux kill-session -t "$SESSION" 2>/dev/null || true

# ── Process monitor pane script ──────────────────────────────────────────────
# Uses printf '\033[H\033[2J' (cursor home + erase display) instead of `clear`
# so content is rewritten in-place with no scrollback accumulation.

PROC_MONITOR=$(cat << 'MONITOR_EOF'
#!/usr/bin/env bash
REPO_ROOT="$1"
STATE_DIR="$REPO_ROOT/operating-room/state"

while true; do
    printf '\033[H\033[2J'
    printf "\033[1;36m═══ OPERATING ROOM PROCESSES ═══\033[0m\n\n"

    # Loop process
    if [[ -f "$REPO_ROOT/.operating-room.pid" ]]; then
        pid=$(cat "$REPO_ROOT/.operating-room.pid")
        if ps -p "$pid" &>/dev/null; then
            elapsed=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
            cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
            printf "\033[32m● Loop\033[0m  PID %-6s  up %-10s  CPU %s%%\n" "$pid" "$elapsed" "$cpu"
        else
            printf "\033[31m○ Loop\033[0m  DEAD (stale PID %s)\n" "$pid"
        fi
    else
        printf "\033[31m○ Loop\033[0m  NOT RUNNING\n"
    fi
    echo ""

    # Claude processes
    printf "\033[1;36m─── Claude Agents ───\033[0m\n"
    count=0
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        cpu=$(echo "$line" | awk '{print $3}')
        elapsed=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
        printf "  PID %-6s  CPU %-5s%%  up %s\n" "$pid" "$cpu" "$elapsed"
        count=$((count + 1))
    done < <(ps aux | grep 'claude.*--dangerously-skip-permissions' | grep -v grep)
    [[ $count -eq 0 ]] && printf "  \033[33m(none active)\033[0m\n"
    echo ""

    # Kubectl/helm processes
    printf "\033[1;36m─── Cluster Tools ───\033[0m\n"
    count=0
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i}' | cut -c1-55)
        printf "  PID %-6s  %s\n" "$pid" "$cmd"
        count=$((count + 1))
    done < <(ps aux | grep -E '(helm|kubectl)' | grep -v grep | head -6)
    [[ $count -eq 0 ]] && printf "  \033[33m(none active)\033[0m\n"

    sleep 5
done
MONITOR_EOF
)

# ── Cycle monitor pane script ─────────────────────────────────────────────────

CYCLE_MONITOR=$(cat << 'CYCLE_EOF'
#!/usr/bin/env bash
REPO_ROOT="$1"
STATE_DIR="$REPO_ROOT/operating-room/state"

while true; do
    printf '\033[H\033[2J'
    printf "\033[1;36m═══ CYCLE STATE ═══\033[0m\n\n"

    if [[ -f "$STATE_DIR/cycle.json" ]]; then
        python3 -c "
import json
c = json.load(open('$STATE_DIR/cycle.json'))
print(f\"  Cycle: {c.get('cycle','?')}    Phase: {c.get('status','?')}\")
print()
agents = c.get('agents', {})
for name in ['operator','counsel','surgeon','retro']:
    if name in agents:
        code = agents[name].get('exitCode','?')
        t = agents[name].get('lastRun','')[:19]
        mark = '\033[32m✓\033[0m' if code == 0 else '\033[31m✗\033[0m'
        print(f'  {mark} {name:<10s} exit={code}  {t}')
" 2>/dev/null
    else
        echo "  (no cycle data)"
    fi
    echo ""

    # Pod summary
    printf "\033[1;36m─── Cluster Pods ───\033[0m\n"
    if kubectl cluster-info --context kind-sovereign-test &>/dev/null; then
        running=0; failing=0; pending=0; total=0
        while IFS= read -r line; do
            total=$((total + 1))
            if echo "$line" | grep -qE 'Running|Completed'; then
                running=$((running + 1))
            elif echo "$line" | grep -qE 'Pending|ContainerCreating|Init:'; then
                pending=$((pending + 1))
            else
                failing=$((failing + 1))
            fi
        done < <(kubectl get pods -A --context kind-sovereign-test --no-headers 2>/dev/null)
        printf "  \033[32m● Running: %-3d\033[0m  " "$running"
        [[ $failing -gt 0 ]] \
            && printf "\033[31m● Failing: %-3d\033[0m  " "$failing" \
            || printf "○ Failing: 0    "
        printf "\033[33m● Pending: %-3d\033[0m  Total: %d\n" "$pending" "$total"

        # Show non-running pods
        echo ""
        kubectl get pods -A --context kind-sovereign-test --no-headers 2>/dev/null \
            | grep -vE 'Running|Completed' \
            | awk '{printf "  \033[33m%-20s %-30s %s\033[0m\n", $1, $2, $4}' \
            | head -10
    else
        printf "  \033[31mCluster unreachable\033[0m\n"
    fi
    echo ""

    # Recent logs
    printf "\033[1;36m─── Recent Logs ───\033[0m\n"
    ls -t "$STATE_DIR/logs/"*.log 2>/dev/null | head -5 | while read -r f; do
        size=$(wc -c < "$f" | tr -d ' ')
        mod=$(stat -f '%Sm' -t '%H:%M:%S' "$f" 2>/dev/null || date -r "$f" '+%H:%M:%S' 2>/dev/null)
        printf "  %s  %6s bytes  %s\n" "$mod" "$size" "$(basename "$f")"
    done

    sleep 10
done
CYCLE_EOF
)

# Write pane scripts to temp files
rm -f /tmp/or-monitor-*.sh || true
PROC_SCRIPT=$(mktemp /tmp/or-monitor-proc-XXXXXX.sh)
CYCLE_SCRIPT=$(mktemp /tmp/or-monitor-cycle-XXXXXX.sh)
echo "$PROC_MONITOR" > "$PROC_SCRIPT"
echo "$CYCLE_MONITOR" > "$CYCLE_SCRIPT"
chmod +x "$PROC_SCRIPT" "$CYCLE_SCRIPT"

# Start the loop (exits immediately, loop runs in background)
"$SCRIPT_DIR/loop.sh" start --cycles "${CYCLES}" || true

# Build tmux session:
#   Pane 0 (top 65%):   live agent log stream
#   Pane 1 (bot-left):  process monitor
#   Pane 2 (bot-right): cycle/pod monitor
#
# Commands are passed directly to new-session/split-window (not send-keys)
# so they don't echo into the pane and dimensions are set at attach time.

LOG_CMD="tail -n 0 -f '$REPO_ROOT/operating-room/state/logs/stream.log'"

tmux new-session -d -s "$SESSION" -c "$REPO_ROOT" "$LOG_CMD"

tmux split-window -v -t "${SESSION}.0" -p 35 -c "$REPO_ROOT" \
    "bash '$PROC_SCRIPT' '$REPO_ROOT'"

tmux split-window -h -t "${SESSION}.1" -c "$REPO_ROOT" \
    "bash '$CYCLE_SCRIPT' '$REPO_ROOT'"

# Pane titles
tmux select-pane -t "${SESSION}.0" -T "Agent Output"
tmux select-pane -t "${SESSION}.1" -T "Processes"
tmux select-pane -t "${SESSION}.2" -T "Cycle / Pods"

tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format "  #{pane_title}  "
tmux set-option -t "$SESSION" pane-active-border-style "fg=cyan"
tmux set-option -t "$SESSION" pane-border-style "fg=brightblack"

# Focus top pane
tmux select-pane -t "${SESSION}.0"

tmux attach-session -t "$SESSION"
