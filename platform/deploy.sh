#!/usr/bin/env bash
# platform/deploy.sh
#
# Deploys the Sovereign Platform in dependency order.
# Idempotent — safe to run repeatedly. Each step checks if its chart is
# already healthy before installing. 3-minute timeout per chart.
#
# Usage:
#   ./platform/deploy.sh --cluster-values cluster-values.yaml
#   ./platform/deploy.sh --cluster-values cluster-values.yaml --dry-run
#
# The autarky bootstrap window closes after Harbor is running (step 2).
# Steps 0-1 may pull images from upstream; after step 2, Harbor serves all images.

set -euo pipefail

CLUSTER_VALUES=""
DRY_RUN=false
PLATFORM_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${PLATFORM_DIR}/.." && pwd)"
CONTRACT_VALIDATE="${REPO_ROOT}/contract/validate.py"
CONTEXT="kind-sovereign-test"
TIMEOUT="3m0s"

usage() {
  echo "Usage: $0 --cluster-values <path> [--dry-run]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-values) CLUSTER_VALUES="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true;        shift   ;;
    --help)           usage ;;
    *) echo "Unknown flag: $1"; usage ;;
  esac
done

[[ -z "$CLUSTER_VALUES" ]] && usage
[[ ! -f "$CLUSTER_VALUES" ]] && { echo "ERROR: $CLUSTER_VALUES not found"; exit 1; }

log() { echo "==> $*"; }

# ── 0. Validate contract ─────────────────────────────────────────────────
log "Validating cluster contract..."
python3 "${CONTRACT_VALIDATE}" "${CLUSTER_VALUES}"

DOMAIN=$(python3 -c "import yaml; d=yaml.safe_load(open('${CLUSTER_VALUES}')); print(d['runtime']['domain'])")
BLOCK_SC=$(python3 -c "import yaml; d=yaml.safe_load(open('${CLUSTER_VALUES}')); print(d['storage']['block']['storageClassName'])")
OBJECT_ENDPOINT=$(python3 -c "import yaml; d=yaml.safe_load(open('${CLUSTER_VALUES}')); print(d['storage']['object']['endpoint'])")
CLUSTER_ISSUER=$(python3 -c "import yaml; d=yaml.safe_load(open('${CLUSTER_VALUES}')); print(d['pki']['clusterIssuer'])")

log "Domain: ${DOMAIN}  SC: ${BLOCK_SC}  Issuer: ${CLUSTER_ISSUER}"

# ── Helpers ───────────────────────────────────────────────────────────────

chart_healthy() {
  # Returns 0 if the helm release exists and all pods in the namespace are Running/Completed.
  local name="$1" namespace="$2"
  helm status "$name" -n "$namespace" --kube-context "$CONTEXT" &>/dev/null || return 1
  local not_ready
  not_ready=$(kubectl get pods -n "$namespace" --context "$CONTEXT" --no-headers 2>/dev/null \
    | grep -v -E 'Running|Completed' | wc -l | tr -d ' ')
  [[ "$not_ready" == "0" ]]
}

install_chart() {
  local name="$1" namespace="$2"
  shift 2
  local extra_args=("$@")

  # Skip if already healthy
  if chart_healthy "$name" "$namespace"; then
    log "${name}: healthy ✓ (skipped)"
    return 0
  fi

  log "${name}: deploying → ${namespace}..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] helm upgrade --install ${name} ${PLATFORM_DIR}/charts/${name}/ -n ${namespace}"
    return 0
  fi

  helm upgrade --install "${name}" "${PLATFORM_DIR}/charts/${name}/" \
    --namespace "${namespace}" --create-namespace \
    --set "global.domain=${DOMAIN}" \
    --set "global.storageClass=${BLOCK_SC}" \
    --set "global.clusterIssuer=${CLUSTER_ISSUER}" \
    --timeout "${TIMEOUT}" \
    --kube-context "${CONTEXT}" \
    ${extra_args[@]+"${extra_args[@]}"} \
    2>&1 || {
      log "${name}: FAILED (continuing to next chart)"
      return 0  # Don't abort — report the failure and keep going
    }

  log "${name}: ready ✓"
}

ensure_namespace() {
  kubectl create namespace "$1" --dry-run=client -o yaml \
    | kubectl apply -f - --context "$CONTEXT" &>/dev/null
}

ensure_secret() {
  local name="$1" namespace="$2"
  shift 2
  if ! kubectl get secret "$name" -n "$namespace" --context "$CONTEXT" &>/dev/null; then
    kubectl create secret generic "$name" -n "$namespace" --context "$CONTEXT" "$@"
    log "Created secret ${namespace}/${name}"
  fi
}

# ── Step 1: OpenBao (secrets store) ───────────────────────────────────────

install_chart openbao openbao

# ── Step 2: Harbor (internal registry — closes autarky bootstrap window) ──

