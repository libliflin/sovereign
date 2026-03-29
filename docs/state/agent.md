# Agent Briefing

> This document is rewritten each sprint by the sync ceremony.
> Read this before touching any file in the repository.
> It reflects what is true right now — not what was true last sprint.

---

## What you are doing

Building the Sovereign Platform: a self-hosted Kubernetes stack deployable from one command.
You are an implementation agent. You receive stories from the sprint file, implement them,
push branches, open PRs. Ceremonies verify your work. You do not run ceremonies.

---

## Where things live

| What | Where |
|---|---|
| Current sprint | `prd/manifest.json` → `activeSprint` field |
| All stories | `prd/backlog.json` |
| Strategic direction | `prd/themes.json`, `prd/epics.json` |
| Platform service charts | `platform/charts/<service>/` |
| Kind bootstrap charts | `cluster/kind/charts/<service>/` |
| ArgoCD apps | `argocd-apps/<tier>/<service>-app.yaml` |
| Contract schema | `contract/v1/` — validated by `contract/validate.py` |
| Bootstrap scripts | `bootstrap/` (VPS) and `cluster/kind/bootstrap.sh` (kind) |
| Governance rules | `docs/governance/` |
| Architecture decisions | `docs/state/architecture.md` (this directory) |

The root `charts/` directory is empty and retired. Do not create charts there.

---

## Patterns that must not be broken

**Domain**: always `{{ .Values.global.domain }}` in Helm _templates_. `values.yaml` defaults may
use the dogfood domain `sovereign-autarky.dev` — that is correct and expected. Never put a literal
domain in `templates/`.

**Storage class**: always `{{ .Values.global.storageClass }}`. Never `standard` or `ceph-block` literal.

**Secrets**: never in plain text, never committed. Use Sealed Secrets for GitOps, OpenBao references for runtime.

**Namespaces**: each service gets its own namespace. Never deploy into `default`.

**Helm chart structure**: every chart needs `Chart.yaml`, `values.yaml`, `templates/`. Run
`helm dependency update` before `helm lint` when `Chart.yaml` has dependencies.

**Chart location**: platform service charts go in `platform/charts/<service>/`. Kind bootstrap
charts (cert-manager, cilium, sealed-secrets) go in `cluster/kind/charts/<service>/`.
Never create charts in the root `charts/` directory.

**HA gate — run before every `git push` on a chart story:**

```bash
helm template platform/charts/<name>/ | grep -c PodDisruptionBudget   # must be >= 1 (>= 1 per component for distributed-mode charts)
helm template platform/charts/<name>/ | grep -c podAntiAffinity        # must be >= 1
grep replicaCount platform/charts/<name>/values.yaml                   # must be >= 2
helm template platform/charts/<name>/ | python3 scripts/check-limits.py  # every container must have requests AND limits
```

This applies to upstream wrapper charts too. Setting `affinity` in `values.yaml` is not
sufficient — verify the rendered output actually contains `podAntiAffinity`. If the upstream
chart does not propagate it, add a dedicated affinity template that merges the required rule.

For distributed-mode charts (Loki Simple Scalable, Tempo distributed), the upstream chart
generates one PDB per component (ingester, distributor, querier, etc.). Count must be >= number
of deployed components, not just >= 1. Use `grep -c PodDisruptionBudget` and verify the count
is reasonable for the chart's component topology.

**Resource limits — use check-limits.py, not grep**: `grep -A5 resources:` is insufficient for
verifying resource limits on every container. It passes even when one initContainer is missing
limits. Always use `helm template platform/charts/<name>/ | python3 scripts/check-limits.py`
which exhaustively enumerates every container and initContainer spec. This is quality gate #6.

**Upstream wrapper charts need values-schema research before implementation**: when an HA story
covers a chart that wraps an upstream Helm chart (cilium, cert-manager, crossplane, etc.), identify
the specific upstream `values.yaml` key for each container and initContainer's resource limits
before writing any code. Do not assume a generic key (e.g., `initResources`) applies to all
initContainers. Cross-reference the upstream chart's values schema and confirm the exact key for
each container in your implementation. Quote the exact key in the acceptance criteria.

**Storage-provider charts require different HA ACs**: charts that ARE storage providers
(rook-ceph, etcd) create StorageClasses — they do not consume a pre-existing StorageClass for
their own StatefulSet PVs. The standard AC "volumeClaimTemplates reference global.storageClass"
is inapplicable for these charts. Instead, add a CephCluster CR template with
`spec.storage.storageClassDeviceSets` referencing `{{ .Values.global.storageClass }}`. This is
the correct way to satisfy the original AC intent for operator charts.

