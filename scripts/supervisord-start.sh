#!/usr/bin/env bash
# supervisord-start.sh — Start the Sovereign pipeline under supervisord.
#
# Usage:
#   scripts/supervisord-start.sh [--tool claude|amp]
#
# Options:
#   --tool  Tool to use for ceremonies (default: claude)
#
# Prerequisites:
#   pip install supervisor
#
# The web dashboard will be available at http://127.0.0.1:9001 once started.
# Change the default credentials in supervisord.conf before use.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$REPO_ROOT/supervisord.conf"
PIDFILE="$REPO_ROOT/logs/supervisord.pid"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

RALPH_TOOL="claude"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool) RALPH_TOOL="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; echo "Usage: $0 [--tool claude|amp]" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

if ! command -v supervisord &>/dev/null; then
    echo "supervisord is not installed."
    echo ""
    echo "Install it with:"
    echo "  pip install supervisor"
    echo ""
    echo "Or with pipx (isolated install):"
    echo "  pipx install supervisor"
    exit 1
fi

if [[ ! -f "$CONF" ]]; then
    echo "Config file not found: $CONF" >&2
    exit 1
fi

# Check if already running by reading the PID file.
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "supervisord is already running (PID $(cat "$PIDFILE"))."
    echo ""
    echo "  Status:  supervisorctl -c $CONF status"
    echo "  Stop:    scripts/supervisord-stop.sh"
    exit 0
fi

# ---------------------------------------------------------------------------
# Ensure the logs directory exists
# ---------------------------------------------------------------------------

mkdir -p "$REPO_ROOT/logs"

# ---------------------------------------------------------------------------
# Start supervisord
# ---------------------------------------------------------------------------

echo "Starting supervisord..."
echo "  Config:  $CONF"
echo "  Tool:    $RALPH_TOOL"
echo "  Web UI:  http://127.0.0.1:9001"
echo ""

# Export RALPH_TOOL so supervisord inherits it and passes it to [program:ralph].
export RALPH_TOOL

supervisord -c "$CONF"

# Give it a moment to write the PID file.
sleep 1

# ---------------------------------------------------------------------------
# Show initial status
# ---------------------------------------------------------------------------

echo "supervisord started."
echo ""
supervisorctl -c "$CONF" status || true
echo ""
echo "Commands:"
echo "  Status:      supervisorctl -c $CONF status"
echo "  Logs:        supervisorctl -c $CONF tail -f ralph"
echo "  Web UI:      http://127.0.0.1:9001"
echo "  Stop:        scripts/supervisord-stop.sh"
echo "  Reload cfg:  supervisorctl -c $CONF reread && supervisorctl -c $CONF update"
