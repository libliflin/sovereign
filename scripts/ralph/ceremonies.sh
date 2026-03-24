#!/usr/bin/env bash
# ceremonies.sh — thin wrapper; delegates to ceremonies.py
# Kept for backwards compatibility and tab-completion.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/ceremonies.py" "$@"
