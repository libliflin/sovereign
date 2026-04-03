# Changelog — Cycle 34

## Observed
- Layer: 0 (Lima VMs + k3s — compute/network foundation)
- Service: lima-sovereign-2 (DiskPressure → cascading evictions)
- Category: RESOURCE_ISSUE
- Evidence:
  - `lima-sovereign-2` had DiskPressure condition True with `node.kubernetes.io/disk-pressure:NoSchedule` taint
  - Node at 86% disk usage (24G/29G used)
  - Cascading evictions: argocd-server (12 pods), jaeger-agent, node-exporter, kube-system helper pods
  - `openbao-0` and `victorialogs-server-0` Pending — PVs bound to sovereign-2, blocked by disk taint
  - Root cause: `/var/lib/rancher/k3s/storage/pvc-2b4807f7-..._harbor_database-data-harbor-database-0` was consuming **22GB**
  - Harbor is dead code (D1 — arm64 incompatible), but its database PVC was never cleaned up
  - Local-path helper pods trying to delete the PVs were themselves being evicted (circular failure)

## Applied
- Manually deleted Harbor database PVC directory on sovereign-2: freed 22GB (86% → 10%)
- Manually deleted Harbor redis PVC directory on sovereign-2 (8K, also stale)
- Patched both Released PVs to remove `kubernetes.io/pv-protection` finalizers so k8s can GC them
- Deleted 13 Failed/Evicted argocd-server pods (cleanup of eviction debris)
- Deleted Failed jaeger-agent, node-exporter, helper pods
- Files: none (in-cluster cleanup only)

## Validated
```
limactl shell sovereign-2 df -h /
→ Filesystem: /dev/vda1   Size: 29G   Used: 2.8G   Avail: 26G   Use%: 10%

kubectl get nodes
→ lima-sovereign-0   Ready   control-plane
→ lima-sovereign-1   Ready
→ lima-sovereign-2   Ready

PVs patched:
→ persistentvolume/pvc-2b4807f7-... patched
→ persistentvolume/pvc-9215aa1c-... patched

Autarky gate (no change to templates):
→ PASS
```

## Expect Next Cycle
- `lima-sovereign-2` DiskPressure clears (kubelet 5-minute eviction-pressure-transition-period)
- `node.kubernetes.io/disk-pressure:NoSchedule` taint removed automatically once pressure resolves
- `openbao-0` schedules to sovereign-2 (PV has node affinity there) and joins the cluster
- `victorialogs-server-0` schedules and starts
- ArgoCD server replica count normalizes (one replica already Running)
- Ready to assess Layer 6 (Istio, OPA-Gatekeeper, Falco, Trivy)

---

# Changelog — Cycle 33

## Observed
- Layer: 2 (Harbor — autarky boundary)
- Service: harbor-core, harbor-db, harbor-jobservice, harbor-registry
- Category: IMAGE_ISSUE (arm64 incompatibility, permanent decision D1)
- Evidence: Cycles 31-32 showed Harbor QEMU SIGSEGV on arm64; D1 permanently replaces Harbor with Zot
- Zot is Running (revision 4), ArgoCD/Forgejo/Keycloak all deployed and Running
- Jaeger Cassandra removed (cycle 32), cluster memory stabilized

## Applied
- (See cycle 32 changelog — Cassandra disable was the cycle 32 fix)
- Cycle 33: no new chart installs recorded — observability layer stabilizing

## Validated
- All Layer 1-5 helm releases deployed
- Jaeger running without Cassandra (Badger embedded storage)

## Expect Next Cycle
- Disk pressure from Harbor PVC remnants to surface (it did — cycle 34 address it)

---

# Changelog — Cycle 32

## Observed
- Layer: 5 (Prometheus, VictoriaLogs, Jaeger — observability)
- Service: jaeger-cassandra-2 (CrashLoopBackOff), propagating to Layer 2 Harbor probe failures
- Category: CONFIG_ERROR
- Evidence:
  - `jaeger-cassandra-2` in CrashLoopBackOff (5 restarts) on lima-sovereign-0
  - 5× `SystemOOM: victim process java` on lima-sovereign-0 within the snapshot window
  - Harbor liveness/readiness probe timeouts on same node under memory pressure
  - Root cause: upstream `jaeger-3.4.1` chart defaults `provisionDataStore.cassandra: true`;
    our `values.yaml` set `storage.type: badger` but never disabled the Cassandra subchart,
    so 3 Cassandra pods (Java, ~1–2GB heap each) deployed despite being unreachable/unused

## Applied
- Added `jaeger.provisionDataStore.cassandra: false` to `platform/charts/jaeger/values.yaml`
- Ran `helm upgrade jaeger` — Cassandra StatefulSet removed, cassandra-0/1/2 Terminating
- Files: `platform/charts/jaeger/values.yaml`

## Validated
```
helm lint platform/charts/jaeger/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
→ PASS

helm upgrade jaeger platform/charts/jaeger/ -n jaeger --timeout 60s --wait
→ Release "jaeger" has been upgraded. STATUS: deployed REVISION: 2
```

## Expect Next Cycle
- Cassandra pods fully terminated; ~3GB of Java heap freed across the cluster
- sovereign-0 OOM events cease; nodes return to stable memory utilization
- Harbor liveness/readiness probes recover (no more memory pressure on sovereign-0)
- Jaeger collector and query continue running with Badger embedded storage
- Ready to progress to Layer 6 (Istio, OPA-Gatekeeper, Falco, Trivy)
