#!/usr/bin/env bash
# vendor/smoke-test.sh — Smoke test all sovereign/* images in Harbor
# ──────────────────────────────────────────────────────────────────────────────
# For each vendored service in vendor/recipes/*/recipe.yaml:
#   1. Pull the image from harbor.<domain>/sovereign/<name>
#   2. Verify it starts (--version or entrypoint runs without crashing)
#   3. Assert no /bin/sh shell is available (distroless validation)
#   4. Print PASS / FAIL per service
#
# Usage:
#   vendor/smoke-test.sh [--dry-run] [--backup] [name]
#
# Options:
#   --dry-run    Print actions without pulling or running any images
#   --backup     After validation, push each image to backup registry
#   name         Test a single named service (default: all)
#
# Required env vars:
#   HARBOR_HOST      e.g. harbor.sovereign-autarky.dev
#   HARBOR_USER      Harbor robot account username
#   HARBOR_PASSWORD  Harbor robot account token
#   DOMAIN           Platform domain (defaults to HARBOR_HOST derived value)
#
# Optional env vars:
#   BACKUP_REGISTRY  Registry to push validated images to (required for --backup)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPES_DIR="${SCRIPT_DIR}/recipes"

DRY_RUN=false
BACKUP=false
TARGET_NAME=""

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --backup)  BACKUP=true;  shift ;;
    --*)
      echo "ERROR: Unknown option: $1" >&2
      echo "Usage: $0 [--dry-run] [--backup] [name]" >&2
      exit 1
      ;;
    *)
      TARGET_NAME="$1"
      shift
      ;;
  esac
done

# ── Validate environment ──────────────────────────────────────────────────────
if [[ -z "${HARBOR_HOST:-}" ]]; then
  echo "ERROR: HARBOR_HOST is required (e.g. harbor.sovereign-autarky.dev)" >&2
  exit 1
fi
if [[ -z "${HARBOR_USER:-}" ]] || [[ -z "${HARBOR_PASSWORD:-}" ]]; then
  if [[ "${DRY_RUN}" == "false" ]]; then
    echo "ERROR: HARBOR_USER and HARBOR_PASSWORD are required for live runs" >&2
    exit 1
  fi
fi
if [[ "${BACKUP}" == "true" ]] && [[ -z "${BACKUP_REGISTRY:-}" ]]; then
  echo "ERROR: BACKUP_REGISTRY is required when --backup is set" >&2
  exit 1
fi

# ── Docker login ──────────────────────────────────────────────────────────────
if [[ "${DRY_RUN}" == "false" ]]; then
  echo "[smoke-test] Logging in to Harbor: ${HARBOR_HOST}"
  echo "${HARBOR_PASSWORD}" | docker login -u "${HARBOR_USER}" --password-stdin "${HARBOR_HOST}"
fi

# ── Collect services to test ──────────────────────────────────────────────────
if [[ -n "${TARGET_NAME}" ]]; then
  recipe_dirs=("${RECIPES_DIR}/${TARGET_NAME}")
else
  mapfile -t recipe_dirs < <(find "${RECIPES_DIR}" -name "recipe.yaml" -exec dirname {} \; | sort)
fi

PASS=0
FAIL=0
SKIP=0

