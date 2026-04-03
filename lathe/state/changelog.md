# Changelog — Cycle 43

## Observed
- Layer: 1 (OpenBao — PKI + secrets)
- Service: openbao-0
- Category: CONFIG_ERROR
- Evidence: `openbao-0` was `0/1 Running` with 807 failed readiness probes over 66 minutes — `bao status` confirmed `Sealed: true`. Pod had restarted at ~18:09 EDT; openbao-1 and openbao-2 remained unsealed and healthy. Readiness probe (`/v1/sys/health?standbyok=true&sealedok=true&uninitcode=200` via HTTPS) returned 503 despite `sealedok=true` — OpenBao 2.5.x does not appear to honor `sealedok` in the sealed+raft-joining state.

## Applied
- Manually unsealed openbao-0 using stored Shamir keys (3 of 5 threshold) from `lathe/state/openbao-keys.json`
- Commands: `kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY1/2/3>`
- Files: none (operational action, no chart changes)

## Validated
```
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY3>
→ Sealed: false, HA Mode: standby, Raft Committed Index: 36

kubectl get pods -n openbao
→ openbao-0  1/1  Running  0  6h57m
→ openbao-1  1/1  Running  0  13h
→ openbao-2  1/1  Running  0  13h
```

## Operational Note
OpenBao with Shamir unseal requires manual intervention after every pod restart. The
readiness probe's `sealedok=true` parameter does not prevent 503 responses in OpenBao
2.5.2 when a node is sealed — the probe correctly marks the pod not-ready, which is
actually correct behavior (sealed nodes should not serve traffic). The manual unseal
procedure is: `bao operator unseal -tls-skip-verify <KEY>` × 3 using keys from
`lathe/state/openbao-keys.json`.

Future work: add a Kubernetes-native unseal operator or configure transit auto-unseal
to eliminate this manual step.

## Expect Next Cycle
- openbao-0 stays 1/1 Running (no further restarts expected)
- All Layer 1 services healthy: cert-manager, sealed-secrets, openbao ×3
- Backstage pod with 4 restarts (Layer 7) is the next candidate if it's still restarting
