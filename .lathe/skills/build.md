# Build — Sovereign Platform

## Helm Charts

Charts live in `platform/charts/<service>/` and `cluster/kind/charts/<service>/`. No charts in the root `charts/` (retired).

```bash
# Lint a chart:
helm lint platform/charts/<name>/

# Render a chart (check output):
helm template sovereign platform/charts/<name>/ --set global.domain=sovereign-autarky.dev

# HA gate scoped to one chart:
bash scripts/ha-gate.sh --chart <name>

# Full HA gate (all charts):
bash scripts/ha-gate.sh
```

## Shell Scripts

All `.sh` files in `cluster/`, `platform/`, `scripts/` must pass:
```bash
shellcheck -S error <script>
```

Vendor scripts additionally must handle `--dry-run` and `--backup` flags.

## Contract Validator

```bash
python3 contract/validate.py contract/v1/tests/valid.yaml          # must exit 0
python3 contract/validate.py contract/v1/tests/invalid-*.yaml      # each must exit 1
```

## Adding a New Chart

1. Create `platform/charts/<service>/` with `Chart.yaml`, `values.yaml`, `templates/`
2. Create `platform/argocd-apps/<tier>/<service>-app.yaml` with `spec.revisionHistoryLimit: 3`
3. Register in `platform/vendor/VENDORS.yaml` (required fields: name, upstream, version, license, distroless)
4. If the service is architecturally single-instance, add `ha_exception: true` to VENDORS.yaml entry — the HA gate checks this before requiring PDB/antiAffinity

## Vendor Recipes

`platform/vendor/recipes/<name>/recipe.yaml` must declare:
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

## Snapshot

The snapshot summarizes project health. Run it to see what the agent will see:
```bash
bash .lathe/snapshot.sh
```

Sections: Git Status, Recent Commits, Sprint, Helm Lint, Contract Validator (G7), Autarky (G6), Shellcheck, State Docs (G2), CI config list.
