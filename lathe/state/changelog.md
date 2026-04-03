# Changelog — Cycle 20

## Observed

- Layer: 2 (internal registry — autarky boundary)
- Service: Zot — running but acting as a plain OCI registry; pull-through proxy not enabled
- Category: CONFIG_ERROR — Zot had no sync/onDemand configuration; the autarky boundary was structurally incomplete (Zot couldn't serve as a transparent cache for upstream registries)
- Evidence: Zot configmap had no `sync` extension; k3s nodes still pulled directly from external registries; Zot was effectively unused

## Applied

- Enabled Zot `sync` extension with `onDemand: true` for 5 upstream registries: ghcr.io, registry-1.docker.io, quay.io, gcr.io, registry.k8s.io
- Fixed deployment update strategy from `RollingUpdate` (maxUnavailable:0, maxSurge:1) to `Recreate` — RollingUpdate caused a boltdb deadlock on the ReadWriteOnce PVC: new pod couldn't acquire `cache.db` lock while old pod was still running
- Files: `platform/charts/zot/values.yaml`, `platform/charts/zot/templates/configmap.yaml`, `platform/charts/zot/templates/deployment.yaml`

## Validated

```
# Helm lint
helm lint platform/charts/zot/
→ 1 chart(s) linted, 0 chart(s) failed

# Autarky gate
grep -rn "docker.io|quay.io|ghcr.io|gcr.io|registry.k8s.io" platform/charts/*/templates/
→ PASS

# Pod status
kubectl get pods -n zot
→ zot-756c7b788b-m5w5w   1/1   Running   0   (after Recreate)

# OCI v2 API
wget -S -qO- http://zot.zot.svc.cluster.local:5000/v2/
→ HTTP/1.1 200 OK
→ Docker-Distribution-Api-Version: registry/2.0
```

## Expect Next Cycle

Zot is now a pull-through proxy. Next cycle:
1. Configure k3s registry mirrors on all 3 nodes (`/etc/rancher/k3s/registries.yaml`) to route external pulls through Zot:
   - `ghcr.io` → `http://zot.zot.svc.cluster.local:5000`
   - `docker.io` → `http://zot.zot.svc.cluster.local:5000`
   - `quay.io` → `http://zot.zot.svc.cluster.local:5000`
   - `gcr.io` → `http://zot.zot.svc.cluster.local:5000`
   - `registry.k8s.io` → `http://zot.zot.svc.cluster.local:5000`
2. Restart k3s on each node after writing registries.yaml
3. Verify a new pod pull goes through Zot (check Zot logs for a sync hit)

Note: k3s registry mirrors can't reach Zot by its cluster DNS name from the node level — will need to use the ClusterIP (`10.43.32.173:5000`) or set up a NodePort/HostNetwork service for Zot so it's reachable from the host network the nodes use.
