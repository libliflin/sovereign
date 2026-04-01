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

# Harbor is always upgraded unconditionally — no chart_healthy skip — so that
# config changes (e.g. externalURL) land in the running release and trigger a
# ConfigMap checksum rollout of harbor-core. If install_chart's healthy-check
# fires, the corrected values never reach the cluster. (Cycle 27 fix)
log "harbor: deploying → harbor..."
helm upgrade --install harbor "${PLATFORM_DIR}/charts/harbor/" \
  --namespace harbor --create-namespace \
  --set "global.domain=${DOMAIN}" \
  --set "global.storageClass=${BLOCK_SC}" \
  --set "global.clusterIssuer=${CLUSTER_ISSUER}" \
  --set "harbor.expose.ingress.hosts.core=harbor.${DOMAIN}" \
  --set "harbor.externalURL=http://harbor.${DOMAIN}" \
  --set "harbor.persistence.persistentVolumeClaim.registry.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.database.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.redis.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.trivy.storageClass=${BLOCK_SC}" \
  --set "harbor.persistence.persistentVolumeClaim.jobservice.storageClass=${BLOCK_SC}" \
  --set "global.s3.endpoint=${OBJECT_ENDPOINT}" \
  --set "harbor.expose.tls.enabled=false" \
  --force-conflicts \
  --timeout "${TIMEOUT}" \
  --kube-context "${CONTEXT}" \
  2>&1 || { log "harbor: FAILED (continuing to next chart)"; }
log "harbor: ready ✓"


# ── Step 2a: Inject harbor hostname into kind node /etc/hosts ─────────────
# containerd on kind nodes uses the Docker bridge DNS (192.168.65.254) which
# has no record for harbor.${DOMAIN}. Inject the service ClusterIP so that
# image pulls from containerd resolve without touching CoreDNS or hostAliases.
# Use the harbor service ClusterIP (not the pod IP) so that kube-proxy handles
# the 80→8080 port translation; crane and containerd both connect on port 80.
if [[ "$DRY_RUN" != "true" ]] && chart_healthy harbor harbor; then
  HARBOR_IP=$(kubectl get svc harbor -n harbor --context "${CONTEXT}" \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null) || true
  if [[ -n "$HARBOR_IP" ]]; then
    while IFS= read -r node; do
      docker exec "$node" sh -c "
        grep -v 'harbor\.${DOMAIN}' /etc/hosts > /tmp/.hosts.tmp; cat /tmp/.hosts.tmp > /etc/hosts && echo '${HARBOR_IP} harbor.${DOMAIN}' >> /etc/hosts
        mkdir -p /etc/containerd/certs.d/harbor.${DOMAIN}
        printf 'server = \"http://harbor.${DOMAIN}\"\n\n[host.\"http://%s:80\"]\n  capabilities = [\"pull\", \"resolve\", \"push\"]\n' '${HARBOR_IP}' > /etc/containerd/certs.d/harbor.${DOMAIN}/hosts.toml
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

if [[ "$DRY_RUN" != "true" ]] && kubectl get pods -n harbor -l component=core --context "$CONTEXT" --no-headers 2>/dev/null | grep -q Running; then
  HARBOR_ADMIN_PASS=$(python3 -c "import yaml; d=yaml.safe_load(open('${PLATFORM_DIR}/charts/harbor/values.yaml')); print(d['harbor']['harborAdminPassword'])")

  # Start port-forward to Harbor (HTTP) — used by harbor_api() health polling
  kubectl port-forward svc/harbor -n harbor "${HARBOR_LOCAL_PORT}:80" \
    --context "${CONTEXT}" &>/dev/null &
  HARBOR_PF_PID=$!
  # Wait for port-forward to be ready (poll until Harbor responds, max 30s)
  for i in $(seq 1 15); do curl -s -o /dev/null "http://localhost:${HARBOR_LOCAL_PORT}/v2/" && break; sleep 2; done
  trap 'kill ${HARBOR_PF_PID} 2>/dev/null || true' EXIT

  # Install crane inside the kind control-plane node — the node already has
  # harbor.sovereign.local in its /etc/hosts and can reach Harbor directly on
  # the cluster network, so no host-side DNS or sudo is required.
  KIND_NODE="sovereign-test-control-plane"
  docker exec "${KIND_NODE}" sh -c \
    "test -x /usr/local/bin/crane || \
     (curl -fsSL https://github.com/google/go-containerregistry/releases/download/v0.20.2/go-containerregistry_Linux_x86_64.tar.gz \
       | tar xz -C /tmp crane && mv /tmp/crane /usr/local/bin/crane)"

  # Create bitnami project in Harbor (idempotent)
  harbor_api POST "projects" \
    -d '{"project_name":"bitnami","public":true}' 2>/dev/null || true

  # Seed each image — failures are non-fatal (image may already be in Harbor,
  # or upstream may be unreachable; the install step will surface the real error)
  for img_spec in "keycloak:${KEYCLOAK_TAG}" "postgresql:${PG_TAG}"; do
    # Check if already in Harbor via API
    repo="${img_spec%:*}"
    tag="${img_spec#*:}"
    if harbor_api GET "projects/bitnami/repositories/${repo}/artifacts/${tag}" &>/dev/null; then
      log "Harbor already has bitnami/${img_spec} ✓"
    else
      log "Seeding bitnami/${img_spec} into Harbor..."
      docker exec "${KIND_NODE}" crane copy --insecure \
        "docker.io/bitnamilegacy/${img_spec}" \
        "harbor.sovereign.local/bitnami/${img_spec}" && \
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
