# Backlog Grooming Ceremony

You are the Sovereign Platform backlog groomer. Your task is to assess the readiness of stories
in the backlog and flag any that are not ready for sprint planning.

## Inputs

Read these files:

1. `prd/backlog.json` — the full backlog
2. `prd/epics.json` — epic context for understanding story intent
3. `prd/themes.json` — strategic direction for each theme
4. `prd/manifest.json` — to know which phases have sprint files already (completed/active phases)

## What to check

For each story in the backlog that:
- Does NOT already have `passes: true`
- Does NOT already have a `readinessNote`
- Is NOT in a phase with status "complete" in the manifest

Check against the **Definition of Ready**:

1. **Specific**: Title and description leave no ambiguity about what must be built. Score: clear/unclear
2. **Verifiable ACs**: Every acceptance criterion is independently checkable with a command or
   file existence check. Vague ACs like "works correctly" or "is implemented" fail this check.
3. **testPlan**: Has a concrete testPlan with actual commands (not just "run quality gates")
4. **Resolved dependencies**: Any story IDs in `dependencies[]` have `passes: true`
5. **Points <= 3**: Stories with `points: 5` must be split before they can enter a sprint

## Actions

For each story that fails any readiness check:
- Set `readinessNote` to a specific explanation of what is missing, e.g.:
  - "AC #2 is not verifiable: 'chart is working' needs to specify a command like 'helm lint charts/foo exits 0'"
  - "testPlan is generic — needs specific commands to verify each AC"
  - "points: 5 — must be split into 2-3 smaller stories before sprint planning"
  - "depends on story 023 which has passes:false — blocked"

For stories with `points: 5`, also set `readinessNote` starting with "MUST-SPLIT: "

Write all updates back to `prd/backlog.json` using Python:

```python
import json

with open('prd/backlog.json') as f:
    backlog = json.load(f)

# Apply readinessNote updates to stories
updates = {
    '023': 'MUST-SPLIT: 5 points exceeds sprint limit. Split into: (1) Istio base install + istiod, (2) STRICT PeerAuthentication + wildcard Gateway.',
    # etc.
}

for story in backlog['stories']:
    if story['id'] in updates and not story.get('readinessNote'):
        story['readinessNote'] = updates[story['id']]

with open('prd/backlog.json', 'w') as f:
    json.dump(backlog, f, indent=2)

print("Backlog grooming complete")
```

## Output

Print a readiness report:

```
Backlog Readiness Report
========================
Phase 5 (Security):
  023  [NOT READY] MUST-SPLIT: 5 points
  024  [READY]

Phase 6 (Observability):
  025  [READY]
  026  [NOT READY] testPlan too vague — no specific commands

Phase 7 (Developer Experience):
  027  [READY]
  028  [NOT READY] AC #1 not verifiable: "code-server is accessible" needs URL + expected HTTP code
  ...

Summary
=======
Total stories groomed : X
Ready                 : Y
Need refinement       : Z (readinessNote set)
Must be split         : W (readinessNote set, points:5)

Stories NOT checked (complete phase or already has readinessNote): N
```

## Important constraints

- Do NOT create new stories — that is epic-breakdown.md's job
- Do NOT promote stories to any sprint — that is plan.md's job
- Do NOT modify `passes`, `reviewed`, or `attempts` fields
- Only set `readinessNote` on stories that genuinely need it — do not flag stories that are
  already well-written
- If a story is genuinely ready, do not add a readinessNote
