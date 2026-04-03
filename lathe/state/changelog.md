# Changelog — Cycle 24

## Observed

- Layer: 2 (Harbor — internal registry / autarky boundary)
- Service: harbor
- Category: DEPENDENCY_MISSING — Harbor not yet installed; Layer 3 (Keycloak) is healthy but Layer 2 was skipped
- Evidence: `helm list -A` showed no harbor release; Layer 3 complete, Layer 2 gap

## Applied

- Installed harbor chart (goharbor/harbor 1.15.0 wrapper) into harbor namespace
- All Harbor sub-components applied: core, portal, registry, jobservice, nginx, database, redis
- Images pulled from docker.io/goharbor (bootstrap window — acceptable pre-Harbor)
- Files: `platform/charts/harbor/` (no changes needed, chart was ready)

## Validated

```
helm lint platform/charts/harbor/
→ 1 chart(s) linted, 0 chart(s) failed

helm upgrade --install harbor platform/charts/harbor/ -n harbor --create-namespace
→ STATUS: deployed, REVISION: 1, Install complete

kubectl get events -n harbor (immediate post-install):
→ PVCs: all provisioned successfully (local-path)
→ Images: goharbor/nginx-photon:v2.11.0 already present on machine
→ Images: goharbor/harbor-portal:v2.11.0 pulled (5.2s)
→ Images: goharbor/harbor-jobservice:v2.11.0 already present on machine
→ harbor-nginx pod: Started container nginx

autarky gate (all chart templates):
→ PASS
```

## Expect Next Cycle

Harbor pods should be Running or close to it. Expect:
- harbor-nginx, harbor-portal, harbor-core, harbor-jobservice, harbor-registry, harbor-database, harbor-redis to reach Running
- harbor-nginx readiness (502 at install time — waiting for core/portal to be ready)
- If harbor-database is slow (QEMU emulation), may need readinessProbe timeout increase (already set to 10s in values.yaml)
- Once Harbor is Running, configure k3s registry mirrors to point nodes at harbor.sovereign-autarky.dev and advance to Layer 4 (Forgejo + ArgoCD)
