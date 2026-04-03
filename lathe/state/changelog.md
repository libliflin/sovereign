# Changelog — Cycle 39

## Observed
- Layer: 7 (Backstage, mailpit — developer experience)
- Service: backstage (first Layer 7 component — not yet deployed)
- Category: CONFIG_ERROR (multiple values blocking install; chart never deployed)
- Evidence:
  - No `backstage` helm release; no `backstage` namespace in snapshot
  - `values.yaml` had `storageClass: "ceph-block"`, `image.tag: "latest"`, `ingress.className: "nginx"`, `cert-manager.io/cluster-issuer: "letsencrypt-prod"`
  - OPA `no-privilege-escalation` constraint (enforcing `allowPrivilegeEscalation: false` on Pods) blocked pod creation: `[no-privilege-escalation] Container backstage must explicitly set allowPrivilegeEscalation: false`
  - OPA `require-labels` constraint required `app` and `tier` on Deployment metadata (backstage template lacked them)
  - Available issuers: `selfsigned-issuer`, `sovereign-ca-issuer` (no letsencrypt)
  - Confirmed `ghcr.io/backstage/backstage:1.30.2` exists (queried ghcr.io tags list from sovereign-0)
  - k3s registry mirrors route `ghcr.io` through Zot (10.43.32.173:5000) on-demand

## Applied
- Fixed `global.storageClass`: `"ceph-block"` → `"local-path"` in `platform/charts/backstage/values.yaml`
- Fixed `image.tag`: `"latest"` → `"1.30.2"` (confirmed available at ghcr.io)
- Fixed `ingress.className`: `"nginx"` → `"traefik"`
- Fixed `ingress.annotations`: removed nginx annotation, changed issuer to `"sovereign-ca-issuer"`
- Added `app: backstage` and `tier: devex` labels to Deployment metadata in `deployment.yaml`
- Added `securityContext.allowPrivilegeEscalation: false` to backstage container in `deployment.yaml`
- Installed backstage (revision 1→2); namespace created, ingress/cert/PDB/svc provisioned; pod in ContainerCreating (image pulling through Zot from ghcr.io)
- Files: `platform/charts/backstage/values.yaml`, `platform/charts/backstage/templates/deployment.yaml`

## Validated
```
helm lint platform/charts/backstage/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate (templates):
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/backstage/templates/
→ PASS

helm template ... | grep -E "app:|tier:|PodDisruptionBudget|podAntiAffinity"
→ kind: PodDisruptionBudget ✓
→ app: backstage ✓
→ tier: devex ✓
→ podAntiAffinity ✓

helm upgrade backstage ... --timeout 90s --wait
→ timed out at 90s (image still pulling through Zot from ghcr.io — expected for first pull)
→ backstage-5d64db89b9-m6kpv: ContainerCreating on lima-sovereign-2
→ Certificate issued by sovereign-ca-issuer ✓
→ Ingress provisioned at backstage.sovereign-autarky.dev ✓
```

## Expect Next Cycle
- backstage image (`ghcr.io/backstage/backstage:1.30.2`, ~1GB+) fully cached in Zot
- Pod(s) Running; second replica created once first becomes Ready (rolling update: maxSurge=1, maxUnavailable=0)
- `helm upgrade backstage ...` succeeds with 2/2 replicas Ready
- Layer 7 partial: backstage up, mailpit next
