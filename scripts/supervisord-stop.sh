#!/usr/bin/env bash
# supervisord-stop.sh — Gracefully stop the Sovereign pipeline and supervisord.
#
# Usage:
#   scripts/supervisord-stop.sh
#
# Sends SIGINT to the ralph process (mirrors Ctrl-C, allows ceremonies to
# finish cleanly), waits up to stopwaitsecs, then shuts down supervisord itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$REPO_ROOT/supervisord.conf"
PIDFILE="$REPO_ROOT/logs/supervisord.pid"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

if ! command -v supervisorctl &>/dev/null; then
    echo "supervisorctl not found — is supervisor installed?" >&2
    exit 1
fi

if [[ ! -f "$PIDFILE" ]] || ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "supervisord is not running."
    [[ -f "$PIDFILE" ]] && rm -f "$PIDFILE"
    exit 0
fi

# ---------------------------------------------------------------------------
# Stop managed processes gracefully
# ---------------------------------------------------------------------------

echo "Stopping managed processes..."
# supervisorctl stop sends the configured stopsignal (SIGINT) and waits up
# to stopwaitsecs (30s) for the process to exit cleanly.
supervisorctl -c "$CONF" stop all || true
echo ""

# ---------------------------------------------------------------------------
# Shut down supervisord itself
# ---------------------------------------------------------------------------

echo "Shutting down supervisord..."
supervisorctl -c "$CONF" shutdown || true

# Wait for the PID file to disappear (confirms clean exit).
local_timeout=15
elapsed=0
while [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [[ $elapsed -ge $local_timeout ]]; then
        echo "supervisord did not exit within ${local_timeout}s — sending SIGKILL." >&2
        kill -9 "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
        break
    fi
done

[[ -f "$PIDFILE" ]] && rm -f "$PIDFILE"
echo "supervisord stopped."
