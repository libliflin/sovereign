# Changelog — Cycle 22

## Observed

- Layer: 3 (Keycloak — identity / SSO)
- Service: keycloak
- Category: IMAGE_ISSUE — bitnami images `docker.io/bitnami/keycloak:24.0.5-debian-12-r0` and `docker.io/bitnami/postgresql:16.3.0-debian-12-r14` not found; VMs were recreated at cycle 14, losing all previously imported images; Zot pull-through proxy correctly returns 404 since these tags moved to `bitnamilegacy` at Docker Hub
- Evidence: `Failed to pull image "docker.io/bitnami/keycloak:24.0.5-debian-12-r0": not found` and `Failed to pull image "docker.io/bitnami/postgresql:16.3.0-debian-12-r14": not found`

## Applied

- Fixed ingress annotation in `platform/charts/keycloak/values.yaml`: `kubernetes.io/ingress.class: nginx` → `traefik` (cluster runs Traefik v3.6.10, not nginx)
- Created keycloak namespace and bootstrap secrets (`keycloak-admin-secret`, `keycloak-db-secret`) imperatively
- Deployed Keycloak helm release with `realmInit.enabled=false` (no ArgoCD at Layer 4 yet; realm-init is a PostSync hook)
- Re-queued bitnami images in `lathe/state/downloads.json` (entries added for cycle 22): fetch.sh will pull from `bitnamilegacy` and re-tag before importing into all 3 nodes
- Files: `platform/charts/keycloak/values.yaml`, `lathe/state/downloads.json`

## Validated

```
# Helm lint
helm lint platform/charts/keycloak/
→ 1 chart(s) linted, 0 chart(s) failed

# Autarky gate
grep -rn "docker.io|quay.io|ghcr.io|gcr.io|registry.k8s.io" platform/charts/*/templates/
→ PASS

# ClusterIssuer sovereign-ca-issuer confirmed Ready (cert-manager TLS will work)

# Helm install: timed out (150s) — keycloak and keycloak-postgresql StatefulSets in ImagePullBackOff
# Release in 'failed' state — resources are created, awaiting images
```

## Downloads Queued

- image: `docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r0` → tag as `docker.io/bitnami/keycloak:24.0.5-debian-12-r0` → k3s nodes
- image: `docker.io/bitnamilegacy/postgresql:16.3.0-debian-12-r14` → tag as `docker.io/bitnami/postgresql:16.3.0-debian-12-r14` → k3s nodes

## Expect Next Cycle

After fetch.sh runs, both bitnami images will be available in containerd on all 3 nodes. Run:
```bash
helm upgrade keycloak platform/charts/keycloak/ -n keycloak --set realmInit.enabled=false --timeout 150s --wait
```
Keycloak and keycloak-postgresql pods should start successfully and reach Running state.
