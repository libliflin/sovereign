# CTO Intervention — 2026-04-01

## Problem

Cycle 33 stalled: operator exit code 1 for multiple consecutive cycles. Loop process dead (PID 19634 not found). Both worker nodes at 99% memory requests — harbor-core could not schedule, blocking all downstream charts.

## Root Cause

**Primary:** loki-chunks-cache StatefulSet requested **9830Mi** (8192MB allocation default from upstream chart + process overhead), which exceeds each worker node's ~7837Mi allocatable memory. It could never schedule. loki-results-cache (1229Mi) was scheduled on worker2, consuming the last available headroom.

**Secondary failures all downstream of memory pressure:**
1. harbor-core Pending → Harbor API unavailable → keycloak/thanos/sonarqube ImagePullBackOff
2. ceph-block StorageClass hardcoded in prometheus-stack and gitlab — doesn't exist on kind; PVCs stuck Pending indefinitely
3. Tempo and Loki configured for rook-ceph S3 — rook-ceph not deployed; Tempo CrashLoopBackOff
4. Falco using eBPF driver requiring kernel headers — linuxkit has none; Init:Error
5. Istio upgrade failing: SSA ownership conflict on ValidatingWebhookConfiguration with pilot-discovery
6. OPA Gatekeeper: Constraint resources applied before CRD generation from ConstraintTemplates
7. gitlab-redis, thanos-query, sonarqube-postgresql pulling from docker.io/bitnami (old tags removed)
8. reportportal rabbitmq upgrade requires existing password

## Fix Applied

### Chart fixes
- `loki/values.yaml`: disabled `chunksCache` (was 9830Mi) and `resultsCache` (was 1229Mi); switched S3 from rook-ceph to `minio.minio.svc:9000`
- `tempo/values.yaml`: switched S3 from rook-ceph to `minio.minio.svc:9000`
- `prometheus-stack/values.yaml`: hardcoded `ceph-block` → `standard` (grafana and prometheus PVCs)
- `gitlab/values.yaml`: hardcoded `ceph-block` → `standard` (gitaly PVC)
- `falco/values.yaml`: `driver.kind: ebpf` → `driver.kind: modern_ebpf` (CO-RE, no kernel headers)

### deploy.sh fixes
- Delete `istiod-default-validator` webhook before istio upgrade (prevents SSA conflict)
- Two-pass OPA Gatekeeper install: first pass creates controller + CRDs, polls until `k8snoprivilegeescalations.constraints.gatekeeper.sh` exists, second pass applies Constraints
- Read existing rabbitmq password for reportportal upgrades
- Pass `harbor.${DOMAIN}` image registry for gitlab (redis), thanos, sonarqube (postgresql)
- Added redis, thanos, sonarqube-postgresql to Harbor seeding list

### Manual cluster actions
- Deleted `loki-results-cache` StatefulSet (freed 1229Mi on worker2)
- Deleted `loki-chunks-cache` StatefulSet (9830Mi unschedulable pod)
- Deleted stuck ceph-block PVCs: `repo-data-gitlab-gitaly-0`, `prometheus-stack-grafana`, `sonarqube-sonarqube`
- **harbor-core is now Running on sovereign-test-worker2**

## Decisions Made

- **Loki caches disabled for kind**: chunksCache (8192MB) and resultsCache (1024MB) are appropriate for production but catastrophic for kind. Loki works without them, just slower. Appropriate for dev environment.
- **MinIO instead of rook-ceph**: rook-ceph requires raw block devices and is not deploying. MinIO is already running at `minio.minio.svc:9000` and is the correct S3 backend for kind.
- **modern_ebpf for falco**: CO-RE eBPF is embedded in the falco binary. No init container, no kernel headers. Works on any BTF-capable kernel (5.8+). linuxkit 6.10.14 qualifies.
- **ceph-block → standard**: ceph-block is the correct class for production bare-metal clusters. For kind, `standard` (rancher local-path) is the only available RWO class. These changes should be reverted when deploying to production.

## Loop Restarted

Cycle 33 → restarting from cycle 33. Pushed commit `6b94fb4` to main.

---

# CTO Intervention — 2026-04-01 (Second Intervention)
**Duration:** ~3 hours (two sessions, context compaction between them)
**Cycles at entry:** 43 (running:counsel) — loop alive but stuck, same keycloak failure 4+ cycles

## Problem

