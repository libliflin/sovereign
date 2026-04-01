#!/usr/bin/env bash
# operating-room/log-stream.sh — Aggregate new log lines into a single stream file.
#
# Watches operating-room/state/logs/ every 2 seconds. For each .log file,
# tracks how many bytes were read last time. Appends only new bytes to
# the stream file with a header showing which file they came from.
#
# Usage:
#   ./log-stream.sh              # run in background, tail the output
#   tail -f operating-room/state/logs/stream.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/state/logs"
STREAM="$LOG_DIR/stream.log"
OFFSETS="$LOG_DIR/.offsets"

mkdir -p "$LOG_DIR"
: > "$STREAM"
: > "$OFFSETS"

get_offset() {
    grep "^$1 " "$OFFSETS" 2>/dev/null | awk '{print $2}' || echo 0
}

set_offset() {
    local file="$1" size="$2"
    if grep -q "^$file " "$OFFSETS" 2>/dev/null; then
        sed -i '' "s|^$file .*|$file $size|" "$OFFSETS"
    else
        echo "$file $size" >> "$OFFSETS"
    fi
}

while true; do
    for f in "$LOG_DIR"/*.log; do
        [[ -f "$f" ]] || continue
        [[ "$f" == "$STREAM" ]] && continue

        basename_f=$(basename "$f")
        current_size=$(wc -c < "$f" | tr -d ' ')
        last_size=$(get_offset "$basename_f")

        if (( current_size > last_size )); then
            # Append header + new bytes to stream
            printf "\n\033[36m── %s (%s) ──\033[0m\n" "$basename_f" "$(date '+%H:%M:%S')" >> "$STREAM"
            tail -c +"$((last_size + 1))" "$f" >> "$STREAM"
            set_offset "$basename_f" "$current_size"
        fi
    done
    sleep 2
done
