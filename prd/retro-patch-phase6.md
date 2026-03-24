# Retro Patch: Phase 6 — Observability
Generated: 2026-03-24T00:00:00+00:00 (final — overrides early-close draft)

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 4 | 8 pts |
| Incomplete → backlog | 0 | — |
| Killed | 0 | — |

All 4 stories accepted. Sprint fully delivered.

**Note**: A prior early-close retro ran before any implementation occurred (storiesAccepted=0). This
patch supersedes that draft. The actual sprint completed with 100% delivery after stories 026a, 026b,
and 026c were implemented and reviewed.

## 5 Whys: incomplete stories

No incomplete stories. All acceptance criteria verified and reviewed.

## Flow analysis

| Metric | Value |
|--------|-------|
| Sprint avg story size | 2.0 pts |
| Point distribution | {2: 4} |
| Oversized (> 8 pts) | 0 |
| Split candidates (5–8 pts) | 0 |

Story sizing was consistent at 2 pts across all 4 stories. No oversizing. The chart-per-upstream
pattern (one Helm chart wrapping one upstream, ~2 pts) is validated and repeatable.

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Chart-per-upstream at 2 pts is the right unit**: Wrapping one upstream Helm chart with sovereign
  HA defaults, a Grafana datasource ConfigMap, and an ArgoCD app file consistently fits in 2 story
  points. Use this as the baseline estimate for all Phase 7–9 chart stories.
- **Datasource ConfigMap is standard boilerplate**: Every observability chart includes a Grafana
  datasource ConfigMap in `charts/<name>/templates/`. Add this as a checklist item in the grooming
  ceremony for any chart integrating with Grafana.
- **Prior retro ran mid-sprint with stale data**: The phase 6 sprintHistory entry was first written
  when 0 stories had been implemented. The retro ceremony's idempotency guard (don't double-append)
  prevented it from self-correcting. The guard should allow *updating* a stale entry rather than
  simply skipping re-execution.
- **SMART achievable=4 did not block delivery**: Stories 026a–026c had achievable=4 due to unpinned
  upstream versions. In practice, Ralph correctly chose specific versions without issue. The achievable
  score threshold for blocking should stay at ≤ 3; score 4 is acceptable risk.

## Quality gate improvements

- **Pinned upstream versions in ACs**: Stories 026a–026c said "pin appVersion to a specific release
  (e.g. X.Y.Z)" rather than naming a specific version. Future stories should either require a named
  version or reference `vendor/recipes/<name>/recipe.yaml` for the canonical version.
- **Stronger datasource grep**: `helm template | grep -i 'datasource'` will match a YAML comment.
  Use `helm template | grep 'kind: ConfigMap' -A 20 | grep datasource` or check a specific label/key
  to make the gate objectively verifiable.
- **Retro idempotency should update, not skip**: When a sprintHistory entry already exists, compare
  the stored vs. computed values; if they differ, overwrite the entry. "Don't double-append" should
  not mean "preserve stale data."

## Velocity

| Phase | Points completed | Stories accepted | Review pass rate |
|-------|-----------------|-----------------|-----------------|
| 0 (ceremonies) | 15 | 7 | 100% |
| 1 (bootstrap) | 14 | 6 | 100% |
| 2 (foundations) | 10 | 4 | 75% |
| 2h (ci-hardening) | 5 | 4 | 100% |
| 2i (integration) | 13 | — | 100% |
| 3 (gitops-engine) | 12 | 2 | 100% |
| 4 (autarky) | 13 | 5 | 80% |
| 5 (security) | 12 | 5 | 20% |
| **6 (observability)** | **8** | **4** | **100%** |

Sprint points accepted: 8 / 8
First-review pass rate: 100% (4 of 4, all accepted on first attempt, attempts=0)

Retro patch → prd/retro-patch-phase6.md
