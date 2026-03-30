# Retro Patch: Phase 24 — pending-stub
Generated: 2026-03-29T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 11 | 16 pts |
| Incomplete → backlog | 0 | — |
| Killed | 0 | — |

## 5 Whys: incomplete stories

_No incomplete stories. All 11 stories accepted._

## Flow analysis

| Metric | Value |
|--------|-------|
| Sprint avg story size | 1.5 pts |
| Point distribution | {1: 6, 2: 5} |
| Oversized (> 8 pts) | 0 |
| Split candidates (5–8 pts) | 0 |

No flow issues. Story sizing was well-controlled throughout the sprint. All work delivered
at 1–2 points per story, consistent with the platform's "thin slice" delivery model.

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **bash set -euo pipefail + grep pipelines**: Chart-iterating shell scripts must use
  `|| true` on grep pipelines to prevent silent script death when no match is found.
  KAIZEN-012 enshrined this in smart.md — apply the same guard to any future script
  that iterates a corpus where some entries may not have the searched field.

- **ArgoCD global.domain injection pattern**: The correct pattern for injecting cluster-wide
  config into ArgoCD-managed Helm charts is `spec.source.helm.parameters` with
  `name: global.domain` and `value: <domain>`. This is now applied to all 16 targeted
  app manifests across platform, observability, and security tiers.

- **Helm template AC gotcha**: When writing ACs that check `helm template` output for
  values referencing `.Values.*`, verify whether the check should use a resolved value
  (e.g. `storageClassName: standard`) or a Go template expression. The template is
  rendered — raw expressions like `{{ .Values.global.storageClass }}` will not appear
  in output. Use a known default value or the key name instead.

- **attempts: 1 vs first-pass metric**: The ceremony's first-pass formula uses
  `attempts == 0` which never matches accepted stories (all have `attempts >= 1`).
  This causes pass_rate to report 0% even when every story passed on the first review
  attempt. The formula should use `attempts == 1` to capture genuine first-pass
  success. Consider a KAIZEN story to fix this.

## Quality gate improvements

- The `attempts == 0` first-pass rate formula in the retrospective ceremony produces
  misleading 0% output when all stories pass on first attempt (`attempts: 1`). The
  formula should be updated to `attempts <= 1` or `attempts == 1` to accurately reflect
  first-pass success. Low-effort fix.

- KAIZEN-012 introduced the smart.md guard for chart-iterating scripts. Confirm the
  guidance is actually referenced in the SMART scoring rubric used by the plan ceremony.

## Velocity

| Sprint | Points | Stories | Pass Rate |
|--------|--------|---------|-----------|
| Increment 24 | 16 pts | 11/11 | 100% (11/11 first attempt) |

Sprint points accepted: 16 / 16 (plan ceiling: 9 per manifest — manifest was stale)
First-review pass rate: 100% (11/11 stories accepted on first review attempt — note: ceremony
formula reports 0% due to `attempts == 0` condition; actual data shows all stories attempts: 1)

Retro patch → prd/retro-patch-increment24.md
