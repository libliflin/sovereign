# Changelog — Cycle 15

## Observed

- Layer: 1 (cert-manager + sealed-secrets + OpenBao — PKI + secrets)
- Service: sealed-secrets — not installed; previous cycle installed cert-manager, sealed-secrets is next in layer order
- Category: DEPENDENCY_MISSING (fresh cluster rebuild, Layer 1 components installing sequentially)
- Evidence: `helm list -A` showed cert-manager deployed, no sealed-secrets, no openbao

## Applied

- Added sealed-secrets helm repo: `helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets`
- Installed sealed-secrets v2.18.4 (controller v0.36.1) in kube-system namespace with fullnameOverride=sealed-secrets-controller
- `helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets -n kube-system --set fullnameOverride=sealed-secrets-controller --timeout 90s --wait`
- Files: `lathe/state/history.sh`

## Validated

```
# sealed-secrets pod
kubectl get pods -n kube-system | grep sealed
→ sealed-secrets-controller-6485f65cbc-945zk   1/1   Running   0   9s

# Autarky gate
grep -rn "docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io" platform/charts/*/templates/
→ PASS
```

## Expect Next Cycle

- sealed-secrets-controller 1/1 Running (stable)
- Next: install OpenBao (Layer 1, third component) — requires cert-manager CRDs for Certificate resource
