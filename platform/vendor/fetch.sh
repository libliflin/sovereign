#!/usr/bin/env bash
# vendor/fetch.sh — Mirror upstream sources into internal GitLab
#
# Equivalent to Gentoo portage fetch: clones upstream at the pinned version and
# mirrors it into the internal GitLab vendor group so the cluster never needs to
# reach out to GitHub/external hosts at runtime.
#
# Usage: vendor/fetch.sh [name|all] [--dry-run] [--backup]
#
# Required env vars (unless --dry-run):
#   GITLAB_TOKEN  — GitLab personal access token with api + write_repository scopes
#   GITLAB_URL    — Base URL of internal GitLab (e.g. https://gitlab.sovereign-autarky.dev)
#
# Optional env vars (with --backup):
#   SECONDARY_REMOTE — Base URL for secondary git backup (e.g. https://backup.example.com/vendor)
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
for tool in git curl python3; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: $tool is required" >&2
    exit 1
  fi
done

# Validate required env vars (skip in dry-run)
if [[ "$DRY_RUN" == "false" ]]; then
  : "${GITLAB_TOKEN:?GITLAB_TOKEN must be set}"
  : "${GITLAB_URL:?GITLAB_URL must be set (e.g. https://gitlab.sovereign-autarky.dev)}"
fi

# Temp dir registry — cleaned up on EXIT
VENDOR_TMPDIRS=()
vendor_cleanup() {
  for d in "${VENDOR_TMPDIRS[@]+"${VENDOR_TMPDIRS[@]}"}"; do
    rm -rf "$d"
  done
}
trap vendor_cleanup EXIT

vendor_mktemp() {
  local d
  d=$(mktemp -d)
  VENDOR_TMPDIRS+=("$d")
  printf '%s' "$d"
}

# --- GitLab API helpers ---

gitlab_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sf -X "$method" \
      -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$body" \
      "$GITLAB_URL/api/v4$path"
  else
    curl -sf -X "$method" \
      -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "$GITLAB_URL/api/v4$path"
  fi
}

