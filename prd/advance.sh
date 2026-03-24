#!/usr/bin/env bash
# prd/advance.sh — thin wrapper; delegates to scripts/ralph/lib/advance.py
# Usage: ./prd/advance.sh [--dry-run]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$REPO_ROOT/scripts/ralph/lib/advance.py" \
  --repo-root "$REPO_ROOT" \
  "$@"
