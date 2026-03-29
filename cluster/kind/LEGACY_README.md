# Sovereign Kind Cluster

Local Kubernetes clusters for integration testing. Free, reproducible, no cloud costs.

## Quick start

```bash
# Start Docker Desktop first — the whale icon in your menu bar must be solid (not animating)

# Create single-node cluster (fast, ~1.5GB RAM):
./kind/setup.sh

# Verify it worked:
./kind/setup.sh --status

# Destroy when done:
./kind/setup.sh --destroy
```

## Cluster types

| Config | Nodes | RAM needed | Use for |
|--------|-------|-----------|---------|
| `sovereign-single` | 1 | ~2GB | Chart smoke tests, fast CI |
| `sovereign-ha` | 3 | ~6GB+ | HA/PDB validation, chaos tests |

## Docker Desktop memory settings

With 7.6GB allocated (default), the single-node cluster works fine.
For the HA cluster you need more:

1. Docker Desktop → Settings → Resources → Memory
2. Set to **10GB minimum** (12GB recommended for HA + full stack tests)
3. Apply & Restart

## Known chart namespaces

Some upstream charts hardcode their expected namespace. Install into these:

| Chart | Required namespace |
|-------|--------------------|
| sealed-secrets | `sealed-secrets` |
| cert-manager | `cert-manager` |
| crossplane | `crossplane-system` |
| argocd | `argocd` |
| vault | `vault` |
| keycloak | `keycloak` |

Example:
```bash
helm install sealed-secrets charts/sealed-secrets/ \
  --namespace sealed-secrets --create-namespace \
  --kube-context kind-sovereign-test
```

## What's installed by setup.sh

1. **kind cluster** — `sovereign-test` (single) or `sovereign-ha` (3-node)
2. **Cilium CNI** — installed via helm after cluster creation (not during, since `--wait`
   times out when CNI is disabled)
3. **local-path storage** — `storageclass.storage.k8s.io/local-path` (default)
   Substitute for Rook/Ceph in CI. HostPath-backed PVCs, not production-grade.

## Cilium note

The kind configs set `disableDefaultCNI: true` and `kubeProxyMode: none`.
This means:
- `kind create cluster --wait` will always time out — nodes stay NotReady until Cilium
  is installed. `setup.sh` handles this by NOT passing `--wait` to kind.
- If you create the cluster manually, install Cilium before checking node status.

## CI usage

The GitHub Actions `chart-integration` job (story 2I-005) uses sovereign-single
to smoke-test charts on every PR. The cluster is created, charts installed, and
the cluster destroyed in a `cleanup: always()` step.

Cloud APIs (Hetzner, AWS, DigitalOcean) are **never called in CI**.
Bootstrap scripts are validated statically only (shellcheck + syntax).
Live cloud testing is manual: `./bootstrap/bootstrap.sh --confirm-charges`