install_chart harbor harbor \
  --set "harbor.expose.ingress.hosts.core=harbor.${DOMAIN}" \
  --set "harbor.externalURL=http://harbor.${DOMAIN}:8080" \
  --set "harbor.persistence.persistentVolumeClaim.registry.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.database.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.redis.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.trivy.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.jobservice.storageClass=${BLOCK_SC}" \
  --set "global.s3.endpoint=${OBJECT_ENDPOINT}" \
  --set "harbor.expose.tls.enabled=false"

# Unstick harbor-core rolling update and restart with HTTP externalURL.
# The force-upgrade block previously triggered a second helm upgrade every cycle,
# causing harbor-core to enter a perpetual rolling update (new pod Pending, old
# pod Running with stale HTTPS config). Remove it; install_chart already passes
# externalURL=http://... and tls.enabled=false. These three commands cancel any
# stuck rolling update, lock in Recreate strategy, and do a single clean restart.
if [[ "$DRY_RUN" != "true" ]]; then
  kubectl rollout undo deployment/harbor-core -n harbor --context "$CONTEXT" 2>/dev/null || true
  kubectl patch deployment harbor-core -n harbor --context "$CONTEXT" \
    --type=merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}' 2>/dev/null || true
  kubectl rollout restart deployment/harbor-core -n harbor --context "$CONTEXT" 2>/dev/null || true
  kubectl rollout status deployment/harbor-core -n harbor --context "$CONTEXT" --timeout=180s 2>/dev/null || true
fi

# ── Step 2a: Inject harbor hostname into kind node /etc/hosts ─────────────
# containerd on kind nodes uses the Docker bridge DNS (192.168.65.254) which
# has no record for harbor.${DOMAIN}. Inject the pod IP directly so that
# image pulls from containerd resolve without touching CoreDNS or hostAliases.
# Use the harbor-nginx pod IP (not the ClusterIP) because Cilium kube-proxy-free
# mode does not intercept ClusterIP traffic from the host network namespace.
if [[ "$DRY_RUN" != "true" ]] && chart_healthy harbor harbor; then
  HARBOR_IP=$(kubectl get pod -n harbor -l component=nginx --context "$CONTEXT" \
    -o jsonpath='{.items[0].status.podIP}' 2>/dev/null) || true
  if [[ -n "$HARBOR_IP" ]]; then
    while IFS= read -r node; do
      docker exec "$node" sh -c "
        sed -i '/harbor\.${DOMAIN}/d' /etc/hosts && echo '${HARBOR_IP} harbor.${DOMAIN}' >> /etc/hosts
        mkdir -p /etc/containerd/certs.d/harbor.${DOMAIN}
        printf 'server = \"http://harbor.${DOMAIN}\"\n\n[host.\"http://%s:8080\"]\n  capabilities = [\"pull\", \"resolve\", \"push\"]\n' '${HARBOR_IP}' > /etc/containerd/certs.d/harbor.${DOMAIN}/hosts.toml
        if ! grep -q 'config_path.*certs' /etc/containerd/config.toml 2>/dev/null; then
          if grep -q '\[plugins\.\"io\.containerd\.grpc\.v1\.cri\"\.registry\]' /etc/containerd/config.toml 2>/dev/null; then
            sed -i '/\[plugins\.\"io\.containerd\.grpc\.v1\.cri\"\.registry\]/a\\  config_path = \"/etc/containerd/certs.d\"' /etc/containerd/config.toml
          else
            printf '\n[plugins.\"io.containerd.grpc.v1.cri\".registry]\n  config_path = \"/etc/containerd/certs.d\"\n' >> /etc/containerd/config.toml
          fi
          kill -HUP \$(pgrep -x containerd) 2>/dev/null || true
          sleep 1
        fi
      "
    done < <(kind get nodes --name sovereign-test 2>/dev/null)
    log "Injected harbor.${DOMAIN} → ${HARBOR_IP} into kind node /etc/hosts and containerd certs.d"
  else
    log "WARN: Could not resolve harbor ClusterIP — skipping hosts injection"
  fi
fi

# ── Step 2b: Seed Harbor with upstream images (only during bootstrap) ─────
# After Harbor is healthy, mirror images needed by later charts.
# Uses kubectl port-forward (localhost:5000 → harbor:80) because the host
# docker daemon cannot route to Harbor's ClusterIP or pod IP directly.
# Harbor listens on HTTP/8080 (no TLS configured) — docker treats localhost
# as an insecure registry automatically.

KEYCLOAK_TAG="24.0.5-debian-12-r0"
PG_TAG="16.3.0-debian-12-r14"
HARBOR_LOCAL_PORT="5000"

harbor_api() {
  # Run Harbor API call via port-forward on localhost
  local method="$1"; shift
  curl -sf -u "admin:${HARBOR_ADMIN_PASS}" \
    -X "${method}" "http://localhost:${HARBOR_LOCAL_PORT}/api/v2.0/$1" \
    -H "Content-Type: application/json" \
    "${@:2}" 2>/dev/null
}

