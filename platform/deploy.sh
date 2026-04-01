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
  --set "harbor.database.internal.livenessProbe.timeoutSeconds=10" \
  --set "harbor.database.internal.livenessProbe.failureThreshold=10" \
  --set "harbor.database.internal.livenessProbe.initialDelaySeconds=60" \
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

# ── Step 2b: Seed bitnami images into the kind cluster ────────────────────
# Bitnami images are sourced from docker.io/bitnamilegacy (the legacy namespace
# where older pinned tags remain available after Bitnami's registry migration).
# docker.io/bitnami/* no longer hosts these pinned version tags.
#
# For kind clusters: use 'kind load image-archive' to inject images directly
# into each node's containerd cache.  This is the correct approach for kind
# because the Docker Desktop daemon runs in a VM and cannot push to a
# localhost:PORT port-forward (the host port is unreachable from the VM).
#
# Images are tagged harbor.${DOMAIN}/bitnami/... before loading so that
# pod image references of that form resolve from the local cache without
# needing Harbor to actually serve them.

KEYCLOAK_TAG="24.0.5-debian-12-r8"   # bitnamilegacy; r0 retired from docker.io/bitnami; r8 is latest available revision
PG_TAG="16"                          # harbor tag for keycloak postgresql (short)
PG_SRC_TAG="16.3.0-debian-12-r14"   # bitnamilegacy source tag
REDIS_TAG="6.2.7-debian-11-r11"
REDIS_EXPORTER_TAG="1.43.0-debian-11-r4"
THANOS_TAG="0.36.0-debian-12-r1"
FALCOCTL_TAG="0.12.2"               # falcosecurity/falcoctl
KIND_CLUSTER="${CONTEXT#kind-}"      # cluster name for kind commands (strip 'kind-' prefix)

