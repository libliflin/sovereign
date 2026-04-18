# Build — Non-Obvious Build Process

---

## Helm Charts

All platform charts live in `platform/charts/<name>/`. Kind bootstrap charts live in `cluster/kind/charts/<name>/`.

Upstream wrapper charts (cilium, cert-manager, bitnami subcharts) need dependency resolution before lint:
```bash
helm dependency update platform/charts/<name>/
helm lint platform/charts/<name>/
```

New charts require both a Helm chart directory AND an ArgoCD Application manifest in `platform/argocd-apps/<tier>/<name>-app.yaml`.

Every new namespace must be added to `platform/charts/network-policies/values.yaml` for egress baseline enforcement.

---

## Bootstrap Scripts

`bootstrap/bootstrap.sh` — provisions real VPS nodes. Entry points:
- `--estimated-cost` — prints cost estimate, no charges.
- `--confirm-charges` — provisions real servers (requires this flag).
- `--dry-run` — preview intended actions.

`bootstrap/verify.sh` — verifies cluster health post-bootstrap.

`cluster/kind/bootstrap.sh` — creates a local kind cluster named `sovereign-test`. Options:
- `--cluster-name NAME` — override cluster name (default: `sovereign-test`).
- `--dry-run` — preview.

`platform/deploy.sh` — Helm deployment orchestrator for kind. Options:
- `--chart-dir DIR` — chart to deploy.
- `--namespace NS` — target namespace.
- `--cluster-values cluster-values.yaml` — values override.

---

## Quality Gate Scripts

`scripts/ha-gate.sh` — validates HA requirements across charts.
- `--chart <name>` — scoped to one chart (exits 0/1 based only on that chart).
- No `--chart` flag — runs across all charts.

**Pitfall:** `ha-gate.sh` uses `set -euo pipefail`. A `grep` with no match exits 1, which kills the script silently. Use `|| true` on grep pipelines. `platform/charts/_globals/` has no `replicaCount` field and will cause bare greps to exit 1.

`scripts/check-limits.py` — reads helm template output from stdin, validates every container has `resources.requests` and `resources.limits`. Exits 1 with failing containers listed. Wired into `ha-gate.sh`.

---

## Vendor Pipeline

The vendor system produces distroless images from vetted source. Not invoked in normal development — only when adding a new vendored service or updating an existing one.

```
vendor/fetch.sh     → SHA-verified source mirror into Forgejo
vendor/build.sh     → distroless OCI image → Harbor
vendor/deploy.sh    → stage → smoke → promote
vendor/rollback.sh  → revert to last-known-good SHA
vendor/backup.sh    → CronJob: mirror repos + images to secondary storage
```

Image tag format: `<upstream-version>-<source-sha>-p<patch-count>` (e.g. `v1.16.0-a3f8c2d-p3`).

Vendor recipes: `platform/vendor/recipes/<name>/` with `recipe.yaml` and optional `patches/`.
Vendor manifest: `platform/vendor/VENDORS.yaml` — license, HA exception, distroless status.

---

## Ceremony System

`scripts/ralph/ceremonies.py` — the delivery loop. Runs as a Python script.

Validate it compiles and imports resolve:
```bash
python3 -m py_compile scripts/ralph/ceremonies.py scripts/ralph/lib/orient.py scripts/ralph/lib/gates.py
PYTHONPATH=. python3 -c "from scripts.ralph.lib import orient, gates"
```

Libraries live in `scripts/ralph/lib/`. Tests in `scripts/ralph/tests/test_*.py`.

SMART guidance doc: `scripts/ralph/ceremonies/smart.md` — rules for writing story acceptance criteria.

---

## Commit Message Format

```
type: description — enforcement target
```

Types: `feat`, `fix`, `docs`, `test`, `chore`, `refactor`. The em-dash names what the change enforces — use when it applies.

Examples:
```
feat: add loki chart — enforce log aggregation at cluster layer
fix: correct replicaCount in prometheus-stack values.yaml
docs: add hetzner provider setup guide
```

---

## PR Workflow

1. Feature branch from `main`.
2. Implement + run quality gates locally.
3. Open PR against `main`.
4. CI runs `validate.yml` — helm lint, HA gate, autarky, shellcheck.
5. CI green → squash merge.

Never push directly to main for feature work. Every story requires a PR with CI green before `passes: true`.

---

## Known Build Quirks

- `platform/charts/_globals/` is a shared partials chart — not a deployable chart. It has no `replicaCount` field. Scripts that iterate `platform/charts/*/` must handle it specially (skip or `|| true` on grep).
- ArgoCD CRDs are not installed in `kind-sovereign-test`. YAML-validate app manifests with Python `yaml.safe_load` instead of `kubectl apply --dry-run`.
- `helm template` on charts with upstream dependencies requires `helm dependency update` first.
