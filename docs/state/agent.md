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

**Domain**: always `{{ .Values.global.domain }}` in Helm templates. Never a literal domain string.

**Storage class**: always `{{ .Values.global.storageClass }}`. Never `standard` or `ceph-block` literal.

**Secrets**: never in plain text, never committed. Use Sealed Secrets for GitOps, Vault references for runtime.

**Namespaces**: each service gets its own namespace. Never deploy into `default`.

**Helm chart structure**: every chart needs `Chart.yaml`, `values.yaml`, `templates/`. Run
`helm dependency update` before `helm lint` when `Chart.yaml` has dependencies.

**shellcheck**: all `.sh` files must pass `shellcheck`. Common fixes:
- Quote variables: `"$var"` not `$var`
- Use `${var//search/replace}` not `echo "$var" | sed`
- Avoid `SC2086` by double-quoting all variable expansions

**ArgoCD apps**: validate with `yq e '.'` not `kubectl apply --dry-run` — ArgoCD CRDs are not
installed in the local environment.

---

## How to implement a story

1. Read the story from the active sprint file
2. Check out the branch named in `branchName` (create from `main` if it doesn't exist)
3. Implement the acceptance criteria — nothing more, nothing less
4. Run quality gates yourself before marking `passes: true`:
   - `helm lint charts/<name>/` if you touched a chart
   - `shellcheck <file>.sh` if you touched a shell script
   - `yq e '.' <file>.yaml` if you touched ArgoCD manifests
5. Set `passes: true` in the sprint file
6. Push the branch, open a PR

Do not mark `passes: true` if any gate fails. Do not self-certify — gates will re-run.

---

## What the ceremonies do (not your job)

- **Smoke test**: runs `helm lint` + `shellcheck` + `yq` across the whole repo
- **Proof of work**: checks your branch is pushed and PR is open
- **Review**: adversarially checks your acceptance criteria
- **Retro**: closes the sprint, returns incomplete work to backlog with 5 Whys
- **Advance**: moves the phase pointer in manifest.json

You implement. Ceremonies verify. Don't conflate the two.

---

## Current platform state

Phases complete: 0 (ceremonies), 1 (bootstrap), 2 (foundations), 2h (ci-hardening),
2i (integration), 3 (gitops-engine), 5 (security), 6 (observability)

Phase active: 4 (autarky) — Crossplane compositions and platform self-management

Phases pending: 7 (devex), 8 (testing-and-ha), 9 (sovereign-pm)

Active epics: E7, E8 — in-progress work
Backlog epics: E9–E15 — awaiting stories or sprint pull

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
- A chart hardcodes a domain name or IP address → fix before marking passes: true
- A shellcheck error is present → fix before marking passes: true
