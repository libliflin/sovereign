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
| Helm charts | `charts/<service>/` |
| ArgoCD apps | `argocd-apps/<tier>/<service>-app.yaml` |
| Bootstrap scripts | `bootstrap/` |
| Governance rules | `docs/governance/` |
| Architecture decisions | `docs/state/architecture.md` (this directory) |

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

**HA gate — run before every `git push` on a chart story:**
```bash
helm template charts/<name>/ | grep -c PodDisruptionBudget   # must be >= 1 (>= 1 per component for distributed-mode charts)
helm template charts/<name>/ | grep -c podAntiAffinity        # must be >= 1
grep replicaCount charts/<name>/values.yaml                   # must be >= 2
```
This applies to upstream wrapper charts too. Setting `affinity` in `values.yaml` is not
sufficient — verify the rendered output actually contains `podAntiAffinity`. If the upstream
chart does not propagate it, add a dedicated affinity template that merges the required rule.

For distributed-mode charts (Loki Simple Scalable, Tempo distributed), the upstream chart
generates one PDB per component (ingester, distributor, querier, etc.). Count must be >= number
of deployed components, not just >= 1. Use `grep -c PodDisruptionBudget` and verify the count
is reasonable for the chart's component topology.

**Bitnami subchart PDB**: when a bitnami/upstream subchart provides PDB by default, still add a
wrapper-level `templates/poddisruptionbudget.yaml` and disable the subchart PDB with
`<subchart>.pdb.create: false` to avoid duplicate PDB selectors.

**ArgoCD apps**: every Application manifest must have `spec.revisionHistoryLimit: 3`. Omitting it
causes review failure. Validate YAML with `yq e '.'` (not `kubectl apply --dry-run` — ArgoCD CRDs
are not installed locally).

**shellcheck**: all `.sh` files must pass `shellcheck -S error` (matches CI's shellcheck 0.10.0).
Common fixes:
- Quote variables: `"$var"` not `$var`
- Split `local` + command substitution: `local x; x=$(cmd)` — not `local x=$(cmd)` (SC2155)
- Empty array safety: `"${ARRAY[@]+"${ARRAY[@]}"}` instead of `"${ARRAY[@]}"` with `set -u`
- Don't source `interface.sh` (has `exit 1` stubs that fire SC2317 unreachable code)

**vendor scripts**: every script in `vendor/*.sh` must support both `--dry-run` AND `--backup`
flags. CI checks for both with grep. Missing either causes CI failure.

**Observability charts with Grafana integration**: include a Grafana datasource ConfigMap in
`charts/<name>/templates/`. This is required for the chart to auto-register in Grafana.
Gate: `helm template charts/<name>/ | grep -i datasource` must exit 0.

---

## How to implement a story

1. Read the story from the active sprint file
2. Check out the branch named in `branchName` (create from `main` if it doesn't exist)
3. Implement the acceptance criteria — nothing more, nothing less
4. Run quality gates before marking `passes: true`:
   - `helm lint charts/<name>/` if you touched a chart
   - HA gate (PDB, podAntiAffinity, replicaCount) if you touched a chart
   - `helm template charts/<name>/ | grep -i datasource` if you added an observability chart
   - `shellcheck -S error <file>.sh` if you touched a shell script
   - `yq e '.' <file>.yaml` if you touched ArgoCD manifests
   - `yq '.spec.revisionHistoryLimit' argocd-apps/<tier>/<name>-app.yaml` — must equal 3
5. Set `passes: true` in the sprint file
6. Push the branch, open a PR, wait for CI to pass, merge to main

Do not mark `passes: true` if any gate fails. Do not self-certify — gates will re-run.

---

## What the ceremonies do (not your job)

- **Smoke test**: runs `helm lint` + `shellcheck` + `yq` across the whole repo
- **Proof of work**: checks your branch is pushed and PR is merged to main
- **Review**: adversarially checks your acceptance criteria
- **Retro**: closes the sprint, returns incomplete work to backlog with 5 Whys
- **Advance**: moves the phase pointer in manifest.json

You implement. Ceremonies verify. Don't conflate the two.

---

## Current platform state

Phases complete: 0 (ceremonies), 1 (bootstrap), 2 (foundations), 2h (ci-hardening),
2i (integration), 3 (gitops-engine), 4 (autarky), 5 (security), 6 (observability)

Phase active: none (between sprints — advance will activate 7)

Phases pending: 7 (devex), 8 (testing-and-ha), 9 (sovereign-pm)

Epics complete: E1–E10 (all through observability)
Epics backlog: E11 (developer portal), E12 (code quality), E13 (testing infra),
               E14 (sovereign-pm), E15 (HA validation)

---

## Known model inconsistencies

- `phase` (int) field on stories is redundant with `epicId` — two sources of truth that can drift → story 040 will remove it
- "phase" and "sprint" and "increment" used interchangeably across ceremonies.py, manifest.json, and sprint files → story 040 will standardize on "increment"
- `advance.py` uses `int(current_phase) + 1` arithmetic — breaks on non-integer IDs like "2h", "2i" → story 040 will fix to use ordered list position
- Increment names describe install order ("bootstrap", "foundations") not product capability milestones → story 040 will add `themeGoal` to each increment

---

## Hard stops — do not proceed if any of these are true

- A Tier 1 component (CNI, storage, PKI, secret store, service mesh, policy engine) is sourced
  from a vendor-controlled project → flag to retro, do not implement
- A secret is about to be committed in plain text → stop immediately
- A chart hardcodes a domain name or IP address in `templates/` → fix before marking passes: true
- A shellcheck error is present → fix before marking passes: true
- An ArgoCD Application is missing `revisionHistoryLimit: 3` → fix before marking passes: true
- HA gate fails (PDB, podAntiAffinity, or replicaCount < 2) → fix before marking passes: true