**HA exception for single-instance upstreams**: some upstream services (SonarQube CE, MailHog,
single-node Elasticsearch) architecturally cannot scale horizontally. For these:

1. Add `ha_exception: true` and `ha_exception_reason: "<reason>"` to the service's entry in `vendor/VENDORS.yaml`
2. Set a top-level `replicaCount: 1` in `values.yaml` with a comment: `# ha_exception: see vendor/VENDORS.yaml`
3. HA gate #5 passes only when BOTH conditions are met. Missing the VENDORS.yaml entry always fails.

**Re-attempts after review failure — read reviewNotes first**: when a story has `attempts > 0`,
the `reviewNotes[]` array contains the exact failure from the previous review. Before writing
any code on a re-attempt, read and summarize the specific change described in `reviewNotes[0]`.
Implement only that targeted fix. Do not re-implement the full story.

**Bitnami subchart PDB**: when a bitnami/upstream subchart provides PDB by default, still add a
wrapper-level `templates/poddisruptionbudget.yaml` and disable the subchart PDB with
`<subchart>.pdb.create: false` to avoid duplicate PDB selectors.

**ArgoCD apps**: every Application manifest must have `spec.revisionHistoryLimit: 3`. Omitting it
causes review failure. Validate YAML with `yq e '.'` (not `kubectl apply --dry-run` — ArgoCD CRDs
are not installed locally).

**kubectl dry-run does not work for CRD-backed resources**: `kubectl apply --dry-run=client`
silently fails with "no matches for kind X" for any custom resource (ArgoCD Application,
Crossplane XR/XRC, etc.) unless the operator CRDs are pre-installed in the target cluster.
kind-sovereign-test is a bare cluster — it has no operator CRDs. For CRD-backed manifests,
use YAML-only validation:
```bash
python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())"
```
This is the correct gate for any `.yaml` file that is not a core K8s resource. Core resources
(Deployment, Service, Ingress, PDB, ConfigMap) can still use `kubectl apply --dry-run=client`.

