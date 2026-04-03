# Changelog — Cycle 42

## Observed
- Layer: 2 (Zot — autarky boundary / internal registry)
- Service: zot
- Category: CONFIG_ERROR
- Evidence: `"error":"operation timeout: boltdb file is already in use, path '/var/lib/registry/cache.db'"` — Zot pod had 5 restarts; each restart timed out waiting for BoltDB lock released by the previous crashed container

## Applied

### Fix 1: Disable BoltDB dedupe to eliminate lock contention
- Changed `config.storage.dedupe: true` → `dedupe: false` in `platform/charts/zot/values.yaml`
- With `dedupe: true`, Zot maintains a BoltDB file (`cache.db`) for content-addressable deduplication. On restart (especially with `strategy: Recreate`), the new process timed out waiting for the lock from the killed container. Disabling dedupe removes BoltDB entirely — Zot no longer creates or needs `cache.db`.
- Tradeoff: minor storage increase (duplicate blobs not deduplicated). Acceptable on a 20Gi PVC with a small local dev cluster.
- Files: `platform/charts/zot/values.yaml`

### Fix 2: Add required OPA Gatekeeper labels to Zot Deployment
- OPA's `require-labels` constraint blocked the upgrade: `Deployment zot is missing required label: app, tier`
- Added `app: zot` and `tier: registry` to the `zot.labels` helper in `_helpers.tpl`
- Files: `platform/charts/zot/templates/_helpers.tpl`

## Validated
```
helm lint platform/charts/zot/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
grep -rn "docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io" platform/charts/zot/templates/
→ PASS

helm upgrade zot platform/charts/zot/ -n zot --timeout 90s --wait
→ Release "zot" has been upgraded. REVISION: 6. STATUS: deployed

kubectl get pods -n zot
→ zot-6c69787c8d-qsdc6   1/1   Running   0   16s
```

## Expect Next Cycle
- Zot restart count stays at 0 (BoltDB lock no longer an issue)
- All 8 layers healthy: sovereign-0 memory at 88% may still cause transient probe warnings but all pods running
- Consider investigating whether any charts other than Zot and Backstage are missing `app`/`tier` labels (to prevent future Gatekeeper blocks on upgrades)
