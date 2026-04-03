# Changelog — Cycle 33

## Observed
- Layer: 2 (Harbor — autarky boundary)
- Service: harbor-core, harbor-db, harbor-jobservice, harbor-registry
- Category: IMAGE_ISSUE
- Evidence:
  - `harbor-core` log: `x86_64-binfmt-P: QEMU internal SIGSEGV {code=MAPERR, addr=0x20}` (still amd64)
  - `harbor-database-0` liveness probe timeout: `/docker-healthcheck.sh timed out after 10s` (amd64 under QEMU = slow)
  - `harbor-jobservice` restartCount: 5, `harbor-registry` 1/2 Running restartCount: 5
  - All harbor images in containerd still `linux/amd64` despite cycle 31 downloads marked `done: true`
  - Root cause: `fetch.sh` no-daemon path (line 114) called `k3s ctr images pull <source>` **without
    `--platform linux/arm64`**. The `arch = 'arm64'` variable set in cycle 31 was only used in the
    Docker-daemon path (`docker pull --platform`). The no-daemon path ignored it entirely, so `ctr pull`
    on each arm64 node either resolved the multi-arch manifest to amd64 (default) or returned the
    already-cached amd64 layers unchanged.

## Applied
- Fixed `lathe/fetch.sh` no-daemon path: added `'--platform', f'linux/{arch}'` to the `ctr images pull`
  command so it explicitly requests `linux/arm64` regardless of containerd defaults
- Reset all 6 harbor image entries in `lathe/state/downloads.json` from `done: true` → not-done
  (removed `done`/`result` fields, updated `added_by_cycle: 33`) so fetch.sh re-processes them
  next cycle with the corrected `--platform` flag
- Files: `lathe/fetch.sh`, `lathe/state/downloads.json`

## Validated
```
bash -n lathe/fetch.sh
→ PASS: fetch.sh syntax OK

autarky gate:
grep -rn "docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io" platform/charts/*/templates/
→ PASS
```

## Downloads Queued
- image: goharbor/harbor-core:v2.11.0 → k3s nodes (arm64 re-pull, --platform linux/arm64)
- image: goharbor/harbor-db:v2.11.0 → k3s nodes (arm64 re-pull)
- image: goharbor/harbor-jobservice:v2.11.0 → k3s nodes (arm64 re-pull)
- image: goharbor/harbor-registryctl:v2.11.0 → k3s nodes (arm64 re-pull)
- image: goharbor/registry-photon:v2.11.0 → k3s nodes (arm64 re-pull)
- image: goharbor/redis-photon:v2.11.0 → k3s nodes (arm64 re-pull)

## Expect Next Cycle
- fetch.sh runs with `--platform linux/arm64` and pulls native arm64 harbor images into all 3 nodes
- `k3s ctr images list` shows `linux/arm64` for all goharbor images
- harbor-core stops SIGSEGV; harbor-database healthcheck script runs natively (sub-second, no QEMU overhead)
- All harbor pods reach 1/1 Running with 0 new restarts
- harbor-jobservice, harbor-registry stabilize (no more QEMU crash loops)
- Ready to advance to Layer 6 (Istio, OPA-Gatekeeper, Falco, Trivy) once Harbor is stable

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

---

# Changelog — Cycle 31

## Observed
- Layer: 2 (Harbor — autarky boundary)
- Service: harbor-core, harbor-db, harbor-jobservice, harbor-registry
- Category: IMAGE_ISSUE
- Evidence:
  - `harbor-core`, `harbor-jobservice` logs: `x86_64-binfmt-P: QEMU internal SIGSEGV {code=MAPERR, addr=0x20}`
  - `harbor-db` readiness probe timeout on `/docker-healthcheck.sh` (PostgreSQL)
  - `harbor-registry` restartCount: 4 (registryctl container crash)
  - All 5 pre-loaded goharbor images confirmed `linux/amd64` via `k3s ctr images list`
  - Lima nodes confirmed `arm64` (aarch64) via `kubectl get nodes` and `uname -m`
  - Root cause in `lathe/fetch.sh` line 55: `arch = 'amd64'` — hardcoded wrong architecture

## Applied
- Fixed `fetch.sh`: `arch = 'amd64'` → `arch = 'arm64'` with corrected comment
- Queued arm64 re-download of 6 failing Harbor images in `downloads.json`:
  - `goharbor/harbor-core:v2.11.0`
  - `goharbor/harbor-db:v2.11.0`
  - `goharbor/harbor-jobservice:v2.11.0`
  - `goharbor/harbor-registryctl:v2.11.0`
  - `goharbor/registry-photon:v2.11.0`
  - `goharbor/redis-photon:v2.11.0`
- Files: `lathe/fetch.sh`, `lathe/state/downloads.json`

## Validated
```
bash -n lathe/fetch.sh
→ PASS: fetch.sh syntax OK

autarky gate:
→ PASS
```

## Expect Next Cycle
- `fetch.sh` runs at cycle start, pulls Harbor images as `linux/arm64`, imports into all 3 nodes
- Existing amd64 images overwritten in containerd by arm64 variants (same tags, new manifests)
- Harbor pods restart and run natively on arm64: no QEMU binfmt, no SIGSEGV
- Expected: harbor-core 1/1, harbor-db 1/1, harbor-jobservice 1/1, harbor-registry 2/2 all Running
- After Harbor stabilizes: continue to Layer 6 (Istio, OPA-Gatekeeper, Falco, Trivy)