if [[ "$DRY_RUN" != "true" ]] && chart_healthy harbor harbor; then
  HARBOR_ADMIN_PASS=$(python3 -c "import yaml; d=yaml.safe_load(open('${PLATFORM_DIR}/charts/harbor/values.yaml')); print(d['harbor']['harborAdminPassword'])")

  # Start port-forward to Harbor (HTTP)
  kubectl port-forward svc/harbor -n harbor "${HARBOR_LOCAL_PORT}:80" \
    --context "${CONTEXT}" &>/dev/null &
  HARBOR_PF_PID=$!
  # Give port-forward a moment to establish
  sleep 3
  trap 'kill ${HARBOR_PF_PID} 2>/dev/null || true' EXIT

  # Create bitnami project in Harbor (idempotent)
  harbor_api POST "projects" \
    -d '{"project_name":"bitnami","public":true}' 2>/dev/null || true

  # Seed each image — failures are non-fatal (image may already be in Harbor,
  # or upstream may be unreachable; the install step will surface the real error)
  for img_spec in "keycloak:${KEYCLOAK_TAG}" "postgresql:${PG_TAG}"; do
    local_tag="localhost:${HARBOR_LOCAL_PORT}/bitnami/${img_spec}"
    # Check if already in Harbor via API
    repo="${img_spec%:*}"
    tag="${img_spec#*:}"
    if harbor_api GET "projects/bitnami/repositories/${repo}/artifacts/${tag}" &>/dev/null; then
      log "Harbor already has bitnami/${img_spec} ✓"
    else
      log "Seeding bitnami/${img_spec} into Harbor..."
      docker pull "bitnamilegacy/${img_spec}" 2>&1 && \
      docker tag "bitnamilegacy/${img_spec}" "${local_tag}" && \
      docker push "${local_tag}" 2>&1 && \
      log "Seeded bitnami/${img_spec} ✓" || \
      log "WARN: Failed to seed bitnami/${img_spec} (will retry next cycle)"
    fi
  done

  kill "${HARBOR_PF_PID}" 2>/dev/null || true
  trap - EXIT
fi

# ── Step 3: Keycloak (identity / SSO) ────────────────────────────────────

# Pre-conditions: namespace, secrets (idempotent)
ensure_namespace keycloak

# Detect orphaned state: PVC exists but password secret is gone
if kubectl get pvc data-keycloak-postgresql-0 -n keycloak --context "$CONTEXT" &>/dev/null && \
   ! kubectl get secret keycloak-db-secret -n keycloak --context "$CONTEXT" &>/dev/null; then
  log "Orphaned keycloak PVC — clearing stale state"
  helm uninstall keycloak -n keycloak --kube-context "$CONTEXT" --ignore-not-found 2>/dev/null || true
  kubectl delete pvc data-keycloak-postgresql-0 -n keycloak --context "$CONTEXT" --ignore-not-found
fi

ensure_secret keycloak-admin-secret keycloak \
  --from-literal=admin-password="$(openssl rand -base64 24)"

if ! kubectl get secret keycloak-db-secret -n keycloak --context "$CONTEXT" &>/dev/null; then
  DB_PASS="$(openssl rand -base64 24)"
  ensure_secret keycloak-db-secret keycloak \
    --from-literal=postgres-password="${DB_PASS}" \
    --from-literal=password="${DB_PASS}"
fi

# Read existing password for upgrade compatibility
KEYCLOAK_EXTRA=()
if kubectl get secret keycloak-db-secret -n keycloak --context "$CONTEXT" &>/dev/null; then
  PG_PASS=$(kubectl get secret keycloak-db-secret -n keycloak --context "$CONTEXT" \
    -o jsonpath="{.data.password}" | base64 -d)
  KEYCLOAK_EXTRA=(
    --set "global.postgresql.auth.password=${PG_PASS}"
  )
fi

install_chart keycloak keycloak \
  --set "global.imageRegistry=harbor.${DOMAIN}" \
  --set "keycloak.image.tag=${KEYCLOAK_TAG}" \
  --set "keycloak.postgresql.image.tag=${PG_TAG}" \
  ${KEYCLOAK_EXTRA[@]+"${KEYCLOAK_EXTRA[@]}"}

# ── Step 4: GitLab + ArgoCD ──────────────────────────────────────────────

install_chart gitlab gitlab
install_chart argocd argocd

# ── Step 5: Observability ────────────────────────────────────────────────

install_chart prometheus-stack monitoring
install_chart loki monitoring
install_chart tempo monitoring
install_chart thanos monitoring

# ── Step 6: Security mesh ────────────────────────────────────────────────

install_chart istio istio-system
install_chart opa-gatekeeper gatekeeper-system
install_chart falco falco
install_chart trivy-operator trivy-system

# ── Step 7: Developer experience ─────────────────────────────────────────

install_chart backstage backstage
install_chart code-server code-server
install_chart sonarqube sonarqube
install_chart reportportal reportportal

log ""
log "Deploy pass complete."
