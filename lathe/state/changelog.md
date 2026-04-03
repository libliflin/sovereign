# Changelog — Cycle 23

## Observed

- Layer: 3 (Keycloak — identity / SSO)
- Service: keycloak
- Category: CHART_ERROR — helm release stuck in `failed` state from cycle 22 timeout; both pods were already Running 1/1 after fetch.sh imported bitnami images
- Evidence: `helm status keycloak -n keycloak` → `STATUS: failed`, `DESCRIPTION: context deadline exceeded`; pods showed `keycloak-0 1/1 Running` and `keycloak-postgresql-0 1/1 Running`

## Applied

- Ran `helm upgrade keycloak` with `realmInit.enabled=false` to reconcile release from `failed` → `deployed`
- No chart changes required — pods were already healthy, release just needed the upgrade to acknowledge current state

## Validated

```
helm lint platform/charts/keycloak/
→ 1 chart(s) linted, 0 chart(s) failed

helm upgrade keycloak platform/charts/keycloak/ -n keycloak --set realmInit.enabled=false --timeout 150s --wait
→ STATUS: deployed, REVISION: 2, Upgrade complete

kubectl get pods -n keycloak
→ keycloak-0              1/1 Running   0
→ keycloak-postgresql-0   1/1 Running   0

autarky gate
→ PASS
```

## Expect Next Cycle

Layer 3 (Keycloak) is healthy and deployed. Next cycle should advance to Layer 2 — Harbor (internal registry / autarky boundary). Harbor must be installed before Layer 4 (Forgejo + ArgoCD) so all subsequent images come from the internal registry.
