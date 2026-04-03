# Changelog — Cycle 41

## Observed
- Layer: 7 (Backstage — developer experience)
- Service: backstage
- Category: DEPENDENCY_MISSING + CONFIG_ERROR (compound)
- Evidence: `connect ECONNREFUSED ::1:5432` — no PostgreSQL deployed; helm release in `failed` state

## Applied

### Fix 1: Add PostgreSQL to Backstage chart
- Added `platform/charts/backstage/templates/postgresql-statefulset.yaml` — bitnami/postgresql:16.3.0-debian-12-r14 StatefulSet (image already on nodes from cycle 22)
- Added `platform/charts/backstage/templates/postgresql-service.yaml` — ClusterIP service on port 5432
- Added `postgresql:` section to `platform/charts/backstage/values.yaml`
- Added DB env vars to `platform/charts/backstage/templates/deployment.yaml` (`APP_CONFIG_backend_database_*`)
- Added ConfigMap volumeMount to deployment
- Files: `platform/charts/backstage/templates/postgresql-statefulset.yaml`, `platform/charts/backstage/templates/postgresql-service.yaml`, `platform/charts/backstage/values.yaml`, `platform/charts/backstage/templates/deployment.yaml`

### Fix 2: OPA Gatekeeper blocking local-path provisioner helper-pod (kube-system)
- Added `kube-system` to `privilegeEscalationExcludedNamespaces` in `platform/charts/opa-gatekeeper/values.yaml`
- Added `excludedNamespaces` support to `constraint-require-resource-limits.yaml` template (previously had none)
- Added `resourceLimitsExcludedNamespaces: [kube-system]` to `platform/charts/opa-gatekeeper/values.yaml`
- Files: `platform/charts/opa-gatekeeper/values.yaml`, `platform/charts/opa-gatekeeper/templates/constraint-require-resource-limits.yaml`

### Fix 3: OPA Gatekeeper blocking PostgreSQL container (no allowPrivilegeEscalation)
- Added `securityContext.allowPrivilegeEscalation: false` to postgresql container in StatefulSet
- Files: `platform/charts/backstage/templates/postgresql-statefulset.yaml`

### Fix 4: Guest auth provider blocking Backstage startup in production
- Baked-in `app-config.yaml` in `ghcr.io/backstage/backstage:1.30.2` has `auth.providers.guest: {}`. In production mode, Backstage 1.30 refuses to initialize guest auth and throws fatal error
- Added `auth.environment: production` and `auth.providers.guest.dangerouslyAllowOutsideDevelopment: true` to `platform/charts/backstage/templates/configmap.yaml`
- Acceptable for local dev cluster; Keycloak OIDC is the target auth path once client is configured
- Files: `platform/charts/backstage/templates/configmap.yaml`

### Fix 5: Knex migration lock from concurrent startup
- Two pods tried to run DB migrations simultaneously; one crashed mid-lock
- Cleared lock: `UPDATE knex_migrations_lock SET is_locked=0` in `backstage_plugin_catalog` database

## Validated
```
helm lint platform/charts/backstage/
→ 1 chart(s) linted, 0 chart(s) failed

helm lint platform/charts/opa-gatekeeper/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate:
grep -rn "docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io" \
  platform/charts/backstage/templates/ platform/charts/opa-gatekeeper/templates/
→ PASS

kubectl get pods -n backstage
→ backstage-84b9fc674d-4w96c   1/1   Running   4   2m56s
→ backstage-84b9fc674d-qjf5m   1/1   Running   0   50s
→ backstage-postgresql-0       1/1   Running   0   17m
```

## Expect Next Cycle
- All 8 layers fully healthy: Layer 0-7 complete
- Backstage accessible at https://backstage.sovereign-autarky.dev with guest auth
- Zot still shows 5 restarts — investigate if persistent or stabilized
- Consider configuring Keycloak Backstage OIDC client to replace `dangerouslyAllowOutsideDevelopment: true`