# Ensure GitLab group 'vendor' exists; print its numeric ID
ensure_vendor_group() {
  local group_id
  group_id=$(gitlab_api GET "/groups/vendor" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null \
    || echo "")
  if [[ -z "$group_id" ]]; then
    echo "[INFO] Creating GitLab group 'vendor'..." >&2
    group_id=$(gitlab_api POST "/groups" \
      '{"name":"vendor","path":"vendor","visibility":"private"}' \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'])")
  fi
  printf '%s' "$group_id"
}

# Ensure GitLab project vendor/<name> exists; print its HTTP clone URL
ensure_vendor_project() {
  local name="$1"
  local group_id="$2"
  local encoded_path="vendor%2F${name}"
  local clone_url
  clone_url=$(gitlab_api GET "/projects/$encoded_path" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('http_url_to_repo',''))" 2>/dev/null \
    || echo "")
  if [[ -z "$clone_url" ]]; then
    echo "[INFO] Creating GitLab project vendor/$name..." >&2
    clone_url=$(gitlab_api POST "/projects" \
      "{\"name\":\"$name\",\"path\":\"$name\",\"namespace_id\":$group_id,\"visibility\":\"private\"}" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['http_url_to_repo'])")
  fi
  printf '%s' "$clone_url"
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

# Read a single top-level scalar field from a recipe.yaml
recipe_field() {
  local field="$1"
  local file="$2"
  grep "^${field}:" "$file" | head -1 | sed "s/^${field}: *//;s/\"//g"
}

# --- Core fetch logic for a single recipe ---

fetch_one() {
  local name="$1"
  local recipe_file="$RECIPES_DIR/$name/recipe.yaml"

  if [[ ! -f "$recipe_file" ]]; then
    echo "ERROR: recipe not found: $recipe_file" >&2
    return 1
  fi

  local upstream_url version fetch_method git_sha
  upstream_url=$(recipe_field "upstream_url" "$recipe_file")
  version=$(recipe_field "version" "$recipe_file")
  fetch_method=$(recipe_field "fetch_method" "$recipe_file")
  git_sha=$(recipe_field "git_sha" "$recipe_file")

  if [[ -z "$upstream_url" || -z "$version" || -z "$fetch_method" ]]; then
    echo "ERROR: $name/recipe.yaml is missing upstream_url, version, or fetch_method" >&2
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] fetch $name @ $version (method: $fetch_method)"
    echo "[DRY RUN]   upstream : $upstream_url"
    if [[ -n "$git_sha" ]]; then
      echo "[DRY RUN]   git_sha  : $git_sha (will verify after clone)"
    fi
    echo "[DRY RUN]   mirror   : \$GITLAB_URL/vendor/$name"
    if [[ "$BACKUP" == "true" ]]; then
      echo "[DRY RUN]   backup   : \$SECONDARY_REMOTE/$name"
    fi
    return 0
  fi

  local src_dir
  src_dir=$(vendor_mktemp)

  echo "[INFO] Fetching $name @ $version ..."

  case "$fetch_method" in
    git_tag|git_commit)
      git clone --quiet --depth 1 --branch "$version" "$upstream_url" "$src_dir/src"
      # Verify pinned SHA matches what was actually cloned — abort if tag was tampered with
      if [[ -n "$git_sha" ]]; then
        local actual_sha
        actual_sha=$(git -C "$src_dir/src" rev-parse HEAD)
        if [[ "$actual_sha" != "$git_sha" ]]; then
          echo "ERROR: SHA mismatch for $name: pinned=$git_sha actual=$actual_sha" >&2
          echo "ERROR: The tag '$version' may have been moved or tampered with. Aborting." >&2
          return 1
        fi
        echo "[INFO] SHA verified: $name @ $actual_sha"
      fi
      ;;
    tarball)
      local tarball_url="${upstream_url}/archive/refs/tags/${version}.tar.gz"
      echo "[INFO] Downloading tarball: $tarball_url"
      mkdir -p "$src_dir/src"
      curl -fsSL "$tarball_url" | tar -xz -C "$src_dir/src" --strip-components=1
      git -C "$src_dir/src" init --quiet
      git -C "$src_dir/src" add .
      git -C "$src_dir/src" \
        -c user.email="sovereign@localhost" \
        -c user.name="Sovereign Vendor" \
        commit --quiet -m "vendor: $name $version"
      ;;
    *)
      echo "ERROR: Unknown fetch_method '$fetch_method' for $name" >&2
      return 1
      ;;
  esac

  # Ensure group and project exist in internal GitLab
  local group_id raw_push_url push_url
  group_id=$(ensure_vendor_group)
  raw_push_url=$(ensure_vendor_project "$name" "$group_id")
  push_url=$(embed_gitlab_token "$raw_push_url")

  # Tag pre-update state on existing mirror (best-effort)
  local ts existing_dir existing_push_url
  ts=$(date +%Y%m%d%H%M%S)
  existing_dir=$(vendor_mktemp)
  existing_push_url=$(embed_gitlab_token "$raw_push_url")
  if git clone --quiet --depth 1 "$existing_push_url" "$existing_dir/existing" 2>/dev/null; then
    git -C "$existing_dir/existing" tag "sovereign/pre-update-$ts" 2>/dev/null || true
    git -C "$existing_dir/existing" push --quiet "$existing_push_url" \
      "refs/tags/sovereign/pre-update-$ts" 2>/dev/null || true
  fi

  # Push source to internal GitLab
  git -C "$src_dir/src" remote add gitlab "$push_url"
  git -C "$src_dir/src" push --quiet gitlab HEAD:refs/heads/main --force
  git -C "$src_dir/src" push --quiet gitlab "refs/tags/$version" 2>/dev/null \
    || git -C "$src_dir/src" push --quiet gitlab --tags

  echo "[INFO] Mirrored $name @ $version → $GITLAB_URL/vendor/$name"

  # --backup: push to secondary remote
  if [[ "$BACKUP" == "true" ]]; then
    : "${SECONDARY_REMOTE:?SECONDARY_REMOTE must be set when using --backup}"
    echo "[INFO] Backing up $name to secondary remote..."
    git -C "$src_dir/src" remote add backup "$SECONDARY_REMOTE/$name"
    git -C "$src_dir/src" push backup HEAD:refs/heads/main --force
    git -C "$src_dir/src" push backup --tags
    echo "[INFO] Backed up $name → $SECONDARY_REMOTE/$name"
  fi
}

# --- Main ---

if [[ "$TARGET" == "all" ]]; then
  echo "[INFO] Fetching all recipes from $RECIPES_DIR ..."
  for recipe_dir in "$RECIPES_DIR"/*/; do
    [[ -d "$recipe_dir" ]] || continue
    rname="$(basename "$recipe_dir")"
    if [[ -f "$recipe_dir/recipe.yaml" ]]; then
      fetch_one "$rname" || echo "[WARN] Failed to fetch $rname" >&2
    fi
  done
  echo "[INFO] Done."
else
  fetch_one "$TARGET"
fi
