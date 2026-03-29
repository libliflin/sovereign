# SMART Check Ceremony

You are running the **SMART check ceremony** for the Sovereign Platform.

SMART criteria for a sprint story:
- **Specific** — Describes exactly what to build. No ambiguity about scope.
- **Measurable** — Has concrete, binary acceptance criteria that can be verified by running commands.
- **Achievable** — Can realistically be completed in one Ralph iteration (~2000 tokens of output, ~1-3 files changed).
- **Relevant** — Directly advances the active sprint goal and the platform architecture.
- **Time-bound** — Is scoped to a single story with no open-ended "and also..." extensions.

## Your task

Read the **active sprint file** (find it via `prd/manifest.json` → `activeSprint`) and score every
story against the SMART criteria.

### Step 1 — Find and read the active sprint

```bash
cat prd/manifest.json
# Then read the file at .activeSprint, e.g.:
cat prd/increment-0-ceremonies.json
```

### Step 2 — Score each story

For each story in the sprint, evaluate each SMART dimension on a scale of 1–5:

| Score | Meaning |
|-------|---------|
| 5 | Excellent — no issues |
| 4 | Good — minor gap but still sprint-ready |
| 3 | Acceptable — borderline, proceed with caution |
| 2 | Weak — this story needs work before it can be implemented reliably |
| 1 | Poor — story is not implementable as written |

**Scoring guidance:**

*Specific (5)*: Every file to create is named. Every tool/chart/version is specified. A developer
could start without asking any clarifying questions.
*Specific (3)*: The general direction is clear but 1-2 details are left open.
*Specific (1)*: Could be interpreted multiple ways.

*Measurable (5)*: Every AC is a binary shell command or file check with a clear pass/fail.
*Measurable (3)*: Most ACs are verifiable but 1-2 are vague ("works", "is correct").
*Measurable (1)*: ACs are descriptive but not verifiable.

*Achievable (5)*: Clearly doable in one Ralph iteration.
*Achievable (3)*: Might be tight at the top of the points budget.
*Achievable (1)*: Clearly too large for one story (multiple charts, multiple providers, etc.).

*Relevant (5)*: Directly required by the current sprint goal.
*Relevant (3)*: Useful but could be deferred without blocking the sprint goal.
*Relevant (1)*: Nice-to-have or belongs in a different phase.

*Time-bound (5)*: Story has a clear end state with no scope creep opportunities.
*Time-bound (3)*: Has 1 vague "and also..." that could expand scope.
*Time-bound (1)*: Open-ended — "and any other improvements needed".

### Step 3 — Write scores back to the sprint file

For each story, update the `smart` object in the sprint file with your scores and a note:

```json
"smart": {
  "specific":   4,
  "measurable": 5,
  "achievable": 4,
  "relevant":   5,
  "timeBound":  5,
  "notes": "Specific score 4: does not specify which K3s version to install. Achievable score 4: three provider scripts in one story is near the top of the budget."
}
```

**Notes field:** Only include notes when a dimension scores < 5. Be specific about *what* is missing.
If all dimensions are 5, write `"notes": "All SMART dimensions green."`.

Use Python or jq to update the sprint file in place. Example with Python:

```python
import json

with open('prd/increment-0-ceremonies.json') as f:
    sprint = json.load(f)

# Update smart fields for each story...
for story in sprint['stories']:
    story['smart'] = { ... }  # your scores

with open('prd/increment-0-ceremonies.json', 'w') as f:
    json.dump(sprint, f, indent=2)
```

### Step 4 — Flag not-ready stories

A story is **not sprint-ready** if any SMART dimension scores < 3.

For each not-ready story, add a specific improvement note to `smart.notes` explaining:
1. Which dimension(s) failed
2. Exactly what needs to be added or changed to bring the score to >= 3

### Step 5 — Print summary table

After updating the sprint file, print this summary to stdout:

```
=== SMART Check: prd/increment-0-ceremonies.json ===

Story  | S | M | A | R | T | Status
-------|---|---|---|---|---|-------
P0-001 | 5 | 5 | 5 | 5 | 5 | READY
P0-002 | 4 | 5 | 4 | 5 | 5 | READY
P0-003 | 3 | 3 | 5 | 5 | 5 | READY (borderline)
P0-004 | 2 | 3 | 5 | 5 | 5 | NOT READY — see smart.notes

Sprint-ready: 3/4 stories
Not-ready   : 1/4 stories (P0-004)
Action needed: Refine P0-004 before sprint execution. See smart.notes for details.
```

## Shell script quality gates (apply when scoring Achievable/Measurable)

### Chart-iterating scripts must be tested against the real corpus

Any shell script story whose description mentions iterating `platform/charts/` **must include**
"run against all existing charts in `platform/charts/`" as an explicit acceptance criterion —
not just a synthetic fixture chart. Mark `achievable ≤ 3` if this criterion is missing.

The real chart corpus contains edge cases that synthetic fixtures will not expose:
- Charts with no top-level `replicaCount` field (e.g. `platform/charts/_globals/`)
- Underscore-prefixed directories that are not deployable services

If an AC only covers a freshly-created test chart, the script has not been validated against
the actual platform and will likely fail review.

### `set -euo pipefail` + grep on optional YAML fields is a hard failure mode

When a shell script uses `set -euo pipefail` and runs `grep` for an optional YAML field
(e.g. `replicaCount`), the grep will exit 1 when the field is absent. With `pipefail`, this
kills the script silently — no error message, no FAIL output, just a non-zero exit.

**Required fix**: always use `|| true` on grep pipelines where the field may be absent:

```bash
# BAD — script dies silently on charts without replicaCount
replica_count="$(grep -E '^replicaCount:' "$values" | awk '{print $2}')"

# GOOD — script continues; empty result handled by subsequent -z check
replica_count="$(grep -E '^replicaCount:' "$values" | awk '{print $2}' || true)"
```

Mark `achievable ≤ 3` for any story whose shell script iterates `platform/charts/` and whose
test plan does not include running against the full chart corpus. The real corpus will expose
this bug; a synthetic fixture will not.

## Important constraints

- Write SMART scores directly into the active sprint file. This is the only file you modify.
- Do not modify `prd/backlog.json` or `prd/manifest.json`.
- If a story already has non-zero SMART scores, re-evaluate them — do not blindly preserve prior scores.
- A score of 0 in any dimension means "not yet scored". Treat 0 as if the dimension needs evaluation.
