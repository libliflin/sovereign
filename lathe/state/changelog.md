# Changelog — Cycle 16

## Observed

- Layer: 1 (cert-manager + sealed-secrets + OpenBao — PKI + secrets)
- Service: OpenBao — not installed; cert-manager running but no ClusterIssuers existed (fresh cluster rebuild), blocking OpenBao's Certificate resource
- Category: DEPENDENCY_MISSING — sovereign-ca-issuer ClusterIssuer absent; OpenBao certificate.yaml requires it
- Evidence: `kubectl get clusterissuers` → No resources found; OpenBao chart templates/certificate.yaml references `sovereign-ca-issuer`

## Applied

- Bootstrapped cert-manager CA: applied `selfsigned-issuer` ClusterIssuer → `sovereign-ca` Certificate (10yr CA) → `sovereign-ca-issuer` ClusterIssuer
- Installed OpenBao v2.5.2 in HA Raft mode (3 replicas) with `--set global.storageClass=local-path` (ceph-block not yet available)
- Files: `lathe/state/history.sh`, `lathe/state/changelog.md`

## Validated

```
# helm lint
helm lint platform/charts/openbao/
→ 1 chart(s) linted, 0 chart(s) failed

# ClusterIssuers
kubectl get clusterissuers
→ selfsigned-issuer     True
→ sovereign-ca-issuer   True

# TLS cert issued
kubectl get certificate -n openbao
→ openbao-server-tls   True   openbao-server-tls

# Pods
kubectl get pods -n openbao
→ openbao-0   1/1   Running
→ openbao-1   0/1   Running  (starting)

# Autarky gate
grep -rn "docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io" platform/charts/*/templates/
→ PASS
```

## Expect Next Cycle

- openbao-0, openbao-1, openbao-2 all Running (image pull completes across nodes)
- OpenBao needs initialization: `bao operator init` + unseal (3-of-5 keys) on each pod
- Next: initialize and unseal OpenBao to complete Layer 1
