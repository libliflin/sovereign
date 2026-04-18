# Testing — How This Project Tests

---

## Constitutional Gates (run every cycle, checked by snapshot.sh)

The snapshot runs these gates and reports pass/fail. If any gate fails, it's the top priority.

| Gate | Command | What It Checks |
|---|---|---|
| G1 | `python3 -m py_compile scripts/ralph/ceremonies.py scripts/ralph/lib/orient.py scripts/ralph/lib/gates.py && PYTHONPATH=. python3 -c "from scripts.ralph.lib import orient, gates"` | Ceremony scripts compile + imports resolve |
| G6 | `grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/*/templates/` (expect no output) | No external registry refs in chart templates |
| G7 | `python3 contract/validate.py contract/v1/tests/valid.yaml` (must pass) and `python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml` (must exit 1) | Contract validator enforces sovereignty |
| G8 | `helm template platform/charts/istio/ \| grep PeerAuthentication && grep "mode: STRICT"` | Istio chart renders STRICT mTLS |
| G9 | `bash scripts/ha-gate.sh` | All charts pass HA requirements |

---

## Python Unit Tests (scripts/ralph/tests/)

Tests live in `scripts/ralph/tests/test_*.py`. Runner: plain Python (`python3 <file>`), not pytest.

Output format: lines starting with `PASS:` for passing tests, ending with `All tests passed.` on success.

Run all: the snapshot runs `for f in scripts/ralph/tests/test_*.py; do cd "$(dirname "$f")" && python3 "$(basename "$f")"; done`.

Tests cover ceremony logic, orient/gates modules, story lifecycle transitions.

---

## Helm Chart Validation

```bash
# Lint (catches YAML errors, required fields)
helm lint platform/charts/<name>/

# HA gate (scoped — only checks the named chart)
bash scripts/ha-gate.sh --chart <name>

# Resource limits (check-limits.py wired into ha-gate.sh)
helm template platform/charts/<name>/ | python3 scripts/check-limits.py

# Autarky (no external registries)
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/<name>/templates/ && echo "FAIL" || echo "PASS"

# No :latest tags
grep -n ":\s*latest" platform/charts/<name>/values.yaml && echo "FAIL" || echo "PASS"
```

**Important:** `ha-gate.sh` uses `set -euo pipefail`. Under `grep` with no match (e.g., `platform/charts/_globals/` has no `replicaCount`), the script can exit silently. Use `|| true` on grep pipelines where no match is expected. This is documented in `scripts/ralph/ceremonies/smart.md`.

For upstream wrapper charts (bitnami, etc.), run `helm dependency update platform/charts/<name>/` before lint.

---

## ArgoCD App Manifest Validation

CI cannot run `kubectl apply --dry-run=client` because ArgoCD CRDs aren't installed in kind-sovereign-test. Use:

```bash
python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())" platform/argocd-apps/<tier>/<name>-app.yaml
```

All app manifests must have `spec.revisionHistoryLimit: 3`.

---

## Shell Script Validation

```bash
shellcheck -S error <script>.sh
```

Common pitfalls:
- Unquoted variables → always `"$var"` not `$var`.
- `local x=$(cmd)` → split to `local x; x=$(cmd)` (SC2155).
- `grep pattern file` under `set -euo pipefail` → use `|| true` when no match is expected.

Scripts must be tested against all existing charts in `platform/charts/` before `passes: true`, not just synthetic fixtures. This catches `_globals/` edge cases.

---

## Contract Validator Tests

```bash
python3 contract/validate.py contract/v1/tests/valid.yaml        # must exit 0
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml  # must exit 1
echo "Exit: $?"
```

---

## Kind Integration Tests (scripts/test/kind-smoke.sh)

Static scaffold covering PLATFORM-001 through PLATFORM-004. Requires `kind-sovereign-test` cluster running. Tests: cert-manager, sealed-secrets, Harbor, Keycloak deployment verification.

Stories that require kind-sovereign-test get a `blocker` field. Accept static verification and move on — don't hold stories hostage to runtime tests that require infrastructure the contributor may not have.

---

## CI Workflows (.github/workflows/)

| Workflow | Trigger | What It Runs |
|---|---|---|
| `validate.yml` | PR or push to main | Helm lint, HA gate, autarky, shellcheck, ArgoCD manifest YAML |
| `ha-gate.yml` | PR touching `platform/charts/` | HA gate across all charts |
| `release.yml` | Tag push | Release artifacts |

No `pull_request_target` or `issue_comment` triggers — lower prompt injection risk than PRs from forks would have with those triggers. The repo is public, so CI runs on fork PRs.

**Security note:** The lathe reads CI status and PR metadata from GitHub into agent prompts. This is a prompt injection surface. PR titles and descriptions from external contributors could contain adversarial content. The lathe should treat CI status (pass/fail) as authoritative and treat free-text fields (PR descriptions, issue titles) as untrusted.

---

## SMART AC Guidance (critical for stories)

When an AC asserts a vendor-specific status field value (e.g. `phase=X`, `condition=Y`), the story must either:
- Cite the upstream CRD documentation for the pinned chart version, OR
- Note that the value was empirically confirmed against a running instance.

Violation: TEST-004b failed review 3x because AC3 asserted `phase=Finished` but chaos-mesh v2.6.3 uses `AllRecovered=True` as the terminal recovery state.

Stories with chart-iterating shell scripts must be tested against all existing `platform/charts/` before `passes: true` — not just synthetic fixtures.