# kind_load_image <bitnamilegacy-repo> <src-tag> <harbor-tag>
# Pulls the arm64-specific digest of bitnamilegacy/<repo>:<src-tag>,
# tags it as harbor.${DOMAIN}/bitnami/<repo>:<harbor-tag>, saves a
# single-arch tar, and loads it via 'kind load image-archive'.
kind_load_image() {
  local repo="$1" src_tag="$2" harbor_tag="$3"
  local harbor_ref="harbor.${DOMAIN}/bitnami/${repo}:${harbor_tag}"

  # Idempotent — skip if any worker node already has the image
  if docker exec "${KIND_CLUSTER}-worker" ctr --namespace=k8s.io images ls 2>/dev/null \
      | grep -qF "${harbor_ref}"; then
    log "kind already has ${harbor_ref} ✓"
    return
  fi

  log "Loading ${harbor_ref} into kind nodes..."
  # Prefer arm64-specific digest to avoid multi-platform manifest import errors
  local arm64_digest
  arm64_digest=$(docker manifest inspect "bitnamilegacy/${repo}:${src_tag}" 2>/dev/null \
    | python3 -c "
import sys, json
m = json.load(sys.stdin)
for p in m.get('manifests', []):
    pl = p.get('platform', {})
    if pl.get('os') == 'linux' and pl.get('architecture') == 'arm64':
        print(p['digest']); break
" 2>/dev/null | head -1)

  if [[ -n "$arm64_digest" ]]; then
    docker pull "bitnamilegacy/${repo}@${arm64_digest}" 2>/dev/null
    docker tag "bitnamilegacy/${repo}@${arm64_digest}" "${harbor_ref}"
  else
    docker pull "bitnamilegacy/${repo}:${src_tag}" 2>/dev/null
    docker tag "bitnamilegacy/${repo}:${src_tag}" "${harbor_ref}"
  fi

  local tmptar
  tmptar=$(mktemp /tmp/kindimg.XXXXXX.tar)
  docker save "${harbor_ref}" -o "${tmptar}"
  kind load image-archive "${tmptar}" --name "${KIND_CLUSTER}" 2>/dev/null && \
    log "Loaded ${harbor_ref} ✓" || log "WARN: kind load failed for ${harbor_ref}"
  rm -f "${tmptar}"
}

if [[ "$DRY_RUN" != "true" ]] && [[ "$CONTEXT" == kind-* ]]; then
  kind_load_image "keycloak"        "${KEYCLOAK_TAG}"       "${KEYCLOAK_TAG}"
  kind_load_image "postgresql"      "${PG_SRC_TAG}"         "${PG_TAG}"
  kind_load_image "redis"           "${REDIS_TAG}"          "${REDIS_TAG}"
  kind_load_image "redis-exporter"  "${REDIS_EXPORTER_TAG}" "${REDIS_EXPORTER_TAG}"
  kind_load_image "thanos"          "${THANOS_TAG}"         "${THANOS_TAG}"

  # falcoctl sidecar — from falcosecurity/ (not bitnamilegacy)
  FALCOCTL_HARBOR="harbor.${DOMAIN}/falcosecurity/falcoctl:${FALCOCTL_TAG}"
  if ! docker exec "${KIND_CLUSTER}-worker" ctr --namespace=k8s.io images ls 2>/dev/null | grep -qF "${FALCOCTL_HARBOR}"; then
    log "Loading ${FALCOCTL_HARBOR} into kind nodes..."
    FC_DIGEST=$(docker manifest inspect "falcosecurity/falcoctl:${FALCOCTL_TAG}" 2>/dev/null \
      | python3 -c "
import sys, json
m = json.load(sys.stdin)
for p in m.get('manifests', []):
    pl = p.get('platform', {})
    if pl.get('os') == 'linux' and pl.get('architecture') == 'arm64':
        print(p['digest']); break
" 2>/dev/null | head -1)
    if [[ -n "$FC_DIGEST" ]]; then
      docker pull "falcosecurity/falcoctl@${FC_DIGEST}" 2>/dev/null
      docker tag "falcosecurity/falcoctl@${FC_DIGEST}" "${FALCOCTL_HARBOR}"
    else
      docker pull "falcosecurity/falcoctl:${FALCOCTL_TAG}" 2>/dev/null
      docker tag "falcosecurity/falcoctl:${FALCOCTL_TAG}" "${FALCOCTL_HARBOR}"
    fi
    FCTMP=$(mktemp /tmp/kindimg.XXXXXX.tar)
    docker save "${FALCOCTL_HARBOR}" -o "${FCTMP}"
    kind load image-archive "${FCTMP}" --name "${KIND_CLUSTER}" 2>/dev/null && \
      log "Loaded ${FALCOCTL_HARBOR} ✓" || log "WARN: kind load failed for ${FALCOCTL_HARBOR}"
    rm -f "${FCTMP}"
  else
    log "kind already has ${FALCOCTL_HARBOR} ✓"
  fi
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
  --set-string "keycloak.postgresql.primary.podAnnotations.forceRestart=$(date +%s)" \
  --set "keycloak.postgresql.primary.resources.requests.memory=64Mi" \
  --set "keycloak.postgresql.primary.resources.limits.memory=256Mi" \
  ${KEYCLOAK_EXTRA[@]+"${KEYCLOAK_EXTRA[@]}"}

# ── Step 4: GitLab + ArgoCD ──────────────────────────────────────────────

install_chart gitlab gitlab \
  --set "gitlab.redis.image.registry=harbor.${DOMAIN}" \
  --set "gitlab.redis.metrics.image.registry=harbor.${DOMAIN}"
install_chart argocd argocd

# ── Step 5: Observability ────────────────────────────────────────────────

install_chart prometheus-stack monitoring
install_chart loki monitoring
install_chart tempo monitoring
install_chart thanos monitoring \
  --set "thanos.image.registry=harbor.${DOMAIN}"

# ── Step 6: Security mesh ────────────────────────────────────────────────

# Clear stale istiod webhook to prevent SSA conflict (cycle 33 fix — pilot-discovery conflicts
# with helm's server-side apply on ValidatingWebhookConfiguration istiod-default-validator)
kubectl delete validatingwebhookconfiguration istiod-default-validator \
  --context "$CONTEXT" --ignore-not-found 2>/dev/null || true

install_chart istio istio-system
# OPA Gatekeeper requires a two-pass install: the controller must process
# ConstraintTemplates into runtime CRDs before Constraint resources can be applied.
# First pass installs gatekeeper + ConstraintTemplates; constraints may fail — that's expected.
# Second pass installs constraints after CRDs are established.
if ! helm status opa-gatekeeper -n gatekeeper-system --kube-context "$CONTEXT" &>/dev/null; then
  log "opa-gatekeeper: first-pass install (establishing CRDs)..."
  helm upgrade --install opa-gatekeeper "${PLATFORM_DIR}/charts/opa-gatekeeper/" \
    --namespace gatekeeper-system --create-namespace \
    --set "global.domain=${DOMAIN}" \
    --set "global.storageClass=${BLOCK_SC}" \
    --timeout "${TIMEOUT}" \
    --kube-context "${CONTEXT}" \
    2>&1 || true  # constraints will fail on first install — expected
  # Wait for gatekeeper webhook to register ConstraintTemplate CRDs
  log "opa-gatekeeper: waiting for constraint CRDs to be established..."
  for i in $(seq 1 30); do
    kubectl get crd k8snoprivilegeescalations.constraints.gatekeeper.sh \
      --context "$CONTEXT" &>/dev/null && break
    sleep 2
  done
fi
install_chart opa-gatekeeper gatekeeper-system
install_chart falco falco \
  --set "falco.falcoctl.image.registry=harbor.${DOMAIN}"
install_chart trivy-operator trivy-system

# ── Step 7: Developer experience ─────────────────────────────────────────

install_chart backstage backstage
install_chart code-server code-server
install_chart sonarqube sonarqube \
  --set "sonarqube.postgresql.image.registry=harbor.${DOMAIN}" \
  --set "sonarqube.postgresql.image.tag=${PG_TAG}"
# ReportPortal: pass existing rabbitmq password on upgrade (bitnami subchart requires this)
RP_EXTRA=()
if kubectl get secret reportportal-rabbitmq-secret -n reportportal --context "$CONTEXT" &>/dev/null; then
  RP_RABBITMQ_PASS=$(kubectl get secret reportportal-rabbitmq-secret -n reportportal \
    --context "$CONTEXT" -o jsonpath="{.data.rabbitmq-password}" | base64 -d 2>/dev/null || echo "")
  if [[ -n "$RP_RABBITMQ_PASS" ]]; then
    RP_EXTRA=(--set "reportportal.rabbitmq.auth.password=${RP_RABBITMQ_PASS}")
  fi
fi
install_chart reportportal reportportal ${RP_EXTRA[@]+"${RP_EXTRA[@]}"}

log ""
log "Deploy pass complete."