Loop was cycling on keycloak/postgresql ImagePullBackOff for 4+ consecutive cycles. Harbor was empty on every cycle. All surgeon fixes were addressing symptoms while the structural seeding failure persisted.

## Root Causes

Two independent structural failures, both silent:

**1. Source tags retired from docker.io/bitnami**
Old code pulled from `docker.io/bitnami/<repo>:<pinned-tag>`. Bitnami moves old pinned tags to `docker.io/bitnamilegacy/` when versions are superseded. `docker pull docker.io/bitnami/keycloak:24.0.5-debian-12-r0` and similar failed silently — caught by `|| log "WARN: ..."`, invisible in operator reports.

**2. Docker Desktop VM isolation broke docker push**
The old seeding code did `docker login localhost:5000` + `docker push localhost:5000/...`. Docker Desktop daemon runs inside a VM. The VM cannot reach the macOS host's localhost port-forwards. Every `docker push` timed out silently. Harbor appeared healthy but never received images.

Result: `==> harbor: ready ✓` logged on every cycle with no actual seeding. Surgeon had no signal that seeding was broken.

## Fixes Applied (deploy.sh)

### Seeding rewrite — kind load image-archive
Replaced `docker push localhost:5000` with:
- Pull arm64-specific digest from `bitnamilegacy/<repo>@<sha256:...>` (avoids multi-platform manifest error in `kind load docker-image`)
- Tag as `harbor.${DOMAIN}/bitnami/<repo>:<tag>`
- `docker save` to temp tar → `kind load image-archive <tar> --name <cluster>`

Pods pulling `harbor.sovereign.local/bitnami/...` find the image in kind's containerd cache without Harbor serving it.

### Source tags updated to bitnamilegacy
| Image | Broken source | Fixed source |
|-------|--------------|-------------|
| keycloak | `docker.io/bitnami/keycloak:24.0.5-debian-12-r0` | `bitnamilegacy/keycloak:24.0.5-debian-12-r8` |
| postgresql | `docker.io/bitnami/postgresql:16` (no such tag) | `bitnamilegacy/postgresql:16.3.0-debian-12-r14` |
| redis | `docker.io/bitnami/redis:6.2.7-debian-11-r11` | `bitnamilegacy/redis:6.2.7-debian-11-r11` |
| redis-exporter | `docker.io/bitnami/redis-exporter:1.43.0-debian-11-r4` | `bitnamilegacy/redis-exporter:1.43.0-debian-11-r4` |
| thanos | `docker.io/bitnami/thanos:0.36.0-debian-12-r1` | `bitnamilegacy/thanos:0.36.0-debian-12-r1` |

### Additional Helm overrides
- `keycloak.image.tag=${KEYCLOAK_TAG}` — explicit pin at install; dynamic extraction returned retired r0 tag
- `keycloak.postgresql.image.tag=${PG_TAG}` — PG16 (PG11 tags unavailable on bitnamilegacy)
- `gitlab.redis.metrics.image.registry=harbor.${DOMAIN}` — redis-exporter was pulling from docker.io
- `falco.falcoctl.image.registry=harbor.${DOMAIN}` — falcoctl sidecar was pulling from docker.io
- `sonarqube.postgresql.image.tag=${PG_TAG}` — SonarQube PG11 tags unavailable
- falcoctl kind-load block added (source: `falcosecurity/falcoctl`, not bitnamilegacy)

### Manual cluster interventions
- Deleted stalled StatefulSet pods (keycloak-postgresql-0, gitlab-redis-master-0, thanos-storegateway-0) to force rolling update
- `helm uninstall gitlab` — freed 2.5Gi from CrashLoopBackOff pods blocking keycloak scheduling
- Deleted 4 tempo CrashLoopBackOff pods (896Mi total reservations) to free worker2 memory; keycloak-postgresql-0 PVC is node-affinity pinned to worker2

## State at Exit (cycle 45 counsel running)

- keycloak-postgresql-0: Running ✓
- keycloak-0: Running (readiness probe pending) ✓
- Loop: PID 26263, cycle 45 counsel in progress (PID 40476)
- Commits: `dae4d10` (falcoctl), prior CTO session changes in `07c920e`

## Structural Recommendation

The operator report must surface WARN lines from deploy.sh as failures, not informational notes. Currently `|| log "WARN: ..."` makes silent failures invisible to the counsel → no directive ever targets the seeding layer. This allowed the bitnamilegacy and Docker Desktop failures to persist for 10+ cycles undetected.
