# Retro Patch: Phase 5 — security
Generated: 2026-03-23T22:00:00Z

## Suggested additions to CLAUDE.md (LEARNINGS section)

### New patterns discovered this sprint

- **ArgoCD app `revisionHistoryLimit: 3` is mandatory on all security-tier apps**: The review
  ceremony checks for this field in every ArgoCD Application manifest. Omitting it causes a
  review failure. Always include `spec.revisionHistoryLimit: 3` in every `argocd-apps/security/`
  manifest (and by extension all tier manifests).

- **HA gate applies to upstream wrapper charts too**: Even when wrapping an upstream Helm chart
  (e.g. `kiali/kiali-operator`, `aquasecurity/trivy-operator`, `falcosecurity/falco`), the
  Sovereign chart must inject its own PDB and podAntiAffinity into the values or templates.
  The review ceremony does not exempt upstream wrappers — it checks `helm template` output for
  `PodDisruptionBudget` and `podAntiAffinity` regardless of chart origin.

- **`podAntiAffinity` must appear in the rendered output, not just in values**: Setting
  `affinity` in values.yaml is insufficient if the upstream chart's template does not propagate
  it. Either verify via `helm template | grep -A5 podAntiAffinity` before marking a story done,
  or add a dedicated affinity template that merges the upstream values with the required
  anti-affinity rule.

- **PDB is required on kiali, trivy-operator, falco**: These charts were initially shipped
  without PodDisruptionBudget resources. The HA gate flags this on every chart, not just
  "critical" ones. All charts with `replicaCount >= 1` need a PDB with `minAvailable: 1`.

- **Pre-verify HA gate before pushing**: Run this check before every `git push` on a chart story:
  ```bash
  helm template charts/<name>/ | grep -c PodDisruptionBudget   # must be >= 1
  helm template charts/<name>/ | grep -c podAntiAffinity        # must be >= 1
  grep replicaCount charts/<name>/values.yaml                   # must be >= 2
  ```
  These three checks are what the review ceremony runs. If any return 0 or < 2, fix before pushing.

## Stories that failed review (re-opened)

| Story | Attempts | Root cause |
|-------|----------|------------|
| 023a (istio-core) | 1 | Missing `revisionHistoryLimit: 3` in istio ArgoCD app; missing `podAntiAffinity` in istiod deployment |
| 024a (opa-gatekeeper) | 1 | Missing `revisionHistoryLimit: 3` in gatekeeper ArgoCD app; missing `podAntiAffinity` |
| 024b (trivy-operator) | 1 | Missing PDB and `podAntiAffinity`; missing `revisionHistoryLimit: 3` in ArgoCD app |
| 024c (falco) | 1 | Missing PDB and `podAntiAffinity`; missing `revisionHistoryLimit: 3` in ArgoCD app |

All four failures were fixed in a single follow-up commit (PR #15). The root cause is the same
across all four: the HA gate requirements for upstream wrapper charts were not applied at initial
implementation.

## Quality gate improvements suggested

1. **Add a pre-push HA checklist to the story template**: Every chart story should include a
   mandatory checklist item before `passes: true` is set:
   - `helm template | grep -c PodDisruptionBudget` ≥ 1
   - `helm template | grep -c podAntiAffinity` ≥ 1
   - `yq '.spec.revisionHistoryLimit' argocd-apps/<tier>/<name>-app.yaml` = 3
   This would catch all four phase-5 failures before the first review attempt.

2. **Distinguish "HA in own templates" from "HA via upstream values"**: When wrapping upstream
   charts, the common failure mode is setting affinity/PDB in `values.yaml` and trusting the
   upstream chart will render it. Add an explicit note in CLAUDE.md: verify rendered output,
   not just values.

3. **`revisionHistoryLimit` should be in the ArgoCD app template or snippet**: Since this
   field must appear on every ArgoCD Application, consider adding it to the ArgoCD app
   CLAUDE.md snippet so it is never omitted by default.

## Velocity note

Sprint points: 12 / 12 completed
Review pass rate: 20.0% (1 of 5 stories accepted on first review — lowest sprint on record)

The 20% first-review pass rate is a regression from phase 4 (80%). However, all 5 stories were
fixed within a single follow-up commit, suggesting the failures were clustered around one missed
HA pattern rather than multiple independent issues. The actual rework cost was low — one PR fixed
all four re-opens simultaneously.

Trend across completed phases:
- Phase 0 (ceremonies):    15 pts, 100% first-review pass
- Phase 1 (bootstrap):     14 pts, 100% first-review pass
- Phase 2h (ci-hardening):  5 pts,  75% first-review pass  (1 re-open)
- Phase 2 (foundations):   10 pts,  75% first-review pass  (1 re-open)
- Phase 3 (gitops-engine):  5 pts, 100% first-review pass
- Phase 4 (autarky):       13 pts,  80% first-review pass  (1 re-open)
- Phase 5 (security):      12 pts,  20% first-review pass  (4 re-opens, same root cause)

Cumulative: 74 pts delivered across 7 phases.
Action: Apply the HA pre-push checklist pattern from this retro to prevent recurrence in phase 6+.
