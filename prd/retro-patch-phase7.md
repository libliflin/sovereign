# Retro Patch: Phase 7 — devex
Generated: 2026-03-24T22:30:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 1 | 2 pts |
| Incomplete → backlog | 1 | 3 pts |
| Killed | 0 | — |

Sprint capacity: 15 pts. Delivered: 2 pts. Velocity: 13%.

---

## 5 Whys: incomplete stories

### 029: Helm charts — SonarQube and ReportPortal

- **Why 1**: Story didn't pass review on attempt 2 → HA gate AC #12 failed: `replicaCount: 1` in charts/sonarqube/values.yaml
- **Why 2**: SonarQube Community Edition is architecturally single-instance — it does not support horizontal pod scaling; the CE chart hardcodes `replicas: 1` at the subchart level
- **Why 3**: The implementing agent re-attempted the story on attempt 2 without applying the specific fix from `reviewNotes[0]`, which clearly described both fix options: (a) switch to DCE, or (b) add `ha_exception` in vendor/VENDORS.yaml and a documented top-level `replicaCount: 1`
- **Why 4**: The CLAUDE.md instruction "Fix only what the reviewNotes describe" was present but not followed — the agent re-implemented the full story rather than applying the targeted single-line fix
- **Why 5**: The quality gate for HA (gate #12: `replicaCount >= 2`) has no documented exception pathway in the quality gate checklist itself — the exception process lives only in CLAUDE.md text, not as a structured gate step, so it is easy to overlook when re-running gates

**Root cause**: The HA quality gate has no machine-readable exception process. Single-instance upstream services (SonarQube CE, MailHog, etc.) will always fail gate #12 unless an exception is explicitly documented. The reviewNote described the exact fix, but without a structured exception mechanism, the agent repeated the same mistake on attempt 2.

**Decision**: Return to backlog. Story is 3 pts and the fix is a targeted one: add `ha_exception: true` entry in vendor/VENDORS.yaml for SonarQube CE and update `charts/sonarqube/values.yaml` to have a top-level `replicaCount: 1` with a comment referencing the exception entry.

**Remediation story**: `041r` — Document and enforce HA exception process in quality gate #12

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Single-instance upstreams need an explicit exception path**: SonarQube CE, MailHog, single-shard Elasticsearch — any upstream that architecturally cannot scale horizontally will fail HA gate #12. The fix is not to switch charts; it is to document the exception in vendor/VENDORS.yaml and add a top-level `replicaCount: 1` with a machine-readable comment. Quality gate #12 should be updated to check for this exception before failing.

- **ReviewNotes must be read before any re-attempt, not after**: When `attempts > 0`, the reviewNotes contain the exact fix. The agent's second pass on story 029 re-implemented the chart from scratch instead of applying the single targeted fix. Any re-attempt after review failure should start by summarising the specific change requested in reviewNotes and implementing only that.

- **Two stories is too small a sprint**: Phase 7 had only 2 stories (capacity 15 pts). The sprint was under-planned relative to capacity. The grooming ceremony should flag sprints where stories < capacity/5 and prompt for additional stories from the backlog.

---

## Quality gate improvements

**Gate #12 (replicaCount >= 2) — add exception check:**

Current gate:
> 12. Default `replicaCount` in values.yaml is >= 2

Proposed addition:
> 12. Default `replicaCount` in values.yaml is >= 2.
>     **Exception**: If `vendor/VENDORS.yaml` contains `ha_exception: true` for this service with a `ha_exception_reason`, then `replicaCount: 1` is acceptable. Gate passes only if the exception entry exists AND the chart has a top-level `replicaCount: 1` with a comment referencing the VENDORS.yaml entry. Undocumented `replicaCount: 1` always fails.

---

## Velocity

| Phase | Points | Stories Accepted | Pass Rate |
|-------|--------|-----------------|-----------|
| 0 — ceremonies | 15 | — | 100% |
| 1 — bootstrap | 14 | — | 100% |
| 2 — foundations | 10 | 4 | 75% |
| 2h — ci-hardening | 5 | 4 | 100% |
| 2i — integration | 13 | — | 100% |
| 3 — gitops-engine | 12 | 2 | 100% |
| 4 — autarky | 13 | 5 | 80% |
| 5 — security | 12 | 5 | 20% |
| 6 — observability | 8 | 4 | 100% |
| **7 — devex** | **2** | **1** | **0%** |

Sprint velocity is the lowest yet (2 pts). Contributing factors:
1. Sprint was under-loaded (only 2 stories vs 15 pt capacity)
2. The one incomplete story (029, 3 pts) failed review twice — preventable with the HA exception process
3. code-server (028) failed its first review (attempts: 1), adding latency

Retro patch → prd/retro-patch-phase7.md
