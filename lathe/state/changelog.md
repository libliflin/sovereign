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