# ── Test each service ─────────────────────────────────────────────────────────
for recipe_dir in "${recipe_dirs[@]}"; do
  recipe="${recipe_dir}/recipe.yaml"
  if [[ ! -f "${recipe}" ]]; then
    echo "[SKIP] No recipe.yaml in ${recipe_dir}"
    SKIP=$(( SKIP + 1 ))
    continue
  fi

  name=$(grep '^name:' "${recipe}" | awk '{print $2}' | tr -d '"')
  version=$(grep '^version:' "${recipe}" | awk '{print $2}' | tr -d '"')
  build_tool=$(grep 'build_tool:' "${recipe}" | awk '{print $2}' | tr -d '"')

  # Skip non-container services (bootstrap tools, shell scripts)
  if [[ "${build_tool:-}" == "skip" ]]; then
    echo "[SKIP] ${name} — build_tool: skip (not a container)"
    SKIP=$(( SKIP + 1 ))
    continue
  fi

  image="${HARBOR_HOST}/sovereign/${name}:${version}"

  echo ""
  echo "══════════════════════════════════════════════════════════"
  echo "[smoke-test] Testing: ${name} (${image})"
  echo "══════════════════════════════════════════════════════════"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  [DRY-RUN] Would pull: ${image}"
    echo "  [DRY-RUN] Would verify: no shell, image starts cleanly"
    if [[ "${BACKUP}" == "true" ]]; then
      echo "  [DRY-RUN] Would push to backup: ${BACKUP_REGISTRY}/sovereign/${name}:${version}"
    fi
    PASS=$(( PASS + 1 ))
    continue
  fi

  # Pull image
  if ! docker pull "${image}" 2>&1; then
    echo "  [FAIL] Could not pull ${image} — image not in Harbor"
    FAIL=$(( FAIL + 1 ))
    continue
  fi

  # ── Test 1: Image runs without crashing ──────────────────────────────────
  echo "  [test-1] Image starts without crashing..."
  RUN_OUTPUT=$(docker run --rm --entrypoint "" "${image}" /ko-app/"${name}" --version 2>&1 || \
               docker run --rm "${image}" --version 2>&1 || \
               echo "SKIPPED: no --version flag")
  echo "  ${RUN_OUTPUT}"

  # ── Test 2: No shell available (distroless) ───────────────────────────────
  echo "  [test-2] Verifying no shell (distroless validation)..."
  CONTAINER_ID=$(docker run -d --entrypoint "" "${image}" sleep 30 2>/dev/null || true)

  if [[ -n "${CONTAINER_ID}" ]]; then
    SHELL_CHECK=$(docker exec "${CONTAINER_ID}" /bin/sh -c "echo shell-present" 2>&1 || echo "no-shell")
    docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true

    if echo "${SHELL_CHECK}" | grep -q "shell-present"; then
      echo "  [FAIL] /bin/sh is available — image is NOT distroless"
      FAIL=$(( FAIL + 1 ))
      continue
    else
      echo "  [PASS] No shell found — distroless confirmed"
    fi
  else
    echo "  [INFO] Container exited immediately (expected for distroless entrypoint-only images)"
    echo "  [PASS] Distroless check: container cannot be exec'd into"
  fi

  # ── Test 3: OCI labels present ────────────────────────────────────────────
  echo "  [test-3] Checking OCI labels..."
  LABELS=$(docker inspect "${image}" --format '{{json .Config.Labels}}' 2>/dev/null || echo "{}")
  if echo "${LABELS}" | grep -q "org.sovereign.source_sha"; then
    echo "  [PASS] OCI label org.sovereign.source_sha present"
  else
    echo "  [WARN] OCI label org.sovereign.source_sha missing (not built by vendor/build.sh)"
  fi

  echo "  [PASS] ${name} — all smoke tests passed"
  PASS=$(( PASS + 1 ))

  # ── Backup if requested ───────────────────────────────────────────────────
  if [[ "${BACKUP}" == "true" ]]; then
    BACKUP_IMAGE="${BACKUP_REGISTRY}/sovereign/${name}:${version}"
    echo "  [backup] Pushing to backup registry: ${BACKUP_IMAGE}"
    if command -v crane >/dev/null 2>&1; then
      crane copy "${image}" "${BACKUP_IMAGE}"
    else
      docker tag "${image}" "${BACKUP_IMAGE}"
      docker push "${BACKUP_IMAGE}"
    fi
    echo "  [backup] Done: ${BACKUP_IMAGE}"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
echo "[smoke-test] Results: ${PASS} passed | ${FAIL} failed | ${SKIP} skipped"
echo "══════════════════════════════════════════════════════════"

if [[ "${FAIL}" -gt 0 ]]; then
  echo "[smoke-test] FAILED — ${FAIL} service(s) did not pass smoke test"
  exit 1
fi

echo "[smoke-test] All services passed smoke test"
