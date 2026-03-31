#!/usr/bin/env bash
# platform/deploy.sh
#
# Deploys the Sovereign Platform onto a conformant cluster.
# Reads cluster-values.yaml, validates against the contract, then
# helm installs each chart in dependency order.
#
# Usage:
#   ./platform/deploy.sh --cluster-values cluster-values.yaml
#   ./platform/deploy.sh --cluster-values cluster-values.yaml --dry-run
#   ./platform/deploy.sh --cluster-values cluster-values.yaml --only cert-manager
#
# The platform never calls out to external services after step 4 (Harbor).
# Steps 1-3 may pull images from upstream registries — this is the bootstrap window.
# After step 4, all images are in Harbor and the cluster is self-sufficient.

set -euo pipefail

CLUSTER_VALUES=""
CHART_DIR=""
NAMESPACE=""
DRY_RUN=false
ONLY=""
PLATFORM_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTRACT_VALIDATE="$(cd "${PLATFORM_DIR}/.." && pwd)/contract/validate.py"

usage() {
  echo "Usage: $0 --cluster-values <path> [--dry-run] [--only <chart>]"
  echo "       $0 --chart-dir DIR --namespace NS [--dry-run]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-values) CLUSTER_VALUES="$2"; shift 2 ;;
    --chart-dir)      CHART_DIR="$2";      shift 2 ;;
    --namespace)      NAMESPACE="$2";      shift 2 ;;
    --dry-run)        DRY_RUN=true;        shift   ;;
    --only)           ONLY="$2";           shift 2 ;;
    --help)           usage ;;
    *) echo "Unknown flag: $1"; usage ;;
  esac
done

# Single-chart deployment mode: --chart-dir DIR --namespace NS
if [[ -n "$CHART_DIR" || -n "$NAMESPACE" ]]; then
  [[ -z "$CHART_DIR" || -z "$NAMESPACE" ]] && { echo "ERROR: --chart-dir and --namespace are both required"; usage; }
  log "Deploying chart: ${CHART_DIR} to namespace: ${NAMESPACE}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] helm upgrade --install $(basename "${CHART_DIR}") ${CHART_DIR} --namespace ${NAMESPACE} --create-namespace"
  else
    helm upgrade --install "$(basename "${CHART_DIR}")" "${CHART_DIR}" \
      --namespace "${NAMESPACE}" --create-namespace \
      --wait --timeout 5m
  fi
  exit 0
fi

[[ -z "$CLUSTER_VALUES" ]] && usage
[[ ! -f "$CLUSTER_VALUES" ]] && { echo "ERROR: $CLUSTER_VALUES not found"; exit 1; }

log() { echo "==> $*"; }
dry() { [[ "$DRY_RUN" == "true" ]] && echo "[dry-run] $*" || true; }

# ── 0. Validate contract ─────────────────────────────────────────────────
log "Validating cluster contract..."
python3 "${CONTRACT_VALIDATE}" "${CLUSTER_VALUES}"

# Read values
DOMAIN=$(python3 -c "import yaml,sys; d=yaml.safe_load(open('${CLUSTER_VALUES}')); print(d['runtime']['domain'])")
BLOCK_SC=$(python3 -c "import yaml,sys; d=yaml.safe_load(open('${CLUSTER_VALUES}')); print(d['storage']['block']['storageClassName'])")
OBJECT_ENDPOINT=$(python3 -c "import yaml,sys; d=yaml.safe_load(open('${CLUSTER_VALUES}')); print(d['storage']['object']['endpoint'])")
CLUSTER_ISSUER=$(python3 -c "import yaml,sys; d=yaml.safe_load(open('${CLUSTER_VALUES}')); print(d['pki']['clusterIssuer'])")

log "Domain:         ${DOMAIN}"
log "StorageClass:   ${BLOCK_SC}"
log "Object storage: ${OBJECT_ENDPOINT}"
log "ClusterIssuer:  ${CLUSTER_ISSUER}"
log ""

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN — no changes will be made to the cluster"
fi

# ── Helper: helm install one chart ───────────────────────────────────────
install_chart() {
  local name="$1"
  local namespace="$2"
  shift 2
  local extra_args=("$@")

  if [[ -n "$ONLY" && "$name" != "$ONLY" ]]; then
    return 0
  fi

  log "Installing ${name} → namespace/${namespace}..."

  if [[ "$DRY_RUN" == "true" ]]; then
    dry "helm upgrade --install ${name} ${PLATFORM_DIR}/charts/${name}/ --namespace ${namespace} --create-namespace ${extra_args[*]:-}"
    return 0
  fi

  helm upgrade --install "${name}" "${PLATFORM_DIR}/charts/${name}/" \
    --namespace "${namespace}" --create-namespace \
    --set "global.domain=${DOMAIN}" \
    --set "global.storageClass=${BLOCK_SC}" \
    --set "global.clusterIssuer=${CLUSTER_ISSUER}" \
    --wait --timeout 5m \
    ${extra_args[@]+"${extra_args[@]}"}

  log "${name} ready ✓"
}

# ── Deployment order ─────────────────────────────────────────────────────
#
# Rule: each chart must be smoke-tested before the next is installed.
# The autarky bootstrap window closes after Harbor is running (step 4).
# After that, all images come from Harbor only.
# Gate: pods Running. Smoke-test assertions are a future story (E2 backlog).

