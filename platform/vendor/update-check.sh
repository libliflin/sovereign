#!/usr/bin/env bash
# vendor/update-check.sh — Check for upstream updates vs pinned versions
#
# For each recipe in vendor/recipes/, queries the upstream repository for
# available releases and compares to the pinned version. Outputs a report
# listing services that have newer versions available.
#
# Usage: vendor/update-check.sh [name|all] [--dry-run] [--backup]
#
# Optional env vars:
#   GITHUB_TOKEN  — GitHub personal access token (avoids rate limits for GitHub repos)
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

# --backup is a no-op for update-check (no artifacts produced)
if [[ "$BACKUP" == "true" ]]; then
  echo "[INFO] --backup flag set (no-op for update-check — no artifacts to push)"
fi

# Validate required tools
for tool in git python3; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: $tool is required" >&2
    exit 1
  fi
done

# Read a single top-level scalar field from a recipe.yaml
recipe_field() {
  local field="$1"
  local file="$2"
  grep "^${field}:" "$file" | head -1 | sed "s/^${field}: *//;s/\"//g"
}

# Extract owner/repo from a GitHub URL
# https://github.com/owner/repo  →  owner/repo
github_slug() {
  local url="$1"
  printf '%s' "$url" | sed 's|https://github.com/||;s|\.git$||'
}

# Fetch the latest release tag from GitHub API
# Falls back to git ls-remote if GITHUB_TOKEN is not set or repo is not on GitHub
latest_github_tag() {
  local slug="$1"
  local auth_header=""
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_header="Authorization: Bearer $GITHUB_TOKEN"
  fi

  local latest_tag
  # Try GitHub releases API first (only returns stable releases, not pre-releases)
  if [[ -n "$auth_header" ]]; then
    latest_tag=$(curl -sf \
      -H "$auth_header" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$slug/releases/latest" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name',''))" \
      2>/dev/null || echo "")
  else
    latest_tag=$(curl -sf \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$slug/releases/latest" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name',''))" \
      2>/dev/null || echo "")
  fi

  printf '%s' "$latest_tag"
}

# Fetch the latest tag from any git remote using ls-remote
latest_git_tag() {
  local upstream_url="$1"
  # Get all tags, sort by version (semver-ish), return the last one
  git ls-remote --tags --refs "$upstream_url" 2>/dev/null \
    | awk '{print $2}' \
    | sed 's|refs/tags/||' \
    | grep -E '^v[0-9]+\.[0-9]+' \
    | sort -V \
    | tail -1 \
    || echo ""
}

# Check a single recipe for updates
check_one() {
  local name="$1"
  local recipe_file="$RECIPES_DIR/$name/recipe.yaml"

  if [[ ! -f "$recipe_file" ]]; then
    echo "ERROR: recipe not found: $recipe_file" >&2
    return 1
  fi

  local upstream_url version
  upstream_url=$(recipe_field "upstream_url" "$recipe_file")
  version=$(recipe_field "version" "$recipe_file")

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] check $name: pinned=$version upstream=$upstream_url"
    return 0
  fi

  local latest_tag=""

  # Use GitHub API for GitHub-hosted repos (faster, more reliable)
  if printf '%s' "$upstream_url" | grep -q "github.com"; then
    local slug
    slug=$(github_slug "$upstream_url")
    latest_tag=$(latest_github_tag "$slug")
    # Fall back to git ls-remote if API returned nothing
    if [[ -z "$latest_tag" ]]; then
      latest_tag=$(latest_git_tag "$upstream_url")
    fi
  else
    latest_tag=$(latest_git_tag "$upstream_url")
  fi

  if [[ -z "$latest_tag" ]]; then
    printf '  %-25s  pinned=%-15s  latest=%-15s  %s\n' \
      "$name" "$version" "unknown" "[could not determine]"
    return 0
  fi

  if [[ "$version" == "$latest_tag" ]]; then
    printf '  %-25s  pinned=%-15s  latest=%-15s  %s\n' \
      "$name" "$version" "$latest_tag" "[up to date]"
  else
    printf '  %-25s  pinned=%-15s  latest=%-15s  %s\n' \
      "$name" "$version" "$latest_tag" "[UPDATE AVAILABLE]"
  fi
}

# --- Main ---

if [[ "$DRY_RUN" == "false" ]]; then
  echo "=== Sovereign Vendor Update Check ==="
  echo ""
fi

if [[ "$TARGET" == "all" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would check all recipes in $RECIPES_DIR for upstream updates"
  else
    printf '  %-25s  %-22s  %-22s  %s\n' "service" "pinned" "latest" "status"
    printf '  %s\n' "---------------------------------------------------------------------"
  fi
  for recipe_dir in "$RECIPES_DIR"/*/; do
    [[ -d "$recipe_dir" ]] || continue
    rname="$(basename "$recipe_dir")"
    if [[ -f "$recipe_dir/recipe.yaml" ]]; then
      check_one "$rname" || echo "[WARN] Failed to check $rname" >&2
    fi
  done
  if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    echo "Run: vendor/pin.sh <name> <version> to update a pinned version."
  fi
else
  if [[ "$DRY_RUN" == "false" ]]; then
    printf '  %-25s  %-22s  %-22s  %s\n' "service" "pinned" "latest" "status"
    printf '  %s\n' "---------------------------------------------------------------------"
  fi
  check_one "$TARGET"
fi
