# Sprint Planning Ceremony

You are running the **sprint planning ceremony** for the Sovereign Platform.

This ceremony populates the next pending phase sprint file from the backlog.

## Your task

### Step 1 — Find the next pending phase

Read `prd/manifest.json` and find the next phase with `status: "pending"`:

```bash
cat prd/manifest.json
```

Look at the `phases` array. Find the first entry where `status` is `"pending"`. Note its `id`,
`name`, `file`, and `capacity` (default 15 if not set). Call this **NEXT_PHASE**.

If no pending phases exist, print "All phases are active or complete. Nothing to plan." and exit.

### Step 2 — Read the backlog

```bash
cat prd/backlog.json
```

Find all stories where `phase == NEXT_PHASE.id`, ordered by `priority` (ascending).
These are the **candidate stories** for this sprint.

### Step 3 — Assign story points

For each candidate story, verify or assign `points` using this rubric:

| Points | When to use |
|--------|-------------|
| 1 | Trivial — a config file change, small script, or single template |
| 2 | Standard — a single Helm chart, a medium script, or a small multi-file change |
| 3 | Complex — multi-file feature, chart with multiple dependencies, or complex script |
| 5 | Must split — anything that would touch more than 3 files in unrelated areas |

If a story already has `points` set and the value seems correct, leave it.
If a story has `points: 5`, mark it `readinessNote: "Must be split before sprint planning. Run refine ceremony."` and leave it in the backlog.

### Step 4 — Check definition of ready

For each candidate story, verify all of the following:

1. **Description is specific** — Could a developer start without asking a question?
   Flag if vague. Add `readinessNote` explaining what is missing.

2. **All ACs are verifiable** — Each AC must be a binary pass/fail check (a command or a file check).
   Phrases like "works correctly" or "is set up" fail this check.

3. **testPlan exists and is non-trivial** — Must describe actual commands, not just "verify ACs".

4. **Dependencies are resolved** — All IDs in `dependencies[]` must exist in `prd/backlog.json` or in
   a sprint file with `passes: true`. If a dependency is unresolved, add a `readinessNote`.

5. **Points <= 3** — Stories with `points: 5` must not enter the sprint (handled in Step 3).

A story is **ready** if it passes all five checks. Otherwise add a `readinessNote` field with the
specific issue and leave it in the backlog.

### Step 5 — Select stories for the sprint (respect capacity)

Collect all **ready** candidate stories, ordered by `priority` (ascending).
Add stories to the sprint plan until the next story would exceed `capacity` total points.

- If a story would push the total over capacity, skip it and continue checking remaining stories
  (a 1-point story may fit even if a 3-point story didn't).
- Record why each skipped story was not included (over capacity / not ready).

### Step 6 — Write the phase sprint file

Write the sprint file at the path defined in `NEXT_PHASE.file` (e.g. `prd/phase-1-bootstrap.json`):

```json
{
  "phase": <NEXT_PHASE.id>,
  "name": "<NEXT_PHASE.name>",
  "description": "<NEXT_PHASE.description>",
  "sprintGoal": "<one sentence: what does 'done' look like for this sprint>",
  "capacity": <NEXT_PHASE.capacity or 15>,
  "stories": [
    <each selected story object, copied verbatim from backlog.json>
  ]
}
```

Each story in the sprint file must match the schema at `prd/schema/story.schema.json`.

### Step 7 — Update backlog.json

For stories that were **not ready**, add the `readinessNote` field to their entry in `prd/backlog.json`.
Do not remove any stories from the backlog. Do not change `passes` or `reviewed` fields.

Use Python to update the backlog:

```python
import json

with open('prd/backlog.json') as f:
    backlog = json.load(f)

for story in backlog['stories']:
    if story['id'] in not_ready_ids:
        story['readinessNote'] = "..."

with open('prd/backlog.json', 'w') as f:
    json.dump(backlog, f, indent=2)
```

### Step 8 — Update manifest.json

Update `prd/manifest.json`:
- Set `phases[NEXT_PHASE.id].status` → `"active"`
- Set `phases[NEXT_PHASE.id].startDate` → current UTC timestamp
- Set `phases[NEXT_PHASE.id].pointsTotal` → total points of selected stories
- Set `phases[NEXT_PHASE.id].storiesTotal` → count of selected stories
- Set `activeSprint` → `NEXT_PHASE.file`
- Set `currentPhase` → `NEXT_PHASE.id`

**Only update manifest if the current phase is already `status: "complete"` OR if no phase is
currently active.** Do not change manifest if a phase is still `status: "active"`.

### Step 9 — Print sprint planning summary

```
=== Sprint Planning: Phase <N> — <name> ===
Sprint goal: <one sentence>
Capacity   : <N> points

Stories committed (<total points> / <capacity> points):
  [priority] <id> — <title> (<points>pts)
  ...

Stories left in backlog:
  <id> — <title> — Reason: <not ready / over capacity>
  ...

Phase file written: prd/phase-<N>-<name>.json
Manifest updated : prd/manifest.json
```

## Important constraints

- Do not modify the active sprint file (if one exists) — only create or modify the NEXT phase file.
- Preserve all story fields when copying from backlog to sprint file. Do not strip any fields.
- The sprint file must be valid JSON and match `prd/schema/story.schema.json` for each story.
- Never set `passes: true` or `reviewed: true` during planning — those are set by Ralph and the review ceremony.
