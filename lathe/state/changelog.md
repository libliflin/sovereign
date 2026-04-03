# Changelog — Cycle 30

## Observed
- Layer: 5 (Observability — Jaeger)
- Service: jaeger (not yet deployed)
- Category: CONFIG_ERROR (multiple)
- Evidence:
  1. `values.yaml` had `storageClass: "standard"` — only `local-path` exists
  2. `templates/ingress.yaml` had `ingressClassName: nginx` and nginx-specific annotation — only traefik IngressClass exists
  3. `storage.badger.ephemeral: false` with `persistence.enabled: true` — upstream chart 3.4.1 does NOT mount a PVC for collector/query deployments; resulted in `mkdir /mnt/data: permission denied` crash on first install attempt

## Applied
- Fixed `storageClass: "standard"` → `"local-path"` in global values
- Fixed `storageClass: "standard"`, `size: "20Gi"` → `"local-path"`, `"5Gi"` in badger persistence block
- Fixed `ingressClassName: nginx` → `ingressClassName: traefik`; removed `nginx.ingress.kubernetes.io/proxy-read-timeout` annotation
- Fixed `storage.badger.ephemeral: false` → `true` (upstream chart doesn't mount a PVC for collector/query; ephemeral uses emptyDir, appropriate for dev environment per chart comment)
- Uninstalled cancelled first release; reinstalled with corrected values
- Files: `platform/charts/jaeger/values.yaml`, `platform/charts/jaeger/templates/ingress.yaml`

## Validated
```
helm lint platform/charts/jaeger/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
→ PASS

helm upgrade --install jaeger ... --timeout 120s --wait
→ Release "jaeger" installed, REVISION: 1, STATUS: deployed

kubectl get pods -n jaeger:
→ jaeger-agent-h9mm5                  1/1  Running  0  15s
→ jaeger-agent-p8jbk                  1/1  Running  0  15s
→ jaeger-agent-tvgnw                  1/1  Running  0  15s
→ jaeger-collector-6bdbcc88f7-999tj   1/1  Running  0  15s
→ jaeger-collector-6bdbcc88f7-hhtn9   1/1  Running  0  15s
→ jaeger-query-67dc77cfcc-6hhwn       2/2  Running  0  15s
→ jaeger-query-67dc77cfcc-dbmq7       2/2  Running  0  15s
```

## Expect Next Cycle
- Jaeger remains Running (all pods healthy)
- Layer 5 now has: Prometheus ✓, VictoriaLogs ✓, Jaeger ✓
- Next: Layer 5 still has Perses (dashboards) and Thanos (long-term retention) — check which is next, then Layer 6 (Istio, OPA-Gatekeeper, Falco, Trivy)
