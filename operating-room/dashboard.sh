#!/usr/bin/env bash
# operating-room/dashboard.sh — Tmux dashboard for the operating room.
#
# Spawns a 4-pane tmux session:
#   ┌──────────────────┬──────────────────┐
#   │                  │                  │
#   │  Loop output     │  Process monitor │
#   │                  │                  │
#   ├──────────────────┼──────────────────┤
#   │                  │                  │
#   │  Live log stream │  Monitor dash    │
#   │                  │                  │
#   └──────────────────┴──────────────────┘
#
# Usage:
#   ./dashboard.sh                    # start loop + dashboard
#   ./dashboard.sh --cycles 50        # start with cycle limit
#   ./dashboard.sh --attach-only      # attach to existing session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION="operating-room"
CYCLES="${1:-50}"

if [[ "${1:-}" == "--attach-only" ]]; then
    tmux attach-session -t "$SESSION" 2>/dev/null || {
        echo "No '$SESSION' session found. Run without --attach-only to create one."
        exit 1
    }
    exit 0
fi

# Parse --cycles flag
if [[ "${1:-}" == "--cycles" ]]; then
    CYCLES="${2:-50}"
fi

# Kill existing session if present
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Create the process monitor script (inline, runs in a pane)
PROC_MONITOR=$(cat << 'MONITOR_EOF'
#!/usr/bin/env bash
REPO_ROOT="$1"
STATE_DIR="$REPO_ROOT/operating-room/state"

while true; do
    clear
    printf "\033[1;36m═══ OPERATING ROOM PROCESSES ═══\033[0m\n\n"

    # Loop process
    if [[ -f "$REPO_ROOT/.operating-room.pid" ]]; then
        pid=$(cat "$REPO_ROOT/.operating-room.pid")
        if ps -p "$pid" &>/dev/null; then
            elapsed=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
            cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
            printf "\033[32m● Loop\033[0m  PID %-6s  up %-12s  CPU %s%%\n" "$pid" "$elapsed" "$cpu"
        else
            printf "\033[31m○ Loop\033[0m  DEAD (stale PID %s)\n" "$pid"
        fi
    else
        printf "\033[31m○ Loop\033[0m  NOT RUNNING\n"
    fi
    echo ""

    # Claude processes
    printf "\033[1;36m─── Claude Agents ───\033[0m\n"
    local_count=0
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        cpu=$(echo "$line" | awk '{print $3}')
        mem=$(echo "$line" | awk '{print $4}')
        elapsed=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
        printf "  PID %-6s  CPU %-5s%%  MEM %-5s%%  up %s\n" "$pid" "$cpu" "$mem" "$elapsed"
        local_count=$((local_count + 1))
    done < <(ps aux | grep 'claude.*--dangerously-skip-permissions' | grep -v grep)
    if [[ $local_count -eq 0 ]]; then
        printf "  \033[33m(none active)\033[0m\n"
    fi
    echo ""

    # Kubectl/helm processes
    printf "\033[1;36m─── Cluster Tools ───\033[0m\n"
    local_count=0
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | head -c 60)
        printf "  PID %-6s  %s\n" "$pid" "$cmd"
        local_count=$((local_count + 1))
    done < <(ps aux | grep -E '(helm|kubectl)' | grep -v grep | head -8)
    if [[ $local_count -eq 0 ]]; then
        printf "  \033[33m(none active)\033[0m\n"
    fi
    echo ""

    # Cycle state
    printf "\033[1;36m─── Cycle State ───\033[0m\n"
    if [[ -f "$STATE_DIR/cycle.json" ]]; then
        python3 -c "
