# Changelog — Cycle 25

## Retro (Cycles 20–24)

| Cycle | Layer | Action | Outcome |
|-------|-------|--------|---------|
| 20 | L2 (Zot) | Pull-through proxy configured | ✓ |
| 21 | L2 (Zot) | k3s registry mirrors written | ✓ Verified via Zot logs |
| 22 | L3 (Keycloak) | Deploy attempted; bitnami images missing | → downloads queued |
| 23 | L3 (Keycloak) | Pods Running, release reconciled | ✓ |
| 24 | L2 (Harbor) | Harbor installed | ✓ All pods Running |

**Pattern:** Advancing cleanly through layers. No regressions. One recurring theme: bitnami pinned tags require bitnamilegacy source — this repeats every time a new bitnami-backed chart deploys.

---

## Observed

- Layer: 4 (Forgejo — SCM)
- Service: forgejo
- Category: CONFIG_ERROR + IMAGE_ISSUE (dual)
  1. `forgejo.postgresql.enabled: false` — no DB would exist, but forgejo app config pointed at `forgejo-postgresql.forgejo.svc.cluster.local:5432`
  2. `storageClass: "standard"` — doesn't exist; only `local-path` available
  3. Upstream chart PDB template bug: renders `spec.enabled: false` into PodDisruptionBudget spec (invalid)
  4. `docker.io/bitnami/postgresql:17.2.0-debian-12-r6` not found — bitnami pinned tags moved to `bitnamilegacy`
- Evidence: PVCs stuck Pending (`standard` StorageClass); PDB create error `.spec.enabled field not declared in schema`; `ImagePullBackOff: docker.io/bitnami/postgresql:17.2.0-debian-12-r6 not found`

## Applied

- Enabled `forgejo.postgresql.enabled: true` with auth credentials
- Changed all `storageClass: "standard"` → `local-path` (3 occurrences)
- Fixed PDB values: replaced `{enabled: false}` with `{maxUnavailable: 1}` — only valid PDB spec fields; `enabled` is not a PDB spec field and caused schema validation failure
- Set `replicaCount: 1` (RWX not available with local-path; HA revisit when Ceph arrives)
- Set `ISSUE_INDEXER_TYPE: db` (bleve requires single instance; db works with postgres)
- Moved deprecated `LFS_CONTENT_PATH` from `[server]` to `[lfs]` section
- Queued `bitnami/postgresql:17.2.0-debian-12-r6` in downloads.json (source: bitnamilegacy)
- Files: `platform/charts/forgejo/values.yaml`, `lathe/state/downloads.json`

## Validated

```
helm lint platform/charts/forgejo/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
→ PASS

helm upgrade --install forgejo (with 180s timeout):
→ PVCs: Bound (local-path provisioned successfully)
→ forgejo pod: image pulled from code.forgejo.org in 6.2s (via Zot proxy)
→ forgejo configure-gitea init container: retrying (DB not ready — postgresql ImagePullBackOff)
→ forgejo-postgresql-0: ImagePullBackOff — docker.io/bitnami/postgresql:17.2.0-debian-12-r6 not found
→ Release in failed state awaiting bitnami postgresql image (queued in downloads.json)
```

## Downloads Queued

- image: `docker.io/bitnamilegacy/postgresql:17.2.0-debian-12-r6` → tag as `docker.io/bitnami/postgresql:17.2.0-debian-12-r6` → k3s nodes

## Expect Next Cycle

After fetch.sh imports `bitnami/postgresql:17.2.0-debian-12-r6` into all 3 nodes:
- `forgejo-postgresql-0` will start
- `forgejo configure-gitea` init container will complete (DB connection succeeds)
- Forgejo main container will reach Running state
- Run: `helm upgrade forgejo platform/charts/forgejo/ -n forgejo --timeout 180s --wait`
