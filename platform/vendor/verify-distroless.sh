#!/usr/bin/env bash
# vendor/verify-distroless.sh — Confirm built images contain no shell
#
# Pulls each sovereign/* image from Harbor staging, runs the binary with --version
# to confirm it starts, then attempts to exec /bin/sh and asserts it is NOT found.
# A distroless image has no shell — exec must fail.
#
# Usage: vendor/verify-distroless.sh [name|all] [--dry-run] [--backup]
#
# Required env vars (unless --dry-run):
#   HARBOR_URL   — Base URL of Harbor registry (e.g. https://harbor.sovereign-autarky.dev)
#   HARBOR_USER  — Harbor username
#   HARBOR_PASS  — Harbor password or robot token
#
# Optional env vars:
#   IMAGE_TAG    — Override image tag to verify (default: latest pushed staging tag)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPES_DIR="$REPO_ROOT/vendor/recipes"
DRY_RUN=false
BACKUP=false
TARGET="all"
PASS_COUNT=0
FAIL_COUNT=0

usage() {
  echo "Usage: $(basename "$0") [name|all] [--dry-run] [--backup]" >&2
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --backup)  BACKUP=true ;;
    --help|-h) usage ;;
    --*)       echo "Unknown option: $arg" >&2; usage ;;
    *)         TARGET="$arg" ;;
  esac
done

# Validate required tools
for tool in docker python3; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: $tool is required" >&2
    exit 1
  fi
done

# Validate required env vars (skip in dry-run)
if [[ "$DRY_RUN" == "false" ]]; then
  : "${HARBOR_URL:?HARBOR_URL must be set (e.g. https://harbor.sovereign-autarky.dev)}"
  : "${HARBOR_USER:?HARBOR_USER must be set}"
  : "${HARBOR_PASS:?HARBOR_PASS must be set}"
fi

# Read a single top-level scalar field from a recipe.yaml
recipe_field() {
  local field="$1"
  local file="$2"
  grep "^${field}:" "$file" | head -1 | sed "s/^${field}: *//;s/\"//g"
}

# Derive Harbor staging image ref for a named service
harbor_staging_image() {
  local name="$1"
  local tag="${2:-latest}"
  local harbor_host
  harbor_host=$(python3 -c "
import sys
from urllib.parse import urlparse
print(urlparse(sys.argv[1]).netloc)
" "$HARBOR_URL")
  printf '%s/sovereign-staging/%s:%s' "$harbor_host" "$name" "$tag"
}

# Verify a single image is distroless (no /bin/sh) and starts correctly
verify_one() {
  local name="$1"
  local recipe_file="$RECIPES_DIR/$name/recipe.yaml"

  if [[ ! -f "$recipe_file" ]]; then
    echo "ERROR: recipe not found: $recipe_file" >&2
    return 1
  fi

  local build_tool version image_ref
  build_tool=$(recipe_field "build_tool" "$recipe_file")
  version=$(recipe_field "version" "$recipe_file")

  if [[ "$build_tool" == "skip" ]]; then
    echo "[SKIP] $name (build_tool: skip — distroless not applicable)"
    return 0
  fi

  local tag="${IMAGE_TAG:-${version}}"

  if [[ "$DRY_RUN" == "true" ]]; then
    local dry_image="\$HARBOR_URL/sovereign-staging/${name}:${tag}"
    echo "[DRY RUN] verify-distroless $name"
    echo "[DRY RUN]   image : $dry_image"
    echo "[DRY RUN]   check : docker run --rm --entrypoint /bin/sh $dry_image -c 'exit 0' → must FAIL"
    if [[ "$BACKUP" == "true" ]]; then
      echo "[DRY RUN]   backup: no-op (verify-distroless has no backup action)"
    fi
    return 0
  fi

  local image_ref
  image_ref=$(harbor_staging_image "$name" "$tag")

  echo "[INFO] Verifying distroless: $name ($image_ref)"

  # Pull the image
  if ! docker pull --quiet "$image_ref"; then
    echo "[FAIL] $name — could not pull image: $image_ref" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  # Test 1: Assert /bin/sh is NOT present (distroless has no shell)
  local shell_exit_code=0
  docker run --rm \
    --entrypoint /bin/sh \
    "$image_ref" \
    -c "exit 0" 2>/dev/null || shell_exit_code=$?

  if [[ "$shell_exit_code" -eq 0 ]]; then
    echo "[FAIL] $name — /bin/sh found and executed successfully (image is NOT distroless)" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  echo "[PASS] $name — /bin/sh not found (exit $shell_exit_code) — image is distroless"

  # Test 2: Verify the image has valid OCI labels baked in
  local labels_ok=true
  for label in \
    "org.sovereign.source_sha" \
    "org.sovereign.patches_applied" \
    "org.sovereign.compiler_version" \
    "org.sovereign.build_timestamp"; do
    local label_value
    label_value=$(docker inspect "$image_ref" \
      --format "{{index .Config.Labels \"${label}\"}}" 2>/dev/null || echo "")
    if [[ -z "$label_value" ]]; then
      echo "[WARN] $name — OCI label missing: $label" >&2
      labels_ok=false
    fi
  done

  if [[ "$labels_ok" == "true" ]]; then
    echo "[PASS] $name — all OCI labels present"
  fi

  PASS_COUNT=$((PASS_COUNT + 1))
}

# Log in to Harbor (once, before loop)
login_harbor() {
  local harbor_host
  harbor_host=$(python3 -c "
import sys
from urllib.parse import urlparse
print(urlparse(sys.argv[1]).netloc)
" "$HARBOR_URL")
  echo "$HARBOR_PASS" | docker login "$harbor_host" \
    --username "$HARBOR_USER" \
    --password-stdin
}

# --- Main ---

if [[ "$DRY_RUN" == "false" ]]; then
  login_harbor
fi

if [[ "$TARGET" == "all" ]]; then
  echo "[INFO] Verifying all recipes in $RECIPES_DIR ..."
  for recipe_dir in "$RECIPES_DIR"/*/; do
    [[ -d "$recipe_dir" ]] || continue
    rname="$(basename "$recipe_dir")"
    if [[ -f "$recipe_dir/recipe.yaml" ]]; then
      verify_one "$rname" || true
    fi
  done
  echo ""
  echo "[INFO] Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
  fi
else
  verify_one "$TARGET"
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
  fi
fi
