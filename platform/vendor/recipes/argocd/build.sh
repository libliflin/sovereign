#!/usr/bin/env bash
# vendor/recipes/argocd/build.sh
# Build ArgoCD using ko — produces distroless OCI images for all server components.
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

echo "[argocd] Building argocd server components with ko..."

# Build all ArgoCD server binaries.
# argocd-server, argocd-application-controller, argocd-repo-server, and argocd-dex
# are the core runtime components deployed in-cluster.
ko build \
  --base-image gcr.io/distroless/static \
  --tags "${IMAGE_TAG}" \
  --platform linux/amd64,linux/arm64 \
  --image-label "org.sovereign.source_sha=${SOVEREIGN_SOURCE_SHA}" \
  --image-label "org.sovereign.patches_applied=${SOVEREIGN_PATCHES_APPLIED}" \
  --image-label "org.sovereign.compiler_version=go${SOVEREIGN_COMPILER_VERSION}" \
  --image-label "org.sovereign.build_timestamp=${SOVEREIGN_BUILD_TIMESTAMP}" \
  ./cmd/argocd-server \
  ./cmd/argocd-application-controller \
  ./cmd/argocd-repo-server \
  ./cmd/argocd-applicationset-controller \
  ./cmd/argocd-notifications

echo "[argocd] Build complete: ${KO_DOCKER_REPO}:${IMAGE_TAG}"
