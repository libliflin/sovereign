# Testing

How this project tests. Gates, CI, conventions.

---

## Constitutional Gates (run each cycle via snapshot.sh)

These are the stop-the-line invariants. All must pass before any new work:

| Gate | What it checks | Command |
|------|---------------|---------|
| G1 | ceremonies.py compiles + imports resolve | `python3 -m py_compile scripts/ralph/ceremonies.py && PYTHONPATH=. python3 -c "from scripts.ralph.lib import orient, gates"` |
| G6 | No external registry refs in chart templates | `grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/*/templates/` (must return empty) |
| G7 | Contract validator test suite passes | `python3 contract/validate.py contract/v1/tests/valid.yaml` (must exit 0) and `python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml` (must exit 1) |
| G8 | Istio renders STRICT PeerAuthentication | `helm template platform/charts/istio/ \| grep -A2 "kind: PeerAuthentication"` (must show `mode: STRICT`) |
| G9 | All platform charts satisfy HA requirements | `bash scripts/ha-gate.sh` (must exit 0) |

Run them: `bash .lathe/snapshot.sh` shows all gate results.

## Helm Chart Gates (run before `passes: true` on any chart story)

```bash
helm lint platform/charts/<name>/
helm template platform/charts/<name>/ | grep PodDisruptionBudget      # must be >= 1
helm template platform/charts/<name>/ | grep podAntiAffinity           # must be >= 1
grep -E 'replicaCount:[[:space:]]+[2-9]' platform/charts/<name>/values.yaml  # must match
helm template platform/charts/<name>/ | python3 scripts/check-limits.py      # must pass
```

For distributed-mode charts (Loki, Tempo), PDB count must be >= number of components, not just >= 1.

**Autarky gate** (every chart story):
```bash
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/<name>/templates/ && echo "AUTARKY FAIL" || echo "AUTARKY PASS"
```

**Observability chart gate:**
```bash
helm template platform/charts/<name>/ | grep -i datasource   # must find datasource ConfigMap
```

## Shell Script Gates

```bash
shellcheck -S error <script>.sh
```

All scripts must pass `shellcheck -S error`. Common fixes documented in `docs/state/agent.md`.

Vendor scripts (`platform/vendor/*.sh`) must also support `--dry-run` and `--backup`.

## Contract Validation

```bash
python3 contract/validate.py cluster-values.yaml      # validate actual cluster config
python3 contract/validate.py contract/v1/tests/valid.yaml                # must exit 0
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml  # must exit 1
```

## CI Workflows

Three workflows in `.github/workflows/`:

**`validate.yml`** — triggers on `pull_request` (main branch) and `push` to main:
- Job 0: Discover charts with Chart.yaml
- Job 1: `helm-validate` (matrix per chart) — lint, template, PDB, podAntiAffinity, replicaCount, :latest check, external registry check
- Job 2: `shell-validate` — shellcheck on cluster, platform, scripts/ralph, vendor scripts; vendor script flag checks
- Job 3: `vendor-audit` — runs only when platform/vendor/ changes
- Job 4: `argocd-validate` — checks revisionHistoryLimit: 3 on all Application manifests
- Job 5: `bootstrap-validate` — shellcheck on bootstrap scripts, dry-run flag, no hardcoded IPs

**`ha-gate.yml`** — triggers on `pull_request` when `platform/charts/**` changes:
- Runs `ha-gate.sh --dry-run`
- Runs `check-limits.py` on changed charts

**`release.yml`** — release automation (check the workflow file for details)

**Security note:** Workflows use `pull_request` (not `pull_request_target`), so they run in a restricted context without access to secrets. This is safe for a public repo.

## Kind Integration Tests

`scripts/test/kind-smoke.sh` — smoke test covering PLATFORM-001 through PLATFORM-004. Runs helm/kubectl checks against the `kind-sovereign-test` cluster.

`kind/fixtures/pdb-test.yaml` — PodDisruptionBudget drain validation fixture (kubectl drain blocked when last pod would be evicted).

`kind/smoke-test/rolling-update.sh` — zero pod unavailability during Helm upgrade.

`cluster/kind/ha-bootstrap.sh` — 3 control-plane node HA variant.

All kind scripts must: support `--dry-run`, pass `shellcheck -S error`.

## Unit Tests (Ceremony Pipeline)

`scripts/ralph/tests/test_retro_guard.py` — pre-retro guard unit test.

Run with: `python3 -m pytest scripts/ralph/tests/` or `python3 scripts/ralph/tests/test_retro_guard.py`

## YAML Validation

For non-core K8s resources (ArgoCD Applications, Crossplane XRs): use YAML-only validation:
```bash
python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())"
```

For core resources (Deployment, Service, PDB): `kubectl apply --dry-run=client` works.

For ArgoCD revisionHistoryLimit:
```bash
yq '.spec.revisionHistoryLimit' argocd-apps/<tier>/<name>-app.yaml   # must equal 3
```
