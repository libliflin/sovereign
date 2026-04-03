# Changelog — Cycle 27

## Observed
- Layer: 4 (ArgoCD — GitOps)
- Service: argocd
- Category: CONFIG_ERROR
- Evidence: `ingress.yaml` specified `ingressClassName: nginx` but only `traefik` IngressClass exists in the cluster; would have caused Ingress to be ignored

## Applied
- Fixed `ingressClassName: nginx` → `ingressClassName: traefik` in `platform/charts/argocd/templates/ingress.yaml`; removed nginx-specific annotations
- Installed ArgoCD: `helm upgrade --install argocd platform/charts/argocd/ -n argocd --create-namespace --timeout 120s --wait`
- Files: `platform/charts/argocd/templates/ingress.yaml`

## Validated
```
helm lint platform/charts/argocd/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
→ PASS

helm upgrade --install argocd ... --timeout 120s --wait
→ Release "argocd" installed, REVISION: 1, STATUS: deployed

kubectl get pods -n argocd:
→ argocd-application-controller-0                     1/1 Running  0  46s
→ argocd-applicationset-controller-7578ddc89b-wdn5b   1/1 Running  0  46s
→ argocd-dex-server-567c57d876-jm2hp                  1/1 Running  0  46s
→ argocd-notifications-controller-cc6794c8b-z2zw7     1/1 Running  0  46s
→ argocd-redis-7d54cffc56-dxb6b                       1/1 Running  0  46s
→ argocd-repo-server-77cb89f598-7hs56                 1/1 Running  0  46s
→ argocd-server-7d846cfdd-gcgvf                       1/1 Running  0  46s
```

## Expect Next Cycle
- Layer 4 complete: Forgejo + ArgoCD both Running
- Next layer: Layer 5 — Prometheus, VictoriaLogs, Jaeger (observability)
- Begin with Prometheus chart next cycle
