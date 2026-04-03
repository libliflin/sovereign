# Changelog — Cycle 29

## Observed
- Layer: 5 (Observability — VictoriaLogs)
- Service: victorialogs (not yet deployed)
- Category: CONFIG_ERROR
- Evidence: `values.yaml` had `storageClass: "standard"` and `size: "50Gi"` — same pattern as prometheus-stack in cycle 28; only `local-path` StorageClass exists and 50Gi exceeds node disk

## Applied
- Fixed `storageClass: "standard"` → `"local-path"` (global and persistentVolume) and `size: "50Gi"` → `"5Gi"` in `platform/charts/victorialogs/values.yaml`
- Installed victorialogs: `helm upgrade --install victorialogs platform/charts/victorialogs/ -n monitoring --create-namespace --timeout 90s --wait`
- Files: `platform/charts/victorialogs/values.yaml`

## Validated
```
helm lint platform/charts/victorialogs/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
→ PASS

helm upgrade --install victorialogs ... --timeout 90s --wait
→ Release "victorialogs" installed, REVISION: 1, STATUS: deployed

kubectl get pods -n monitoring:
→ alertmanager-prometheus-stack-kube-prom-alertmanager-0   2/2  Running  0  2m11s
→ alertmanager-prometheus-stack-kube-prom-alertmanager-1   2/2  Running  0  2m11s
→ prometheus-prometheus-stack-kube-prom-prometheus-0       2/2  Running  0  2m11s
→ prometheus-prometheus-stack-kube-prom-prometheus-1       2/2  Running  0  2m11s
→ prometheus-stack-kube-prom-operator-75475b9946-sdxc9     1/1  Running  0  2m20s
→ prometheus-stack-kube-state-metrics-64f5fccf6d-jnrcv     1/1  Running  0  2m20s
→ prometheus-stack-prometheus-node-exporter-bpssm          1/1  Running  0  2m20s
→ prometheus-stack-prometheus-node-exporter-f7b9d          1/1  Running  0  2m20s
→ prometheus-stack-prometheus-node-exporter-sf9jc          1/1  Running  0  2m20s
→ victorialogs-server-0                                    1/1  Running  0  33s
```

## Expect Next Cycle
- VictoriaLogs remains Running
- Next: install Jaeger (Layer 5 distributed tracing)
