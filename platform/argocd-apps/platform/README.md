# ArgoCD Applications — Platform

This directory contains ArgoCD Application manifests for the **platform** tier.

Platform apps are the foundational services: Cilium, Crossplane, cert-manager, Sealed Secrets,
Vault, Keycloak, Rook/Ceph, GitLab, Harbor, and ArgoCD itself.

ArgoCD's root app watches this directory and automatically creates/syncs all Application resources.

## Adding a new application

Create a new `<service>-app.yaml` file:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <service>
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/libliflin/sovereign
    targetRevision: HEAD
    path: charts/<service>
  destination:
    server: https://kubernetes.default.svc
    namespace: <service>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```
