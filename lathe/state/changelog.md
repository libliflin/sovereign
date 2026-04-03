# Changelog — Cycle 18

## Observed

- Layer: 2 (Harbor — internal registry / autarky boundary)
- Service: Harbor — all components fail with `exec format error` or `QEMU internal SIGSEGV`
- Category: IMAGE_ISSUE — Harbor publishes amd64-only images; no arm64 variant exists on Docker Hub or GHCR
- Evidence:
  - `k3s ctr content get <hash>` → `application/vnd.docker.distribution.manifest.v2+json`, `arch: amd64 os: linux`
  - `kubectl logs harbor-redis-0 --previous` → `exec /usr/bin/redis-server: exec format error`
  - `kubectl logs harbor-core-* --tail` → `QEMU internal SIGSEGV {code=MAPERR, addr=0x20}`
  - Docker Hub API confirmed: every Harbor tag (`v2.11.0` through `v2.14.3`) has only `['amd64']` images
  - GHCR `ghcr.io/goharbor/` confirmed: manifest type `application/vnd.docker.distribution.manifest.v2+json` (single-arch, amd64)

## Applied

1. Fixed Harbor chart PVC storageClass: changed all 5 PVC storageClass fields from `""` to `"local-path"` in `platform/charts/harbor/values.yaml`
2. Deployed Harbor — PVCs bound (local-path), pods started, but crashed on `exec format error`
3. Installed `qemu-user-static` on all 3 Lima nodes → registered `qemu-x86_64` binfmt_misc handler with `F` (fix-binary) flag
4. Result: nginx, portal, and redis started successfully under QEMU emulation; but `harbor-core`, `harbor-registryctl`, and `harbor-db` (init container) all hit `QEMU internal SIGSEGV {code=MAPERR, addr=0x20}` — Go runtime and PostgreSQL use memory patterns that QEMU user-mode cannot reliably emulate on arm64 Apple VZ
5. Uninstalled Harbor, cleaned up PVCs and namespace

- Files: `platform/charts/harbor/values.yaml` (storageClass fix preserved — correct for next attempt)

## Validated

```
# Helm lint
helm lint platform/charts/harbor/
→ 1 chart(s) linted, 0 chart(s) failed

# Autarky gate
grep -rn "docker.io|quay.io|..." platform/charts/*/templates/
→ PASS

# Cluster clean
kubectl get pods -A → Layer 1 healthy (cert-manager, sealed-secrets, openbao all 1/1 Running)
```

## Blocker: Human Decision Required

Harbor is **amd64-only**. The platform runs on **arm64 Lima VMs** (Apple Silicon host). QEMU user-mode emulation is insufficient — Go's runtime and PostgreSQL both hit SIGSEGV under emulation.

**This is not fixable within the current image set.** Options require a human decision:

**Option A — Switch Layer 2 registry to Zot:**
- [Zot](https://zotregistry.dev/) is CNCF Sandbox, Apache 2.0, OCI-compliant
- Publishes multi-arch images (amd64 + arm64) to Docker Hub and GHCR
- Has auth, garbage collection, replication, Trivy scanning plugin
- Could serve as bootstrap registry; Harbor can be re-added when arm64 images are available
- Requires adding a `platform/charts/zot/` chart (architectural change)

**Option B — Accept amd64 cluster:**
- Re-provision Lima VMs as x86_64 (Lima supports x86_64 VMs via QEMU on Apple Silicon)
- All official images work without emulation issues
- Performance cost of running x86_64 VMs on Apple Silicon
- Change Lima template from `template:k3s` to `template:k3s` with `--arch x86_64`

**Option C — Wait for Harbor arm64:**
- Harbor project has not committed to arm64 images (all 2.11–2.14 releases are amd64-only)
- No timeline known

## Expect Next Cycle

Pending human decision. Layer 1 remains healthy. No regression on lower layers.

If Option A (Zot): next cycle deploys a Zot chart and establishes the autarky boundary with arm64-compatible images.
If Option B (x86_64 VMs): next cycle rebuilds cluster nodes as x86_64 and redeploys Harbor.
