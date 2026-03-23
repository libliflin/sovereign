#!/usr/bin/env bash
# vendor/build.sh — Build OCI images from vendored sources
#
# Checks out source from internal GitLab at the pinned SHA, applies patches,
# calls the per-recipe build.sh, tags the image, and pushes to Harbor staging.
# No image is ever pushed to production — use deploy.sh to promote.
#
# Usage: vendor/build.sh [name|all] [--dry-run] [--backup]
#
# Required env vars (unless --dry-run):
#   GITLAB_TOKEN  — GitLab personal access token with api + read_repository scopes
#   GITLAB_URL    — Base URL of internal GitLab (e.g. https://gitlab.sovereign-autarky.dev)
#   HARBOR_URL    — Base URL of Harbor registry (e.g. https://harbor.sovereign-autarky.dev)
#   HARBOR_USER   — Harbor username (or robot account name)
#   HARBOR_PASS   — Harbor password or robot token
#
# Optional env vars:
#   SECONDARY_REGISTRY — Backup registry base URL (used with --backup)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPES_DIR="$REPO_ROOT/vendor/recipes"
DRY_RUN=false
BACKUP=false
TARGET="all"

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
for tool in git docker python3; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: $tool is required" >&2
    exit 1
  fi
done

# Validate required env vars (skip in dry-run)
if [[ "$DRY_RUN" == "false" ]]; then
  : "${GITLAB_TOKEN:?GITLAB_TOKEN must be set}"
  : "${GITLAB_URL:?GITLAB_URL must be set (e.g. https://gitlab.sovereign-autarky.dev)}"
  : "${HARBOR_URL:?HARBOR_URL must be set (e.g. https://harbor.sovereign-autarky.dev)}"
  : "${HARBOR_USER:?HARBOR_USER must be set}"
  : "${HARBOR_PASS:?HARBOR_PASS must be set}"
fi

# Temp dir registry — cleaned up on EXIT
BUILD_TMPDIRS=()
build_cleanup() {
  for d in "${BUILD_TMPDIRS[@]+"${BUILD_TMPDIRS[@]}"}"; do
    rm -rf "$d"
  done
}
trap build_cleanup EXIT

build_mktemp() {
  local d
  d=$(mktemp -d)
  BUILD_TMPDIRS+=("$d")
  printf '%s' "$d"
}

# Read a single top-level scalar field from a recipe.yaml
recipe_field() {
  local field="$1"
  local file="$2"
  grep "^${field}:" "$file" | head -1 | sed "s/^${field}: *//;s/\"//g"
}

# Embed oauth2 token into a GitLab HTTPS URL
embed_gitlab_token() {
  local url="$1"
  python3 -c "
import sys
url, token = sys.argv[1], sys.argv[2]
print(url.replace('https://', 'https://oauth2:' + token + '@', 1))
" "$url" "$GITLAB_TOKEN"
}

