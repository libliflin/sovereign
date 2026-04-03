# Changelog — Cycle 17

## Observed

- Layer: 1 (cert-manager + sealed-secrets + OpenBao — PKI + secrets)
- Service: OpenBao — all 3 pods Running but uninitialized (fresh cluster rebuild from cycle 16)
- Category: CONFIG_ERROR — OpenBao requires explicit `bao operator init` + unseal after every cluster creation
- Evidence: `bao status` → `Initialized: false`, `Sealed: true`

## Applied

- Initialized OpenBao: `bao operator init -key-shares=5 -key-threshold=3 -tls-skip-verify` on openbao-0
- Saved unseal keys + root token to `lathe/state/openbao-keys.json`
- Unsealed openbao-0 (3 of 5 keys) → became raft leader
- Joined openbao-1 and openbao-2 to raft cluster, unsealed both
- Files: `lathe/state/openbao-keys.json`, `lathe/state/history.sh`, `lathe/state/changelog.md`

## Validated

```
# openbao-0 status
bao status -tls-skip-verify
→ Initialized: true, Sealed: false, HA Mode: active

# raft peers
bao operator raft list-peers -tls-skip-verify
→ openbao-0  leader   voter: true
→ openbao-1  follower voter: true
→ openbao-2  follower voter: true

# pod status
kubectl get pods -n openbao
→ openbao-0  1/1  Running  0
→ openbao-1  1/1  Running  0
→ openbao-2  1/1  Running  0

# autarky gate
grep -rn "docker.io|quay.io|..." platform/charts/*/templates/
→ PASS
```

## Expect Next Cycle

- Layer 1 complete: cert-manager, sealed-secrets, OpenBao all healthy
- Next: deploy Harbor (Layer 2) — subchart already present at platform/charts/harbor/charts/harbor-1.15.0.tgz
- Harbor will need storageClass override (local-path) and may need to create harbor namespace + admin secret
- goharbor images will pull from external during bootstrap window (pre-autarky, acceptable)
