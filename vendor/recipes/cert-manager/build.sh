#!/usr/bin/env bash
# vendor/recipes/cert-manager/build.sh
# Build cert-manager using ko — produces distroless OCI images.
# Called by vendor/build.sh from within the cloned source directory.
#
# Required env vars (set by vendor/build.sh):
#   KO_DOCKER_REPO            — Harbor staging repo for this service
#   IMAGE_TAG                 — <version>-<short_sha>-p<patch_count>
#   SOVEREIGN_SOURCE_SHA      — Full git SHA of the source commit
#   SOVEREIGN_PATCHES_APPLIED — Number of patches applied
#   SOVEREIGN_COMPILER_VERSION — Go version used for compilation
#   SOVEREIGN_BUILD_TIMESTAMP — RFC3339 build timestamp
set -euo pipefail

: "${KO_DOCKER_REPO:?KO_DOCKER_REPO must be set by vendor/build.sh}"
: "${IMAGE_TAG:?IMAGE_TAG must be set by vendor/build.sh}"
: "${SOVEREIGN_SOURCE_SHA:?SOVEREIGN_SOURCE_SHA must be set by vendor/build.sh}"
: "${SOVEREIGN_PATCHES_APPLIED:?SOVEREIGN_PATCHES_APPLIED must be set by vendor/build.sh}"
: "${SOVEREIGN_COMPILER_VERSION:?SOVEREIGN_COMPILER_VERSION must be set by vendor/build.sh}"
: "${SOVEREIGN_BUILD_TIMESTAMP:?SOVEREIGN_BUILD_TIMESTAMP must be set by vendor/build.sh}"

export KO_DOCKER_REPO
export GOFLAGS="-mod=mod"

echo "[cert-manager] Building controller, webhook, cainjector, acmesolver with ko..."

# ko build produces distroless images by default when --base-image is gcr.io/distroless/static.
# Builds all cert-manager binaries: controller, webhook, cainjector, acmesolver.
ko build \
  --base-image gcr.io/distroless/static \
  --tags "${IMAGE_TAG}" \
  --platform linux/amd64,linux/arm64 \
  --image-label "org.sovereign.source_sha=${SOVEREIGN_SOURCE_SHA}" \
  --image-label "org.sovereign.patches_applied=${SOVEREIGN_PATCHES_APPLIED}" \
  --image-label "org.sovereign.compiler_version=go${SOVEREIGN_COMPILER_VERSION}" \
  --image-label "org.sovereign.build_timestamp=${SOVEREIGN_BUILD_TIMESTAMP}" \
  ./cmd/controller \
  ./cmd/webhook \
  ./cmd/cainjector \
  ./cmd/acmesolver

echo "[cert-manager] Build complete: ${KO_DOCKER_REPO}:${IMAGE_TAG}"