**shellcheck**: all `.sh` files must pass `shellcheck -S error` (matches CI's shellcheck 0.10.0).
Common fixes:

- Quote variables: `"$var"` not `$var`
- Split `local` + command substitution: `local x; x=$(cmd)` — not `local x=$(cmd)` (SC2155)
- Empty array safety: `"${ARRAY[@]+"${ARRAY[@]}"}` instead of `"${ARRAY[@]}"` with `set -u`
- Don't source `interface.sh` (has `exit 1` stubs that fire SC2317 unreachable code)

**vendor scripts**: every script in `vendor/*.sh` must support both `--dry-run` AND `--backup`
flags. CI checks for both with grep. Missing either causes CI failure.

**Observability charts with Grafana integration**: include a Grafana datasource ConfigMap in
`platform/charts/<name>/templates/`. This is required for the chart to auto-register in Grafana.
Gate: `helm template platform/charts/<name>/ | grep -i datasource` must exit 0.

**Documentation stories**: use `markdownlint` for lint validation and `grep -i 'cost'` to
confirm cost estimates are present in provider docs. This is a reusable testPlan pattern.

**Sprint goal must match increment themeGoal**: when the planning ceremony populates a sprint,
verify that every story's `epicId`/`themeId` aligns with the increment's declared `themeGoal`.
A story whose theme contradicts the increment's purpose creates SMART scoring noise and velocity
drift. If the sprint goal diverges from the increment `themeGoal`, flag it before accepting
stories — do not implement work that contradicts the increment's stated purpose.

**Sprint planning must fill >= 75% capacity**: a sprint with fewer stories than its capacity
allows is a planning failure. If the current increment's backlog is exhausted, pull the
highest-priority stories from adjacent increments or the general backlog.

**Kaizen stories in feature sprints must have priority ≤ 5**: a kaizen story with priority > 5
in a feature sprint will always land last in the priority queue. Last means it may miss the
review window at sprint boundary and end up in `passes: true, reviewed: false` purgatory.
If a kaizen fix matters enough to be in the sprint, give it priority ≤ 5.

**Multi-stage Dockerfile for Node.js + React**: build the React frontend with `vite build`,
build the Express/Node backend with `tsc`, combine both artifacts in a single distroless-style
production image. This pattern is used by Sovereign PM and should be reused for any future
Node/React services.

**Keycloak OIDC env vars must be explicit**: in-cluster apps using `keycloak-js` or JWT
middleware need `KEYCLOAK_URL` (and realm, client ID) as explicit Helm values with clear
placeholders in `values.yaml`. Do not assume DNS resolution of the Keycloak service will work
in local kind clusters.

**bitnami/postgresql subchart vs Crossplane XRC**: for in-cluster apps that need PostgreSQL,
use `bitnami/postgresql` as a Helm subchart dependency (quick-start path). The Crossplane XRC
path is correct for production once foundations are running — but do not block a story on
Crossplane readiness when bitnami works. Resolve this OR-choice in the story before implementation.

**OR-choices must be resolved at grooming, not implementation**: when a story says "option A OR
option B", the implementer must pick one before writing code. Leaving it open creates scope
ambiguity and rework risk. Future grooming should resolve all OR-choices before pulling a
story into a sprint.

**ANDON stories must inline the verification command, and it must be a runnable one-liner**:
ANDON remediation stories must include the exact verification command in `acceptanceCriteria` —
a self-contained Python or bash one-liner that proves the gate passes without navigating to an
external file. This pattern consistently produces single-iteration completion with no review
failures. Stories that reference external files for their verification conditions require
navigation and reduce the SMART "specific" score.

**Remediation sprints work best as single tightly-scoped stories**: remediation sprints with
one story (≤ 2 pts) consistently achieve 100% first-review acceptance. When opening a
remediation sprint, prefer one clearly-scoped story over bundling multiple fixes. If multiple
blockers exist, order them by severity and sprint them sequentially.

**Remediation sprints require at least one execute cycle before retro is eligible**: a
remediation sprint with zero execute cycles (all stories at `attempts: 0`, no stories accepted)
must not fire retro. If you find yourself in this state, the story was likely never attempted
and remains unimplemented. Check `backlog.json` — the story will have been returned there.
The planning ceremony that follows will typically resolve the root condition (e.g., adding a
pending increment resolves GGE-G5). If not, the backlog story covers the fallback.

---

## How to implement a story

1. Read the story from the active sprint file
2. Check out the branch named in `branchName` (create from `main` if it doesn't exist)
3. If `attempts > 0`: read `reviewNotes[0]`, summarize the specific change required, implement only that
4. Implement the acceptance criteria — nothing more, nothing less
5. Write the **test contract** before touching any file — list each test command and expected output.
   Only begin implementation after the contract is written. Run every test. Show the output.

6. Run quality gates before marking `passes: true`:
   - `helm lint platform/charts/<name>/` if you touched a platform chart
   - `helm lint cluster/kind/charts/<name>/` if you touched a kind chart
   - HA gate (PDB, podAntiAffinity, replicaCount) if you touched a chart
   - `helm template platform/charts/<name>/ | python3 scripts/check-limits.py` if you touched a chart
   - `helm template platform/charts/<name>/ | grep -i datasource` if you added an observability chart
   - `shellcheck -S error <file>.sh` if you touched a shell script
   - `python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())"` for ArgoCD Application manifests (CRDs not in kind — use YAML-only validation)
   - `yq e '.' <file>.yaml` on all YAML files touched
   - `yq '.spec.revisionHistoryLimit' argocd-apps/<tier>/<name>-app.yaml` — must equal 3
   - **Autarky gate** (every chart or vendor story — show output verbatim):
     ```bash
     grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/*/templates/ cluster/kind/charts/*/templates/ 2>/dev/null \
       && echo "FAIL" && exit 1 || echo "PASS: no external registries in templates"
     ```
6. Set `passes: true` in the sprint file
7. Push the branch, open a PR, wait for CI to pass, merge to main

Do not mark `passes: true` if any gate fails. Do not self-certify — gates will re-run.

---

## What the ceremonies do (not your job)

- **Smoke test**: runs `helm lint` + `shellcheck` + `yq` across the whole repo
- **Proof of work**: checks your branch is pushed and PR is merged to main
- **Review**: adversarially checks your acceptance criteria
- **Retro**: closes the sprint, returns incomplete work to backlog with 5 Whys
- **Sync**: rewrites `docs/state/architecture.md` and `docs/state/agent.md`
- **Advance**: moves the increment pointer in manifest.json
- **Plan**: populates the next sprint file with stories from the backlog

You implement. Ceremonies verify. Don't conflate the two.

---

## Current platform state

Increments complete: 0 (ceremonies), 1 (bootstrap), 2 (foundations), 2h (ci-hardening),
2i (integration), 3 (gitops-engine), 4 (autarky), 5 (security), 6 (observability), 7 (devex),
8 (testing-and-ha), 9 (sovereign-pm — documentation layer: quickstart, architecture, provider guides,
README), 10 (sovereign-pm-webapp — Node.js/Express backend, React frontend, Dockerfile, Helm chart),
11 (remediation — restored GGE G5: planning pipeline guard for pending increment),
12 (developer-portal — Backstage plugin config, SonarQube + ReportPortal Helm charts; story 027a
returned to backlog: kubectl dry-run gate fails for ArgoCD CRDs not installed in kind),
13 (remediation — GGE G5 restored: increment 14 added to manifest.json as pending),
14 (developer-portal-argocd — delivered backstage-app.yaml ArgoCD Application manifest),
15 (remediation — GGE G5 restored: increment 16 added to manifest.json as pending),
16 (code-quality — SonarQube + ReportPortal GitLab CI integration),
17 (restructure — contract/v1/ schema, cluster/kind/bootstrap.sh, platform/deploy.sh,
charts migrated to platform/charts/ and cluster/kind/charts/),
18 (remediation — zero stories accepted; GGE-G5-andon returned to backlog; retro fired before
any execute cycle ran)

Increment active: 18 complete, awaiting advance ceremony to activate next increment.
No pending increments exist in manifest.json — GGE G5 is failing. The planning ceremony must
add a new pending increment before advance can proceed.

KAIZEN-003 (fix attempts field initialization) is implemented (`passes: true`) and returned to
backlog pending review ceremony in the next sprint. It does not need re-implementation.

Epics complete: E1 (ceremonies), E2 (bootstrap), E3 (foundations), E4 (identity), E5 (GitOps engine),
E6 (autarky vendor system), E7 (service mesh), E8 (policy + runtime security), E9 (metrics/dashboards),
E10 (logs + traces), E14 (Sovereign PM web app — delivered in increments 9 and 10)

Epics active/backlog: E11 (developer portal — Backstage chart + ArgoCD app exist; stories 027a
full Keycloak OIDC/plugin config, 027b, 049 still pending), E12 (code quality — SonarQube +
ReportPortal Helm charts and ArgoCD apps exist; GitLab CI integration story 052 pending),
E13 (testing infrastructure + HA validation), E15 (HA integration testing)

---

## Hard stops — do not proceed if any of these are true

- A Tier 1 component (CNI, storage, PKI, secret store, service mesh, policy engine) is sourced
  from a vendor-controlled project → flag to retro, do not implement
- A secret is about to be committed in plain text → stop immediately
- A chart hardcodes a domain name or IP address in `templates/` → fix before marking passes: true
- A shellcheck error is present → fix before marking passes: true
- An ArgoCD Application is missing `revisionHistoryLimit: 3` → fix before marking passes: true
- HA gate fails (PDB, podAntiAffinity, or replicaCount < 2 without a VENDORS.yaml ha_exception) → fix before marking passes: true
- `check-limits.py` reports any container or initContainer missing `resources.requests` or `resources.limits` → fix before marking passes: true
- The word "phase" appears in new Python or JSON you are writing → use "increment" instead
- `prd/manifest.json` has no increment with `status: "pending"` AND `activeSprint` is unset → the planning ceremony will stall silently; add a pending increment before advancing
- A chart template contains a hard-coded external registry (docker.io, quay.io, ghcr.io, gcr.io, registry.k8s.io) → autarky violation, fix before marking passes: true
- You are about to write `|| true`, `2>/dev/null`, or `--dry-run` as the only test → these are workarounds, diagnose and fix the root cause
- You are about to commit code containing `# TODO`, `# FIXME`, or `# HACK` → deferred work is incomplete work; use the blocker protocol instead
- A story implementation touches files outside the stated story scope (more than ~3 charts for a 1-service story, new dependencies not in VENDORS.yaml, etc.) → stop and split before implementing
- A chart is created in the root `charts/` directory → wrong location; use `platform/charts/` or `cluster/kind/charts/` depending on purpose

---

## Known model inconsistencies

- `phase` field on backlog stories is redundant with `epicId` (8 stories affected) → KAIZEN-006 will remove it
- `retro-patch-phase*.md` filenames use "phase" instead of "increment" — vocabulary inconsistency in ceremonies generation code → KAIZEN-005 will rename the pattern to `retro-patch-increment*.md`
- KAIZEN-004r (pre-retro guard): ceremonies.sh does not check for minimum execute cycles before firing retro. A sprint with zero attempts and zero accepted stories can reach retro without any work happening. KAIZEN-004r will add the guard.