# Derive the Harbor staging repo for a named service
harbor_staging_repo() {
  local name="$1"
  local harbor_host
  harbor_host=$(python3 -c "
import sys
from urllib.parse import urlparse
print(urlparse(sys.argv[1]).netloc)
" "$HARBOR_URL")
  printf '%s/sovereign-staging/%s' "$harbor_host" "$name"
}

# Apply patches from vendor/recipes/<name>/patches/ in alphabetical order
apply_patches() {
  local name="$1"
  local src_dir="$2"
  local patches_dir="$RECIPES_DIR/$name/patches"
  local patch_count=0

  if [[ ! -d "$patches_dir" ]]; then
    printf '%d' "$patch_count"
    return 0
  fi

  # SC2045: use nullglob-safe glob expansion
  local patch_files
  patch_files=$(find "$patches_dir" -maxdepth 1 -name '*.patch' | sort)

  if [[ -z "$patch_files" ]]; then
    printf '%d' "$patch_count"
    return 0
  fi

  while IFS= read -r patch_file; do
    [[ -f "$patch_file" ]] || continue
    echo "[INFO]   Applying patch: $(basename "$patch_file")" >&2
    git -C "$src_dir" apply "$patch_file"
    patch_count=$((patch_count + 1))
  done <<< "$patch_files"

  printf '%d' "$patch_count"
}

# --- Core build logic for a single recipe ---

build_one() {
  local name="$1"
  local recipe_file="$RECIPES_DIR/$name/recipe.yaml"
  local build_script="$RECIPES_DIR/$name/build.sh"

  if [[ ! -f "$recipe_file" ]]; then
    echo "ERROR: recipe not found: $recipe_file" >&2
    return 1
  fi

  local version git_sha build_tool go_version
  version=$(recipe_field "version" "$recipe_file")
  git_sha=$(recipe_field "git_sha" "$recipe_file")
  build_tool=$(recipe_field "build_tool" "$recipe_file")
  go_version=$(recipe_field "go_version" "$recipe_file")

  if [[ "$build_tool" == "skip" ]]; then
    echo "[INFO] Skipping $name (build_tool: skip — incompatible with distroless build)"
    return 0
  fi

  if [[ ! -f "$build_script" ]]; then
    echo "[SKIP] $name — no build.sh yet (vendor/recipes/$name/build.sh not found)"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] build $name @ $version"
    echo "[DRY RUN]   source  : \$GITLAB_URL/vendor/$name @ ${git_sha:-<unpinned>}"
    echo "[DRY RUN]   tool    : $build_tool"
    echo "[DRY RUN]   staging : \$HARBOR_URL/sovereign-staging/$name:<version>-<sha>-p<n>"
    if [[ "$BACKUP" == "true" ]]; then
      echo "[DRY RUN]   backup  : \$SECONDARY_REGISTRY/sovereign-staging/$name"
    fi
    return 0
  fi

  local src_dir
  src_dir=$(build_mktemp)

  echo "[INFO] Building $name @ $version ..."

  # Clone from internal GitLab at the pinned SHA
  local gitlab_project_url clone_url
  gitlab_project_url="$GITLAB_URL/vendor/$name.git"
  clone_url=$(embed_gitlab_token "$gitlab_project_url")
  git clone --quiet "$clone_url" "$src_dir/src"

  if [[ -n "$git_sha" ]]; then
    git -C "$src_dir/src" checkout --quiet "$git_sha"
    echo "[INFO] Checked out $name @ $git_sha"
  fi

  # Apply patches from vendor/recipes/<name>/patches/ in alphabetical order
  local patch_count
  patch_count=$(apply_patches "$name" "$src_dir/src")
  echo "[INFO] Applied $patch_count patch(es) to $name"

  # Compute image tag: <version>-<short_sha>-p<patch_count>
  local source_sha short_sha image_tag
  source_sha=$(git -C "$src_dir/src" rev-parse HEAD)
  short_sha="${source_sha:0:7}"
  image_tag="${version}-${short_sha}-p${patch_count}"

  # Harbor staging repository for this service
  local staging_repo build_timestamp
  staging_repo=$(harbor_staging_repo "$name")
  build_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  echo "[INFO] Image tag: $image_tag"
  echo "[INFO] Staging:   $staging_repo:$image_tag"

  # Log in to Harbor
  echo "$HARBOR_PASS" | docker login \
    "$(python3 -c "import sys; from urllib.parse import urlparse; print(urlparse(sys.argv[1]).netloc)" "$HARBOR_URL")" \
    --username "$HARBOR_USER" \
    --password-stdin

  # Export env vars for the per-recipe build.sh
  export KO_DOCKER_REPO="$staging_repo"
  export IMAGE_TAG="$image_tag"
  export SOVEREIGN_SOURCE_SHA="$source_sha"
  export SOVEREIGN_PATCHES_APPLIED="$patch_count"
  export SOVEREIGN_COMPILER_VERSION="${go_version:-unknown}"
  export SOVEREIGN_BUILD_TIMESTAMP="$build_timestamp"
  export SOVEREIGN_NAME="$name"

  # Run the per-recipe build.sh from within the source directory
  echo "[INFO] Running build script for $name ..."
  (cd "$src_dir/src" && bash "$build_script")

  echo "[INFO] Built and pushed: $staging_repo:$image_tag"

  # --backup: copy image to secondary registry
  if [[ "$BACKUP" == "true" ]]; then
    : "${SECONDARY_REGISTRY:?SECONDARY_REGISTRY must be set when using --backup}"
    local backup_repo="${SECONDARY_REGISTRY}/sovereign-staging/${name}"
    echo "[INFO] Copying $name to backup registry ..."
    if command -v crane &>/dev/null; then
      crane copy "$staging_repo:$image_tag" "$backup_repo:$image_tag"
    else
      docker tag "$staging_repo:$image_tag" "$backup_repo:$image_tag"
      docker push "$backup_repo:$image_tag"
    fi
    echo "[INFO] Backed up: $backup_repo:$image_tag"
  fi
}

# --- Main ---

if [[ "$TARGET" == "all" ]]; then
  echo "[INFO] Building all recipes from $RECIPES_DIR ..."
  for recipe_dir in "$RECIPES_DIR"/*/; do
    [[ -d "$recipe_dir" ]] || continue
    rname="$(basename "$recipe_dir")"
    if [[ -f "$recipe_dir/recipe.yaml" ]]; then
      build_one "$rname" || echo "[WARN] Failed to build $rname" >&2
    fi
  done
  echo "[INFO] Done."
else
  build_one "$TARGET"
fi
