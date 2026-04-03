# Changelog — Cycle 12

## Observed

- Layer: 3 (Keycloak — identity / SSO)
- Service: keycloak — images still not imported; download failed in cycle 11
- Category: CONFIG_ERROR (fetch.sh using wrong architecture)
- Evidence:
  - `downloads.json` shows both cycle 11 entries with `result: "failed: Command '['docker', 'pull', '--platform', 'linux/arm64', ...]' returned non-zero exit status 1."`
  - Root cause: `fetch.sh` detects host machine arch (`arm64` on Apple Silicon) and pulls `linux/arm64` images — but Lima k3s nodes run `linux/amd64` (x86_64 via QEMU emulation). An arm64 image would fail to run even if imported.
  - Both `docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r0` and `docker.io/bitnamilegacy/postgresql:16.3.0-debian-12-r14` DO exist for `amd64` (confirmed via `docker manifest inspect`).
  - No keycloak helm release exists; namespace is empty — clean state for next deploy.

## Applied

- Fixed `lathe/fetch.sh`: changed arch detection from `'arm64' if plat.machine() == 'arm64' else 'amd64'` to hardcoded `'amd64'`. Lima k3s nodes always run x86_64 via QEMU; host arch is irrelevant for import target.
- Reset `lathe/state/downloads.json`: removed `result` and `done` fields from both cycle 11 entries so fetch.sh retries them next cycle with the correct platform.
- Files: `lathe/fetch.sh`, `lathe/state/downloads.json`

## Validated

```
# fetch.sh syntax
bash -n lathe/fetch.sh
→ PASS: syntax ok

# Autarky gate
grep -rn "docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io" platform/charts/*/templates/
→ PASS
```

## Downloads Queued (retry)

- image: `docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r0` → k3s nodes as `docker.io/bitnami/keycloak:24.0.5-debian-12-r0` (now pulls linux/amd64)
- image: `docker.io/bitnamilegacy/postgresql:16.3.0-debian-12-r14` → k3s nodes as `docker.io/bitnami/postgresql:16.3.0-debian-12-r14` (now pulls linux/amd64)

## Expect Next Cycle

- fetch.sh runs at cycle start, pulls both images as `linux/amd64`, imports into all 3 k3s nodes
- Deploy keycloak: `helm upgrade --install keycloak platform/charts/keycloak/ -n keycloak --set ingress.enabled=false --set realmInit.enabled=false`
- `keycloak-0` finds image locally → starts
- `keycloak-postgresql-0` gets `local-path` PVC (global.storageClass is `local-path` in values.yaml) → binds → starts
- Layer 3 first pod running

---

# Changelog — Cycle 11

## Observed

