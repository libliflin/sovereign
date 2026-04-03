# Changelog — Cycle 40

## Observed
- Layer: 6 (Falco — runtime security)
- Service: falco (falcoctl-artifact-follow sidecar)
- Category: CONFIG_ERROR (sidecar attempting external network call; crashes in sovereign environment)
- Evidence:
  - `falco-r9www`: CrashLoopBackOff (5 restarts); `falco-5sph2`, `falco-rsxbc`: Running but BackOff events on falcoctl-artifact-follow sidecar
  - Events: `Back-off restarting failed container falcoctl-artifact-follow` on 2/3 pods
  - Root cause: falcoctl-artifact-follow sidecar polls `https://falcosecurity.github.io/falcoctl/index.yaml` (external) every 168h to pull updated rule files — external call fails in sovereign cluster
  - Secondary: Backstage (Layer 7) pod CrashLoopBackOff: `connect ECONNREFUSED ::1:5432` — no PostgreSQL deployed; helm release in `failed` state; will be addressed next cycle

## Applied
- Disabled `falcoctl.artifact.follow.enabled: false` in `platform/charts/falco/values.yaml`
- Rules already installed at pod startup by `falcoctl-artifact-install` init container; live-update sidecar not needed and violates T1 (external hub dependency)
- Upgraded falco (revision 3 → 4); all 3 DaemonSet pods now 1/1 Running, 0 restarts
- Files: `platform/charts/falco/values.yaml`

## Validated
```
helm lint platform/charts/falco/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
grep -rn "docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io" platform/charts/falco/templates/
→ PASS

helm upgrade falco platform/charts/falco/ -n falco --timeout 90s --wait
→ Release "falco" has been upgraded. STATUS: deployed REVISION: 4

kubectl get pods -n falco
→ falco-cfsgn   1/1   Running   0   65s
→ falco-gkn8h   1/1   Running   0   71s
→ falco-jbt2l   1/1   Running   0   83s
```

## Expect Next Cycle
- Falco: 3/3 DaemonSet pods remain 1/1 Running, no sidecar crashes
- Layer 6 fully healthy: Istio ✓ OPA-Gatekeeper ✓ Falco ✓ Trivy ✓
- Backstage: needs PostgreSQL — will deploy postgresql subchart dependency or StatefulSet in backstage namespace
- Fix: add PostgreSQL subchart to `platform/charts/backstage/Chart.yaml` + configure `APP_CONFIG_backend_database_*` env vars in deployment