import json
c = json.load(open('$STATE_DIR/cycle.json'))
print(f\"  Cycle: {c.get('cycle','?')}  Phase: {c.get('status','?')}\")
agents = c.get('agents', {})
for name in ['operator','counsel','surgeon','retro']:
    if name in agents:
        code = agents[name].get('exitCode','?')
        t = agents[name].get('lastRun','')[:19]
        mark = '✓' if code == 0 else '✗'
        print(f'  {mark} {name:10s} exit={code}  {t}')
" 2>/dev/null
    else
        echo "  (no cycle data)"
    fi
    echo ""

    # Cluster pod summary
    printf "\033[1;36m─── Cluster Pods ───\033[0m\n"
    if kubectl cluster-info --context kind-sovereign-test &>/dev/null; then
        local running=0 failing=0 pending=0 total=0
        while IFS= read -r line; do
            total=$((total + 1))
            if echo "$line" | grep -qE 'Running|Completed'; then
                running=$((running + 1))
            elif echo "$line" | grep -qE 'Pending|ContainerCreating'; then
                pending=$((pending + 1))
            else
                failing=$((failing + 1))
            fi
        done < <(kubectl get pods -A --context kind-sovereign-test --no-headers 2>/dev/null)
        printf "  \033[32m● Running: %-3d\033[0m  " "$running"
        if [[ $failing -gt 0 ]]; then
            printf "\033[31m● Failing: %-3d\033[0m  " "$failing"
        else
            printf "○ Failing: 0    "
        fi
        printf "\033[33m● Pending: %-3d\033[0m  Total: %d\n" "$pending" "$total"
    else
        printf "  \033[31mCluster unreachable\033[0m\n"
    fi
    echo ""

    # Log files
    printf "\033[1;36m─── Recent Logs ───\033[0m\n"
    ls -t "$STATE_DIR/logs/"*.log 2>/dev/null | head -5 | while read -r f; do
        size=$(wc -c < "$f" | tr -d ' ')
        mod=$(stat -f '%Sm' -t '%H:%M:%S' "$f" 2>/dev/null || stat -c '%y' "$f" 2>/dev/null | head -c 8)
        printf "  %s  %6s bytes  %s\n" "$mod" "$size" "$(basename "$f")"
    done

    sleep 5
done
MONITOR_EOF
)

# Write the process monitor to a temp file
PROC_SCRIPT=$(mktemp /tmp/or-proc-XXXXXX.sh)
echo "$PROC_MONITOR" > "$PROC_SCRIPT"
chmod +x "$PROC_SCRIPT"

# Create tmux session with 4 panes
# Pane 0 (top-left): Loop
tmux new-session -d -s "$SESSION" -c "$REPO_ROOT" \
    "echo '  Starting loop (${CYCLES} cycles)...'; sleep 1; ./operating-room/loop.sh start --cycles ${CYCLES}; echo ''; echo '  Loop exited. Press enter to close.'; read"

# Pane 1 (top-right): Process monitor
tmux split-window -h -t "$SESSION" -c "$REPO_ROOT" \
    "bash '$PROC_SCRIPT' '$REPO_ROOT'"

# Pane 2 (bottom-left): Live log stream
tmux split-window -v -t "${SESSION}.0" -c "$REPO_ROOT" \
    "echo '  Waiting for first log file...'; while [ ! -d operating-room/state/logs ] || [ -z \"\$(ls operating-room/state/logs/*.log 2>/dev/null)\" ]; do sleep 2; done; echo '  Tailing all logs...'; tail -f operating-room/state/logs/*.log"

# Pane 3 (bottom-right): Monitor dashboard
tmux split-window -v -t "${SESSION}.1" -c "$REPO_ROOT" \
    "./operating-room/loop.sh monitor 15"

# Set pane titles
tmux select-pane -t "${SESSION}.0" -T "Loop"
tmux select-pane -t "${SESSION}.1" -T "Processes"
tmux select-pane -t "${SESSION}.2" -T "Log Stream"
tmux select-pane -t "${SESSION}.3" -T "Dashboard"

# Enable pane borders with titles
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "

# Attach
tmux attach-session -t "$SESSION"
