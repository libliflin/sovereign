# Vendor System (Autarky)

The platform must be genuinely self-sufficient at runtime. After bootstrap,
the cluster never pulls from external registries (docker.io, quay.io, etc.).

## The System (Gentoo-inspired)

- Every upstream dependency has a recipe in `vendor/recipes/<name>/recipe.yaml`
- `vendor/fetch.sh` mirrors upstream source into internal GitLab
- `vendor/build.sh` builds OCI images and pushes to Harbor
- `vendor/update-check.sh` checks for new upstream releases
- No git submodules. The internal GitLab is the source of truth.

## Recipe Format

Every `recipe.yaml` MUST declare:
```yaml
rollout:
  strategy: rolling        # rolling | node_by_node (CNI only) | skip (bootstrap tools)
  max_unavailable: 0
  max_surge: 1
  staging_timeout: 5m
  production_timeout: 10m
backup:
  priority: critical       # critical | standard | derived (can be rebuilt)
```

## Distroless Standard

All container images MUST use distroless base images:
- Go binaries -> `gcr.io/distroless/static`
- JVM services -> `gcr.io/distroless/java21`
- Node.js services -> `gcr.io/distroless/nodejs`

Non-distroless images require `deprecated: true` in `vendor/VENDORS.yaml`
with `deprecated_reason` and `alternative`.

## License Policy

- Apache 2.0, MIT, BSD, LGPL -> approved
- BSL (HashiCorp) -> BLOCKED. Use OpenBao instead of Vault.
- AGPL -> review required
- SSPL -> blocked
- Run `vendor/audit.sh` before marking any vendor story as passing.

## Script Requirements

Every vendor script MUST support:
- `--dry-run` — print actions without executing
- `--backup` — push to secondary remote/registry after primary operation

## Zero Downtime Rollout

```
build.sh -> harbor staging -> deploy staging -> smoke test -> promote -> rollback on failure
```

`rollback.sh` reads the last-known-good ConfigMap and repins that image digest.
Rollback must complete in under 2 minutes.
