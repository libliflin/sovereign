# Changelog — Cycle 19

## Observed

- Layer: 2 (internal registry — autarky boundary)
- Service: Harbor → blocked (amd64-only images, QEMU SIGSEGV on arm64 Lima VMs)
- Category: IMAGE_ISSUE — Harbor has no arm64 images; replaced with Zot (CNCF, Apache 2.0, multi-arch)
- Evidence (from cycle 18): `QEMU internal SIGSEGV {code=MAPERR, addr=0x20}` on harbor-core, harbor-jobservice; Docker Hub API confirmed every Harbor tag v2.11.0–v2.14.3 is amd64-only

## Applied

- Created `platform/charts/zot/` — first-party Helm chart for Zot OCI registry (CNCF Sandbox, Apache 2.0, arm64-native)
- Chart files: `Chart.yaml`, `values.yaml`, `templates/_helpers.tpl`, `templates/configmap.yaml`, `templates/deployment.yaml`, `templates/service.yaml`, `templates/pvc.yaml`, `templates/pdb.yaml`
- Deployed `helm upgrade --install zot platform/charts/zot/ -n zot --create-namespace`
- Zot pod Running 1/1, PVC bound (local-path 20Gi), Service ClusterIP 10.43.32.173:5000
- Verified: `GET http://zot.zot.svc.cluster.local:5000/v2/ → HTTP 200 OK, Docker-Distribution-Api-Version: registry/2.0`

## Validated

```
# Helm lint
helm lint platform/charts/zot/
→ 1 chart(s) linted, 0 chart(s) failed

# Autarky gate (no external registries in templates)
grep -rn "docker.io|quay.io|ghcr.io|gcr.io|registry.k8s.io" platform/charts/*/templates/
→ PASS

# Zot running
kubectl get pods -n zot
→ zot-9785c7865-nntqg   1/1   Running   0

# OCI v2 API
wget -S -qO- http://zot.zot.svc.cluster.local:5000/v2/
→ HTTP/1.1 200 OK
→ Docker-Distribution-Api-Version: registry/2.0
```

## Expect Next Cycle

Layer 2 is now live. Next cycle should:
1. Configure k3s registry mirrors on all 3 nodes to route pulls through Zot (`/etc/rancher/k3s/registries.yaml`)
2. Push Layer 1 images (cert-manager, sealed-secrets, openbao) into Zot so subsequent chart upgrades can use `global.imageRegistry`
3. Begin populating Zot with Layer 3+ images via downloads.json queue

Zot endpoint (in-cluster): `http://zot.zot.svc.cluster.local:5000`