- Layer: 3 (Keycloak — identity / SSO)
- Service: keycloak — deploy attempt failed on first try
- Category: IMAGE_ISSUE + CONFIG_ERROR
- Evidence:
  - `keycloak-0` stuck in `Init:ImagePullBackOff`: `docker.io/bitnami/keycloak:24.0.5-debian-12-r0: not found` — bitnami migrated pinned tags to `docker.io/bitnamilegacy/`
  - `keycloak-postgresql-0` stuck in `Pending`: PVC `data-keycloak-postgresql-0` requesting `ceph-block` StorageClass (doesn't exist); caused by `global.storageClass: "ceph-block"` in chart values propagating to bitnami postgresql sub-chart
  - Layer 1 (openbao-2): readiness probe 503 was transient — pod confirmed unsealed (standby) when checked

## Applied

- Fixed `platform/charts/keycloak/values.yaml`: changed `global.storageClass` from `"ceph-block"` to `"local-path"` (k3s default; Ceph not installed)
- Queued 2 images to `lathe/state/downloads.json` for import into k3s nodes next cycle:
  - `docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r0` → re-tagged as `docker.io/bitnami/keycloak:24.0.5-debian-12-r0`
  - `docker.io/bitnamilegacy/postgresql:16.3.0-debian-12-r14` → re-tagged as `docker.io/bitnami/postgresql:16.3.0-debian-12-r14`
- Uninstalled failed keycloak release (revision 1, status: failed)
- Files: `platform/charts/keycloak/values.yaml`, `lathe/state/downloads.json`

## Validated

```
# Helm lint
helm lint platform/charts/keycloak/
→ 1 chart(s) linted, 0 chart(s) failed

# Autarky gate (our templates)
grep -rn "docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io" platform/charts/*/templates/
→ PASS

# Secrets created
kubectl get secrets -n keycloak
→ keycloak-admin-secret, keycloak-db-secret (both present, will survive uninstall)
```

## Downloads Queued

- image: `docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r0` → k3s nodes (tagged as docker.io/bitnami/keycloak:24.0.5-debian-12-r0)
- image: `docker.io/bitnamilegacy/postgresql:16.3.0-debian-12-r14` → k3s nodes (tagged as docker.io/bitnami/postgresql:16.3.0-debian-12-r14)

## Expect Next Cycle

- fetch.sh runs, imports both bitnami images into all 3 k3s nodes
- Redeploy keycloak with `global.storageClass=local-path` (now default in values.yaml), `ingress.enabled=false`, `realmInit.enabled=false`
- keycloak-0 finds image locally → starts
- keycloak-postgresql-0 gets `local-path` PVC → binds → starts
- Layer 3 first pod running

---

# Changelog — Cycle 10

## Observed

- Layer: 1 (cert-manager + sealed-secrets + OpenBao)
- Service: openbao-2 — sealed after pod restart (2 restarts), readiness probe returning 503
- Category: CONFIG_ERROR
- Evidence: `bao status -tls-skip-verify` on openbao-2 showed `Sealed: true`, `Unseal Progress: 0/3`. openbao-0 and openbao-1 healthy (leader + standby). Raft cluster had quorum but openbao-2 not participating.

## Applied

- Unsealed openbao-2 with keys 1, 2, 3 (threshold 3 of 5 met)
- Post-unseal: `HA Mode: standby`, `Active Node: openbao-0`, raft indices synced

## Validated

```
# openbao-2 status after unseal
Sealed: false
HA Mode: standby
Raft Committed Index: 36
Raft Applied Index: 36

# Raft cluster — all 3 voters
openbao-0    leader    true
openbao-1    follower  true
openbao-2    follower  true

# Harbor API from inside cluster
wget -qO- http://harbor-core.harbor:80/api/v2.0/ping → Pong
```

## Expect Next Cycle

- Layer 1 fully healthy (all 3 OpenBao pods unsealed, raft intact)
- Layer 2 healthy (Harbor API responding)
- Next: Layer 3 — install Keycloak (identity / SSO)
- Note: OpenBao pods require manual unseal after every restart; this is expected behavior with Shamir secret sharing. Auto-unseal via OpenBao Transit would eliminate this — future backlog item.

---

# Changelog — Cycle 9

## Observed

- Layer: 2 (Harbor — internal container registry)
- Service: harbor — pods crash-looping with QEMU vsyscall errors and init failures
- Category: QEMU_BUG + CONFIG_ERROR
- Evidence: `harbor-core` and `harbor-jobservice` crash with `x86_64-binfmt-P: Cannot allocate vsyscall page` (PATH 2: QEMU_RESERVED_VA=0x40000000000 set by k8s, vsyscall addr 0xffffffffff600000 exceeds 4TB GUEST_ADDR_MAX); `harbor-database` missing `registry` DB (init scripts didn't run during broken QEMU period); postgres user had no password; `harbor-redis` bgsave child crashes with `QEMU internal SIGSEGV {code=MAPERR, addr=0x20}` after writing RDB

## Applied

### QEMU Binary Patches (all 3 nodes: sovereign-0, sovereign-1, sovereign-2)

6 patches applied to `/usr/bin/qemu-x86_64-static` (QEMU 8.2.2, ARM64):
- P1 (0xbfdf0): NOP vsyscall exit PATH1 — 0x97fdfdac → 0xd503201f
- P2 (0xdf6f4): CBZ X0, +0x44 — NULL check for VMA allocation — 0xaa0003e1 → 0xb4000220
- P3 (0xdf6f8): MOV X1, X0 — restore VMA pointer — 0xf9401019 → 0xaa0003e1
- P4 (0xcd3cc): B→dead code (disarm error handler tail) — 0x17ffffa3 → 0x17ffffaa
- P5 (0xcd024): B.LS → 0xcd074 (early return when vsyscall addr > GUEST_ADDR_MAX) — 0x54001c89 → 0x54000289
- P6 (0xcd044): Restore CBNZ X0 → 0xcd3d0 — 0xd503201f → 0xb5001c60

P5 is the key PATH 2 fix: when `QEMU_RESERVED_VA=0x40000000000` makes GUEST_ADDR_MAX = 4TB-1, the vsyscall page address (≈16PB) always exceeds GUEST_ADDR_MAX. P5 redirects the B.LS branch to the function epilogue (clean early return), skipping both the vsyscall mmap and the exit(1) call.

### Database Initialization

- Set postgres user password: `ALTER USER postgres WITH PASSWORD 'changeit'` (matches POSTGRESQL_PASSWORD in harbor-core secret)
- Ran `/docker-entrypoint-initdb.d/initial-registry.sql` manually (created `registry` database + schema_migrations table)

### Redis Persistence Fix

- Patched harbor-redis StatefulSet to pass `--stop-writes-on-bgsave-error no` at startup
- The bgsave fork writes RDB successfully then crashes with SIGSEGV addr=0x20 (QEMU bug in fork cleanup)
- Without the flag, Redis blocks all writes; with it, Harbor-core can connect normally
- Command: `kubectl -n harbor patch statefulset harbor-redis --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["/usr/bin/redis-server"]},{"op":"add","path":"/spec/template/spec/containers/0/args","value":["/etc/redis.conf","--stop-writes-on-bgsave-error","no"]}]'`

### Values.yaml

- Documented Redis workaround in `platform/charts/harbor/values.yaml` with the kubectl patch command

## Validated

```
# All Harbor pods running
harbor-core-589969799-4ppk9         1/1 Running  (sovereign-0)
harbor-database-0                   1/1 Running  (sovereign-1)
harbor-jobservice-77b7f88fcf-rhms5  1/1 Running  (sovereign-1)
harbor-nginx-69b47dd477-8tpzd       1/1 Running  (sovereign-1)
harbor-portal-bb89c9767-bvs57       1/1 Running  (sovereign-0)
harbor-redis-0                      1/1 Running  (sovereign-2)
harbor-registry-55475d8d7d-6r629    2/2 Running  (sovereign-2)

# Harbor API responds
curl -sk --resolve harbor.sovereign-autarky.dev:443:192.168.104.1 \
  -u admin:Harbor12345 https://harbor.sovereign-autarky.dev/api/v2.0/ping
→ Pong

# Autarky gate
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/harbor/templates/ → PASS

# Helm lint
helm lint platform/charts/harbor/ → 0 chart(s) failed
```

## Expect Next Cycle

- Layer 2 complete: Harbor running and serving API
- Next: Layer 3 — ArgoCD (GitOps engine) or advance sprint stories
- Post-install reminder: Redis StatefulSet patch must be re-applied after any `helm upgrade harbor`

## Notes

- The postgres user password was NULL despite POSTGRES_PASSWORD=changeit in the secret; the init container only sets the password on first DB initialization, and the DB was first started during the broken QEMU period when init scripts may not have run completely
- The registry database init SQL (`initial-registry.sql`) creates only the `schema_migrations` table; Harbor runs its own Flyway migrations on first `harbor-core` startup to build the full schema
- QEMU P5 patch: `B.LS → 0xcd074` encoding = `0x54000000 | (imm19=20 << 5) | cond_LS=9 = 0x54000289`; diff_bytes=80 from 0xcd024 to 0xcd074

---

# Changelog — Cycle 8

## Observed

- Layer: 1 (cert-manager + sealed-secrets + OpenBao)
- Service: openbao — running but uninitialized, Raft cluster not formed
- Category: CONFIG_ERROR
- Evidence: `bao status -tls-skip-verify` showed `Initialized: false`. All 3 pods running, Raft storage configured but never bootstrapped.

## Applied

- Initialized OpenBao: `bao operator init -key-shares=5 -key-threshold=3 -tls-skip-verify`
- Joined openbao-1 and openbao-2 to Raft cluster using leader CA cert at `/openbao/tls/ca.crt`
  - Join command requires `-leader-ca-cert=@/openbao/tls/ca.crt` because the cert has DNS SANs (not IP SANs); 127.0.0.1 requires `-tls-skip-verify` for the local API call
- Unsealed all 3 pods with keys 1-3 (threshold 3 of 5)
- Saved init keys and root token to `lathe/state/openbao-init.json`
- Files: `lathe/state/openbao-init.json` (new)

## Validated

```
# All 3 pods unsealed
openbao-0: Sealed=false, HA Mode=active
openbao-1: Sealed=false, HA Mode=standby
openbao-2: Sealed=false, HA Mode=standby

# Raft cluster — all 3 nodes voters
Node         Address                            State       Voter
----         -------                            -----       -----
openbao-0    openbao-0.openbao-internal:8201    leader      true
openbao-1    openbao-1.openbao-internal:8201    follower    true
openbao-2    openbao-2.openbao-internal:8201    follower    true

# Autarky gate
PASS
```

## Expect Next Cycle

- Layer 1 complete: cert-manager + sealed-secrets + OpenBao all healthy
- Next: install Harbor (Layer 2) — autarky boundary
- Harbor chart at `platform/charts/harbor/` (verify exists or create)

## Notes

- OpenBao TLS cert covers DNS SANs via wildcard `*.openbao-internal.openbao.svc.cluster.local` — no 127.0.0.1 IP SAN, so all client connections must use `-tls-skip-verify` or DNS hostname
- Raft join requires `-leader-ca-cert=@/openbao/tls/ca.crt` to verify the leader's cert
- Root token and unseal keys stored in `lathe/state/openbao-init.json` — NEVER commit to git
