# Changelog — Cycle 26

## Observed
- Layer: 4 (Forgejo — SCM)
- Service: forgejo
- Category: CONFIG_ERROR
- Evidence: `configure-gitea` init container crashing with:
  `Failed to initialize OpenID Connect Provider with name 'Keycloak' with url '...': dial tcp: lookup auth.sovereign-autarky.dev on 10.43.0.10:53: no such host`
  Root cause: `autoDiscoverUrl` used external hostname not resolvable in-cluster; confirmed Keycloak `sovereign` realm returns 404 (realm not yet created)

## Applied
- Disabled `forgejo.gitea.oauth` block in values.yaml — OIDC cannot be configured until Keycloak sovereign realm exists
- Updated commented-out URL to internal service URL for when realm is ready: `http://keycloak.keycloak.svc.cluster.local/realms/sovereign/...`
- Files: `platform/charts/forgejo/values.yaml`

## Validated
```
helm lint platform/charts/forgejo/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
→ PASS

helm upgrade --install forgejo ... --timeout 180s --wait
→ Release "forgejo" upgraded, REVISION: 3, STATUS: deployed

kubectl get pods -n forgejo:
→ forgejo-5868d8f9dc-m54zd   1/1 Running  0  27s
→ forgejo-postgresql-0       1/1 Running  0  11m
```

## Expect Next Cycle
- Forgejo is Running at Layer 4. Next layer: ArgoCD (Layer 4).
- Keycloak sovereign realm must be created before re-enabling OIDC in forgejo values.
- Install ArgoCD chart next cycle.
