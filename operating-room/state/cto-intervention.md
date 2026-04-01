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
