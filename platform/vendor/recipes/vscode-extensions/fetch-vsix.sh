#!/usr/bin/env bash
# vendor/recipes/vscode-extensions/fetch-vsix.sh — Download VS Code extensions from Open VSX
#
# Downloads VSIX files for extensions listed in platform/charts/code-server/values.yaml,
# verifies SHA256 checksums, and writes files at the path the install-extensions
# initContainer expects:
#   <output-dir>/vsix/<publisher>/<name>/latest.vsix
#
# Serve <output-dir> with any HTTP server reachable from the cluster. Then set
# .Values.extensionRegistry in the code-server ArgoCD app values to activate
# offline extension install. The initContainer constructs:
#   <extensionRegistry>/vsix/<publisher>/<name>/latest.vsix
#
# Usage:
#   fetch-vsix.sh [--output-dir DIR] [--dry-run] [--backup URL]
#
# Options:
#   --output-dir DIR    Directory to write VSIX files (default: ./vsix-cache)
#   --dry-run           Print actions without downloading
#   --backup URL        After primary download, PUT files to a secondary HTTP endpoint
#
# Dependencies: curl, python3, sha256sum (Linux) or shasum (macOS)
# Source:        Open VSX registry — https://open-vsx.org (Eclipse Public License 2.0)
# Note:          Individual extension licenses vary; verify each before vendoring.
#                Run vendor/audit.sh to cross-check against license-policy.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
VALUES_FILE="$REPO_ROOT/platform/charts/code-server/values.yaml"
OUTPUT_DIR="./vsix-cache"
DRY_RUN=false
BACKUP_URL=""
OPEN_VSX_API="https://open-vsx.org/api"

usage() {
  grep '^#' "$0" | sed 's/^# *//' | sed -n '/^Usage:/,/^$/p'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --backup)     BACKUP_URL="$2"; shift 2 ;;
    --help|-h)    usage ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Extract extension list from values.yaml (publisher.name format)
EXTENSIONS=()
while IFS= read -r ext; do
  [[ -n "$ext" ]] && EXTENSIONS+=("$ext")
done < <(python3 - "$VALUES_FILE" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    vals = yaml.safe_load(f)
for ext in vals.get('extensions', []):
    print(ext)
PYEOF
)

if [[ ${#EXTENSIONS[@]} -eq 0 ]]; then
  echo "FAIL: no extensions found in $VALUES_FILE" >&2
  exit 1
fi

echo "fetch-vsix: ${#EXTENSIONS[@]} extension(s) from Open VSX"
echo "output-dir: $OUTPUT_DIR"
if [ "$DRY_RUN" = "true" ]; then
  echo "mode:       dry-run (no files written)"
fi

FAILED=0

for ext in "${EXTENSIONS[@]}"; do
  publisher="${ext%%.*}"
  name="${ext#*.}"
  dest_dir="$OUTPUT_DIR/vsix/$publisher/$name"
  dest_file="$dest_dir/latest.vsix"

  echo ""
  echo "--- $ext"

  if [ "$DRY_RUN" = "true" ]; then
    echo "  DRY-RUN: GET $OPEN_VSX_API/$publisher/$name/latest"
    echo "  DRY-RUN: write $dest_file"
    continue
  fi

  # Fetch extension metadata from Open VSX API
  meta_json=""
  meta_json=$(curl -sf "$OPEN_VSX_API/$publisher/$name/latest" || true)
  if [[ -z "$meta_json" ]]; then
    echo "  FAIL: metadata fetch failed for $ext" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  # Parse download URL and expected SHA256 from metadata JSON
  download_url=""
  download_url=$(echo "$meta_json" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['files']['download'])" \
    2>/dev/null || true)
  if [[ -z "$download_url" ]]; then
    echo "  FAIL: no download URL in metadata for $ext" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  expected_sha=""
  expected_sha=$(echo "$meta_json" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('sha256',''))" \
    2>/dev/null || true)

  # Download to temp file, then move to dest on success
  tmp_file=$(mktemp "/tmp/${publisher}.${name}.XXXXXX.vsix")

  echo "  GET $download_url"
  if ! curl -sf -L -o "$tmp_file" "$download_url"; then
    echo "  FAIL: download failed for $ext" >&2
    rm -f "$tmp_file"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Verify SHA256 checksum when available
  if [[ -n "$expected_sha" ]]; then
    actual_sha=""
    if command -v sha256sum >/dev/null 2>&1; then
      actual_sha=$(sha256sum "$tmp_file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
      actual_sha=$(shasum -a 256 "$tmp_file" | cut -d' ' -f1)
    else
      echo "  WARN: no sha256sum or shasum; skipping checksum verification"
      actual_sha="$expected_sha"
    fi
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      echo "  FAIL: SHA256 mismatch for $ext" >&2
      echo "        expected: $expected_sha" >&2
      echo "        actual:   $actual_sha" >&2
      rm -f "$tmp_file"
      FAILED=$((FAILED + 1))
      continue
    fi
    echo "  SHA256 OK: $actual_sha"
  else
    echo "  WARN: no checksum in Open VSX metadata for $ext; skipping verification"
  fi

  mkdir -p "$dest_dir"
  mv "$tmp_file" "$dest_file"
  echo "  OK: $dest_file"

  # Backup: PUT to secondary HTTP endpoint when requested
  if [[ -n "$BACKUP_URL" ]]; then
    backup_target="$BACKUP_URL/vsix/$publisher/$name/latest.vsix"
    echo "  backup: PUT $backup_target"
    if ! curl -sf -X PUT -T "$dest_file" "$backup_target"; then
      echo "  WARN: backup upload failed for $ext (primary copy retained)"
    fi
  fi
done

echo ""
if [[ "$FAILED" -gt 0 ]]; then
  echo "FAIL: $FAILED extension(s) could not be downloaded" >&2
  exit 1
fi

echo "OK: all extensions written to $OUTPUT_DIR"
echo ""
echo "Next: serve $OUTPUT_DIR with an HTTP server reachable from the cluster."
echo "Then set extensionRegistry in the code-server ArgoCD app values:"
echo "  extensionRegistry: \"https://<serving-host>\""