# Step 1: OpenBao (runtime secrets store)
install_chart openbao openbao

# Step 4: Harbor (internal registry)
# After this step: push all images to Harbor, then close the bootstrap window.

# Pre-flight: delete harbor StatefulSets with immutable volumeClaimTemplates if they exist.
# Required when storageClass changes between runs (immutable field; helm upgrade is rejected).
for sts in harbor-database harbor-redis harbor-trivy; do
  if kubectl get statefulset "${sts}" -n harbor &>/dev/null; then
    kubectl delete statefulset "${sts}" -n harbor --wait=false
    kubectl delete pvc -n harbor database-data-harbor-database-0 data-harbor-redis-0 data-harbor-trivy-0 --ignore-not-found
  fi
done

install_chart harbor harbor \
  --set "harbor.expose.ingress.hosts.core=harbor.${DOMAIN}" \
  --set "harbor.externalURL=https://harbor.${DOMAIN}" \
  --set "harbor.persistence.persistentVolumeClaim.registry.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.database.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.redis.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.trivy.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.jobservice.storageClass=${BLOCK_SC}" \
  --set "harbor.registry.credentials.htpasswd=" \
  --set "global.s3.endpoint=${OBJECT_ENDPOINT}"

# ── Seed Harbor with Keycloak and PostgreSQL images ──────────────────────
# bitnami prunes old tags — verify pinned tags exist before mirroring.
KEYCLOAK_TAG="24.0.5-debian-12-r0"
PG_TAG="16.3.0-debian-12-r14"

if [[ "$DRY_RUN" != "true" ]]; then
  HARBOR_ADMIN_PASS=$(python3 -c "import yaml; d=yaml.safe_load(open('${PLATFORM_DIR}/charts/harbor/values.yaml')); print(d['harbor']['harborAdminPassword'])")

  if ! skopeo inspect "docker://docker.io/bitnami/keycloak:${KEYCLOAK_TAG}" >/dev/null 2>&1; then
    log "  bitnami/keycloak:${KEYCLOAK_TAG} not found — resolving latest debian-12 tag..."
    KEYCLOAK_TAG=$(skopeo list-tags "docker://docker.io/bitnami/keycloak" \
      | python3 -c "import sys,json; tags=json.load(sys.stdin)['Tags']; print(sorted([t for t in tags if 'debian-12' in t])[-1])")
    log "  Resolved keycloak tag: ${KEYCLOAK_TAG}"
  fi

  if ! skopeo inspect "docker://docker.io/bitnami/postgresql:${PG_TAG}" >/dev/null 2>&1; then
    log "  bitnami/postgresql:${PG_TAG} not found — resolving latest debian-12 tag..."
    PG_TAG=$(skopeo list-tags "docker://docker.io/bitnami/postgresql" \
      | python3 -c "import sys,json; tags=json.load(sys.stdin)['Tags']; print(sorted([t for t in tags if 'debian-12' in t])[-1])")
    log "  Resolved postgresql tag: ${PG_TAG}"
  fi

  curl -sf -u "admin:${HARBOR_ADMIN_PASS}" --insecure \
    -X POST "https://harbor.${DOMAIN}/api/v2.0/projects" \
    -H "Content-Type: application/json" \
    -d '{"project_name":"bitnami","public":false}' || true

  log "Seeding Harbor with bitnami/keycloak:${KEYCLOAK_TAG} and bitnami/postgresql:${PG_TAG}..."
  skopeo copy \
    --dest-creds "admin:${HARBOR_ADMIN_PASS}" \
    --dest-tls-verify=false \
    "docker://docker.io/bitnami/keycloak:${KEYCLOAK_TAG}" \
    "docker://harbor.${DOMAIN}/bitnami/keycloak:${KEYCLOAK_TAG}"

  skopeo copy \
    --dest-creds "admin:${HARBOR_ADMIN_PASS}" \
    --dest-tls-verify=false \
    "docker://docker.io/bitnami/postgresql:${PG_TAG}" \
    "docker://harbor.${DOMAIN}/bitnami/postgresql:${PG_TAG}"

  log "Harbor seeding complete ✓"
fi

# Step 5: Keycloak (identity — SSO for all services)
install_chart keycloak keycloak \
  --set "global.imageRegistry=harbor.${DOMAIN}" \
  --set "keycloak.image.tag=${KEYCLOAK_TAG}" \
  --set "keycloak.postgresql.image.tag=${PG_TAG}"

# Step 6: GitLab (SCM + CI)
install_chart gitlab gitlab

# Step 7: ArgoCD (GitOps — takes over managing upgrades from here)
install_chart argocd argocd

# Step 8: Observability stack
install_chart prometheus-stack monitoring
install_chart loki monitoring
install_chart tempo monitoring
install_chart thanos monitoring

# Step 9: Security
install_chart istio istio-system
install_chart opa-gatekeeper gatekeeper-system
install_chart falco falco
install_chart trivy-operator trivy-system

# Step 10: Developer experience
install_chart backstage backstage
install_chart code-server code-server
install_chart sonarqube sonarqube
install_chart reportportal reportportal

log ""
log "Platform deployment complete."
log "Access the platform at https://gitlab.${DOMAIN}"
