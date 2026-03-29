# Retro Patch: Increment 23 — pending-stub
Generated: 2026-03-29T23:02:47Z

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 8 | 11 pts |
| Incomplete → backlog | 1 | 2 pts |
| Killed | 0 | — |

## 5 Whys: incomplete stories

### HA-001: HA gate script validates all platform charts have replicaCount>=2, PDB, and podAntiAffinity

- **Why 1:** Story failed review after 2 attempts → script exits early when processing `platform/charts/_globals/`, which has no top-level `replicaCount:` field
- **Why 2:** Script uses `set -euo pipefail`; the bare `grep -E '^replicaCount:' ... | awk ...` pipeline exits with code 1 when grep finds no match, triggering `errexit` and killing the script silently
- **Why 3:** macOS bash 3.2 (the test environment) propagates failed subshell pipeline exit codes strictly under `pipefail`; the story assumed bash behavior consistent with newer GNU bash
- **Why 4:** The test plan only specified creating a synthetic fixture chart with `replicaCount: 1` — it never required running the script against all _existing_ charts before marking the story done
- **Why 5:** The SMART "measurable" and "achievable" checks approved the test plan without requiring that chart-iterating scripts be validated against the real chart corpus (not just synthetic fixtures)

**Root cause:** Shell script stories that iterate `platform/charts/` only required synthetic fixture tests in their acceptance criteria. When a chart in the real corpus (here: `_globals`) lacks the field being grepped, `set -euo pipefail` kills the script with no output. This gap was not caught by the SMART achievable/measurable scoring.

**Decision:** Return to backlog as-is — the exact fix (`|| true` guard on the grep pipeline) is documented in `reviewNotes[1]`. Story is well-scoped and valuable; it needs one more attempt with the fix applied.

**Remediation story:** KAIZEN-012 — "Chart-iterating shell scripts must be validated against all existing platform/charts before passes:true"

---

## Flow analysis

| Metric | Value |
|--------|-------|
| Sprint avg story size | 1.4 pts |
| Point distribution | {1: 5, 2: 4} |
| Oversized (> 8 pts) | 0 |
| Split candidates (5–8 pts) | 0 |

No grooming concerns. All stories were 1–2 pts. No oversized stories entered the sprint.

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **`set -euo pipefail` + grep on optional YAML fields is a footgun.** Any shell script that greps for an optional field in a YAML file must use `|| true` (e.g., `grep -E '^replicaCount:' file || true`). Without it, `pipefail` kills the script silently when the field is absent. The script appears to exit 0 with no output from the caller's perspective — a debugging nightmare.
- **Test against the real corpus, not only synthetic fixtures.** Shell script stories that iterate `platform/charts/` must validate against all existing charts _before_ creating synthetic test charts. The existing chart corpus contains edge cases (charts with no `replicaCount`, underscore-prefixed globals directories, etc.) that synthetic fixtures will not expose.
- **macOS bash 3.2 vs GNU bash 5.x behavior diverges under pipefail.** Treat macOS bash 3.2 as the target shell for all scripts until the dev environment explicitly standardises on a newer version. Document this constraint in the story's `testPlan` when relevant.

---

## Quality gate improvements

**Proposed AC addition for any story that creates a chart-iterating script:**
> "Run `<script>` (without any flags) against the existing platform/charts/ directory and confirm it produces PASS or FAIL output for every chart without error."

This should be added as an explicit bullet to the SMART ceremony's "measurable" and "achievable" scoring criteria when evaluating stories tagged with `epicId: E15` or stories whose description mentions iterating `platform/charts/`.

---

## Velocity

| Increment | Points Accepted | Stories Accepted | Review Pass Rate |
|-----------|----------------|-----------------|-----------------|
| 23        | 11             | 8 / 9           | 0.0%            |

_(First-review pass rate of 0% reflects that all accepted stories show `attempts: 1`. If `attempts: 1` means "first successful attempt", the counter semantics should be clarified — stories accepted on first submission should carry `attempts: 0`.)_

---

Retro patch → `prd/retro-patch-increment23.md`
