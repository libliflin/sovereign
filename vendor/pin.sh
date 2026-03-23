#!/usr/bin/env bash
# vendor/pin.sh — Pin a vendor recipe to a specific version
#
# Updates the version field in vendor/recipes/<name>/recipe.yaml.
# Use after running vendor/update-check.sh to apply a new upstream version.
#
# Usage: vendor/pin.sh <name> <version> [--dry-run] [--backup]
#
# Examples:
#   vendor/pin.sh cert-manager v1.15.0
#   vendor/pin.sh argocd v2.11.0 --dry-run
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIPES_DIR="$REPO_ROOT/vendor/recipes"
DRY_RUN=false
BACKUP=false
POSITIONAL=()

usage() {
  echo "Usage: $(basename "$0") <name> <version> [--dry-run] [--backup]" >&2
  echo "" >&2
  echo "  name     — recipe name (directory under vendor/recipes/)" >&2
  echo "  version  — new version tag to pin (e.g. v1.15.0)" >&2
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --backup)  BACKUP=true ;;
    --help|-h) usage ;;
    --*)       echo "Unknown option: $arg" >&2; usage ;;
    *)         POSITIONAL+=("$arg") ;;
  esac
done

if [[ "${#POSITIONAL[@]}" -lt 2 ]]; then
  echo "ERROR: name and version are required" >&2
  usage
fi

NAME="${POSITIONAL[0]}"
NEW_VERSION="${POSITIONAL[1]}"

# Validate version format (must start with v or be a commit SHA)
if ! printf '%s' "$NEW_VERSION" | grep -qE '^(v[0-9]+\.[0-9]+|[0-9a-f]{7,40})'; then
  echo "ERROR: version '$NEW_VERSION' does not look like a valid tag (expected v1.2.3) or SHA" >&2
  exit 1
fi

RECIPE_FILE="$RECIPES_DIR/$NAME/recipe.yaml"

if [[ ! -f "$RECIPE_FILE" ]]; then
  echo "ERROR: recipe not found: $RECIPE_FILE" >&2
  exit 1
fi

CURRENT_VERSION=$(grep "^version:" "$RECIPE_FILE" | head -1 | sed 's/version: *//;s/"//g')

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] pin $NAME: $CURRENT_VERSION → $NEW_VERSION"
  echo "[DRY RUN]   would update: $RECIPE_FILE"
  if [[ "$BACKUP" == "true" ]]; then
    echo "[DRY RUN]   --backup is a no-op for pin (no artifacts to push)"
  fi
  exit 0
fi

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
  echo "[INFO] $NAME is already pinned to $NEW_VERSION — no change needed."
  exit 0
fi

# --backup is a no-op for pin (no remote artifacts)
if [[ "$BACKUP" == "true" ]]; then
  echo "[INFO] --backup flag set (no-op for pin — no artifacts to push)"
fi

# Create a backup of the recipe before modifying
cp "$RECIPE_FILE" "$RECIPE_FILE.bak"

# Update the version field using Python to avoid sed portability issues
python3 - "$RECIPE_FILE" "$NEW_VERSION" << 'PYEOF'
import sys, re

recipe_file = sys.argv[1]
new_version = sys.argv[2]

with open(recipe_file) as f:
    content = f.read()

updated = re.sub(
    r'^(version:\s*)"[^"]*"',
    lambda m: f'{m.group(1)}"{new_version}"',
    content,
    count=1,
    flags=re.MULTILINE
)

if updated == content:
    # Try without quotes
    updated = re.sub(
        r'^(version:\s*)\S+',
        lambda m: f'{m.group(1)}"{new_version}"',
        content,
        count=1,
        flags=re.MULTILINE
    )

with open(recipe_file, 'w') as f:
    f.write(updated)
PYEOF

# Verify the update
WRITTEN_VERSION=$(grep "^version:" "$RECIPE_FILE" | head -1 | sed 's/version: *//;s/"//g')
if [[ "$WRITTEN_VERSION" != "$NEW_VERSION" ]]; then
  echo "ERROR: version update failed — expected $NEW_VERSION but got $WRITTEN_VERSION" >&2
  mv "$RECIPE_FILE.bak" "$RECIPE_FILE"
  exit 1
fi

rm -f "$RECIPE_FILE.bak"
echo "[INFO] Pinned $NAME: $CURRENT_VERSION → $NEW_VERSION"
echo "[INFO] Updated: $RECIPE_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the change: git diff vendor/recipes/$NAME/recipe.yaml"
echo "  2. Fetch the new version: vendor/fetch.sh $NAME"
echo "  3. Build and push:        vendor/build.sh $NAME"
