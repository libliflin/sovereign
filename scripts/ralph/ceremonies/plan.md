# Sprint Planning Ceremony

You are running the **sprint planning ceremony** for the Sovereign Platform.

This ceremony populates the next pending increment sprint file from the backlog.

## Your task

### Step 1 — Find the next pending increment

Read `prd/manifest.json` and find the next increment with `status: "pending"`:

```bash
cat prd/manifest.json
```

Look at the `increments` array. Find the first entry where `status` is `"pending"`. Note its `id`,
`name`, `file`, and `capacity` (default 15 if not set). Call this **NEXT_INCREMENT**.

If no pending increments exist, print "All increments are active or complete. Nothing to plan." and exit.

### Step 2 — Read the backlog

```bash
cat prd/backlog.json
```

Find all stories whose `epicId` maps to an epic targeting `NEXT_INCREMENT.id` (check `prd/epics.json`
`targetIncrement` field), ordered by `priority` (ascending).
These are the **candidate stories** for this sprint.

### Step 3 — Assign story points and enforce hard limits

**Hard limit: stories > 8 points are REJECTED from planning. They must be split.**

For each candidate story, verify or assign `points` using this rubric:

| Points | When to use |
|--------|-------------|
| 1–2 | Trivial to standard — a config change, single Helm chart, or small script |
| 3–5 | Complex — multi-file feature, chart with dependencies, or non-trivial script |
| 6–8 | Large but legal — flag as split candidate in grooming notes |
| > 8  | **ILLEGAL — must not enter sprint. Add readinessNote and leave in backlog.** |

```python
import json
with open('prd/backlog.json') as f:
    backlog = json.load(f)

STORY_MAX_POINTS = 8

rejected = []
for s in backlog.get('stories', []):
    if isinstance(s.get('points'), int) and s['points'] > STORY_MAX_POINTS:
        s['readinessNote'] = f"REJECTED: {s['points']} pts exceeds hard limit of {STORY_MAX_POINTS}. Must be split before planning."
        rejected.append(s['id'])

if rejected:
    with open('prd/backlog.json', 'w') as f:
        json.dump(backlog, f, indent=2)
    print(f"Rejected {len(rejected)} oversized stories: {rejected}")
```

### Step 4 — Compute WIP ceiling from velocity

```python
with open('prd/manifest.json') as f:
    manifest = json.load(f)

velocity = manifest.get('velocity', [])
DEFAULT_SPRINT_POINTS = 12  # used when no velocity history

if velocity:
    recent = velocity[-3:]
    wip_ceiling = round(sum(v.get('pointsCompleted', 0) for v in recent) / len(recent))
else:
    wip_ceiling = DEFAULT_SPRINT_POINTS

print(f"WIP ceiling: {wip_ceiling} pts (from last {min(len(velocity), 3)} sprints avg)")
```

The sprint cannot exceed `wip_ceiling` total points. This is not a soft guideline — it is the capacity
constraint derived from actual delivery history. Do not override it.

### Step 5 — Check definition of ready

For each candidate story, verify all of the following:

1. **Description is specific** — Could a developer start without asking a question?
   Flag if vague. Add `readinessNote` explaining what is missing.

2. **All ACs are verifiable** — Each AC must be a binary pass/fail check (a command or a file check).
   Phrases like "works correctly" or "is set up" fail this check.

3. **testPlan exists and is non-trivial** — Must describe actual commands, not just "verify ACs".

4. **Dependencies are resolved** — All IDs in `dependencies[]` must exist in `prd/backlog.json` or in
   a sprint file with `passes: true`. If a dependency is unresolved, add a `readinessNote`.

5. **Points ≤ 8** — Stories over 8 pts are already rejected (Step 3). Stories 6–8 pts are legal but
   flagged as split candidates — note them in the sprint plan.

A story is **ready** if it passes all five checks. Otherwise add a `readinessNote` field with the
specific issue and leave it in the backlog.

### Step 6 — Select stories for the sprint (respect WIP ceiling)

Collect all **ready** candidate stories, ordered by `priority` (ascending).
Add stories until the next story would exceed `wip_ceiling` total points.

- Priority-0 stories are pulled first, regardless of phase or WIP ceiling.
- If a story would push the total over the ceiling, skip it and continue checking remaining stories
  (a 2-point story may fit even if a 5-point story didn't).
- Record why each skipped story was not included (over WIP / not ready / oversized).

### Step 6 — Write the increment sprint file

Write the sprint file at the path defined in `NEXT_INCREMENT.file` (e.g. `prd/increment-7-devex.json`):

```json
{
  "increment": <NEXT_INCREMENT.id>,
  "name": "<NEXT_INCREMENT.name>",
  "description": "<NEXT_INCREMENT.description>",
  "sprintGoal": "<one sentence: what does 'done' look like for this sprint>",
  "capacity": <NEXT_INCREMENT.capacity or 15>,
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
- Set `increments[NEXT_INCREMENT.id].status` → `"active"`
- Set `increments[NEXT_INCREMENT.id].startDate` → current UTC timestamp
- Set `increments[NEXT_INCREMENT.id].pointsTotal` → total points of selected stories
- Set `increments[NEXT_INCREMENT.id].storiesTotal` → count of selected stories
- Set `activeSprint` → `NEXT_INCREMENT.file`
- Set `currentIncrement` → `NEXT_INCREMENT.id`

**Only update manifest if the current increment is already `status: "complete"` OR if no increment is
currently active.** Do not change manifest if an increment is still `status: "active"`.

### Step 9 — Print sprint planning summary

```
=== Sprint Planning: Increment <N> — <name> ===
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
