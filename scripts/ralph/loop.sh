#!/usr/bin/env bash
# loop.sh — Run the ceremonies delivery machine continuously in the background.
#
# Usage:
#   ./loop.sh start [--tool claude|amp]   # start the loop in background
#   ./loop.sh stop                        # stop the loop
#   ./loop.sh status                      # show running state + recent activity
#   ./loop.sh logs                        # tail the latest ceremony log
#
# The loop runs ceremonies.sh, sleeps 5s on success, and stops automatically
# on any fatal exit (preflight failure, proof-of-work exhausted, blocked orient).
# That stop is intentional — it means the machine needs human attention.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PID_FILE="$REPO_ROOT/.ceremonies.pid"
LOG_DIR="$REPO_ROOT/prd/logs"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

latest_log() {
    find "$LOG_DIR" -maxdepth 1 -name "ceremonies-*.log" -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_start() {
    local tool="claude"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    if is_running; then
        echo "Already running (PID $(cat "$PID_FILE")). Use 'stop' first."
        exit 1
    fi

    mkdir -p "$LOG_DIR"

    # The loop: run ceremonies, sleep briefly on success, stop on any fatal.
    # sleep is backgrounded + waited so SIGTERM actually interrupts the pause.
    (
        trap 'exit 0' SIGTERM
        while "$SCRIPT_DIR/ceremonies.sh" --tool "$tool"; do
            sleep 5 &
            wait $! || exit 0
        done
        echo "[loop.sh] ceremonies.sh exited non-zero — machine stopped for human review." \
            >> "$(latest_log || echo /dev/stderr)"
    ) &

    echo $! > "$PID_FILE"
    echo "Started (PID $!). Tool: $tool"
    echo ""
    echo "  Watch:  $0 logs"
    echo "  Check:  $0 status"
    echo "  Stop:   $0 stop"
}

cmd_stop() {
    if ! is_running; then
        echo "Not running."
        [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
        exit 0
    fi
    local pid
    pid=$(cat "$PID_FILE")

    # Kill children first (sleep, ceremonies.sh), then the subshell itself.
    pkill -TERM -P "$pid" 2>/dev/null
    kill -TERM "$pid" 2>/dev/null

    # Wait up to 5s for graceful shutdown.
    local _
    for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done

    # Force-kill stragglers.
    if kill -0 "$pid" 2>/dev/null; then
        pkill -9 -P "$pid" 2>/dev/null
        kill -9 "$pid" 2>/dev/null
    fi

    rm -f "$PID_FILE"
    echo "Stopped (PID $pid)."
}

cmd_status() {
    echo "=== Loop ==="
    if is_running; then
        echo "  Running — PID $(cat "$PID_FILE")"
    else
        echo "  Stopped"
        [[ -f "$PID_FILE" ]] && echo "  (stale PID file present — run 'stop' to clean up)"
    fi

    echo ""
    echo "=== Recent commits ==="
    git -C "$REPO_ROOT" log --oneline -8

    echo ""
    echo "=== Latest log ==="
    local log
    log=$(latest_log)
    if [[ -n "$log" ]]; then
        echo "  $log"
        echo ""
        tail -20 "$log"
    else
        echo "  No logs yet."
    fi
}

cmd_logs() {
    local log
    log=$(latest_log)
    if [[ -z "$log" ]]; then
        echo "No logs yet. Has the loop been started?"
        exit 1
    fi
    echo "Tailing: $log  (Ctrl-C to stop)"
    echo ""
    tail -f "$log"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${1:-help}" in
    start)  shift; cmd_start "$@" ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    logs)   cmd_logs ;;
    *)
        echo "Usage: $0 start [--tool claude|amp] | stop | status | logs"
        exit 1
        ;;
esac
