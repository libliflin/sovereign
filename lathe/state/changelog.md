# Changelog — Cycle 28

## Observed
- Layer: 5 (Observability — Prometheus)
- Service: prometheus-stack (not yet deployed)
- Category: CONFIG_ERROR
- Evidence: `values.yaml` specified `storageClassName: standard` and `storage: 50Gi`, but only `local-path` StorageClass exists in the cluster; 50Gi exceeds each node's 30GiB disk

## Applied
- Fixed `storageClassName: standard` → `local-path` and `storage: 50Gi` → `5Gi` in `platform/charts/prometheus-stack/values.yaml`
- Installed prometheus-stack: `helm upgrade --install prometheus-stack platform/charts/prometheus-stack/ -n monitoring --create-namespace --timeout 120s --wait`
- Files: `platform/charts/prometheus-stack/values.yaml`

## Validated
```
helm lint platform/charts/prometheus-stack/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
→ PASS

helm upgrade --install prometheus-stack ... --timeout 120s --wait
→ Release "prometheus-stack" installed, REVISION: 1, STATUS: deployed

kubectl get pods -n monitoring:
→ alertmanager-prometheus-stack-kube-prom-alertmanager-0   1/2  Running         0  24s
→ alertmanager-prometheus-stack-kube-prom-alertmanager-1   1/2  Running         0  24s
→ prometheus-prometheus-stack-kube-prom-prometheus-0       0/2  PodInitializing 0  24s
→ prometheus-prometheus-stack-kube-prom-prometheus-1       0/2  PodInitializing 0  24s
→ prometheus-stack-kube-prom-operator-75475b9946-sdxc9     1/1  Running         0  33s
→ prometheus-stack-kube-state-metrics-64f5fccf6d-jnrcv     1/1  Running         0  33s
→ prometheus-stack-prometheus-node-exporter-bpssm          1/1  Running         0  33s
→ prometheus-stack-prometheus-node-exporter-f7b9d          1/1  Running         0  33s
→ prometheus-stack-prometheus-node-exporter-sf9jc          1/1  Running         0  33s
```

## Expect Next Cycle
- Prometheus and Alertmanager pods finish initializing and reach Running state
- Next: install VictoriaLogs (Layer 5 log aggregation)
