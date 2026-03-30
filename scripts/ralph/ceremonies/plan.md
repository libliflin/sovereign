# Sprint Planning Ceremony

You are running the **sprint planning ceremony** for the Sovereign Platform.

This ceremony creates the sprint file for the current active increment (if its file is missing)
OR for the next pending increment (if no sprint file is needed).

## Your task

### Step 1 — Determine which increment to plan

Read `prd/manifest.json`:

```bash
cat prd/manifest.json
```

**Decision logic (in order):**

1. Read `currentIncrement` and `activeSprint` from the manifest.
2. Check whether the `activeSprint` file exists on disk:
   ```bash
   ls <activeSprint path>   # will error if missing
   ```
3. **If the file does NOT exist**: the currently active increment needs its sprint file created.
   Set `NEXT_INCREMENT` to the increment entry whose `id == currentIncrement`.
4. **If the file DOES exist** (or there is no `activeSprint`): Look in `increments[]` for
   the first entry where `status == "pending"`. Set `NEXT_INCREMENT` to that entry.
5. **If no pending increments exist**: check `prd/backlog.json` for any stories with
   `priority == 0` and `passes != true`. If any exist, this is a **remediation sprint** —
   go to **Step 1b** to create a new increment. If none exist, print
   "All increments complete and no priority-0 stories. Platform delivered." and exit.

> **CRITICAL**: Never plan for increment N+1 when the sprint file for increment N is missing.
> The file path is defined in `NEXT_INCREMENT.file`. Write that exact file — do not invent a path.

### Step 1b — Create a remediation increment (only if Step 1 finds no pending increment)

When orient pulls the Andon cord (broken GGE, priority-0 story) but all planned increments are
complete, the machine needs a new increment to carry the remediation work. Create it now.

```python
import json

with open('prd/manifest.json') as f:
    manifest = json.load(f)

increments = manifest.get('increments', [])

# Find the highest numeric increment id
numeric_ids = [i['id'] for i in increments if isinstance(i['id'], int)]
next_id = max(numeric_ids) + 1 if numeric_ids else 10

# Create the new remediation increment entry
new_inc = {
    "id": next_id,
    "name": "remediation",
    "description": "Remediation sprint — restores broken GGEs and resolves priority-0 blockers.",
    "file": f"prd/increment-{next_id}-remediation.json",
    "status": "active",
    "themeGoal": "Restore platform health: fix broken GGEs and unblock delivery.",
    "dependsOn": []
}
increments.append(new_inc)
manifest['increments'] = increments
manifest['activeSprint'] = new_inc['file']
manifest['currentIncrement'] = next_id

with open('prd/manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)

print(f"Created remediation increment {next_id}: {new_inc['file']}")
```

Set `NEXT_INCREMENT` to this new entry. Continue to Step 2.

### Step 2 — Read the terrain (Shi 勢)

Before reading stories, read the strategic situation. Shi is not velocity — it is
positioning. Where should we focus to get the most leverage from the least effort?

```python
import json
from collections import defaultdict
from pathlib import Path

with open('prd/manifest.json') as f:
    manifest = json.load(f)
with open('prd/constitution.json') as f:
    constitution = json.load(f)
with open('prd/epics.json') as f:
    epics = json.load(f)
with open('prd/backlog.json') as f:
    backlog = json.load(f)

themes = {t['id']: t['name'] for t in constitution.get('themes', [])}
epic_theme = {e['id']: e.get('themeId', '') for e in epics.get('epics', [])}

# Count accepted vs returned points per theme from sprint history
accepted = defaultdict(int)
returned = defaultdict(int)
for inc in manifest.get('increments', []):
    if inc.get('status') != 'complete':
        continue
    sf = Path(inc.get('file', ''))
    if not sf.exists():
        continue
    sprint = json.load(open(sf))
    for s in sprint.get('stories', []):
        tid = s.get('themeId') or epic_theme.get(s.get('epicId', ''), '')
        if not tid:
            continue
        pts = s.get('points', 1)
        if s.get('passes') and s.get('reviewed'):
            accepted[tid] += pts
        elif s.get('returnedToBacklog'):
            returned[tid] += pts

# Count unblocked stories per theme in the backlog
unblocked = defaultdict(list)
all_story_ids = {s['id'] for s in backlog.get('stories', [])}
for s in backlog.get('stories', []):
    if s.get('passes') or s.get('status') == 'killed':
        continue
    tid = s.get('themeId') or epic_theme.get(s.get('epicId', ''), '')
    deps = s.get('dependencies', [])
    blocked = any(
        d not in {st['id'] for st in backlog.get('stories', []) if st.get('passes')}
        for d in deps
    )
    if not blocked:
        unblocked[tid].append(s['id'])

print("=== Shi Reading ===")
for tid, name in sorted(themes.items()):
    a, r = accepted.get(tid, 0), returned.get(tid, 0)
    ub = unblocked.get(tid, [])
    print(f"  {tid} {name}: {a}pts accepted, {r}pts returned, {len(ub)} unblocked stories")
print()
```

Now answer these questions before selecting stories:
1. **Where is the leverage?** Which single story or chain, if completed, would unblock the
   most downstream work across all themes?
2. **Where is the energy?** Which themes have momentum and unblocked work ready to flow?
3. **Where should we NOT focus?** Which themes are blocked by long dependency chains that
   can't be resolved this sprint?

**Use this analysis to influence story selection in Step 6.** Don't just sort by priority
number — if the shi reading shows that a lower-priority story is the key to unblocking
10 other stories, pull it ahead of a higher-priority story that only unblocks itself.

### Step 3 — Read the backlog

```bash
cat prd/backlog.json
cat prd/epics.json
```

**Candidate stories:**
- If this is a remediation sprint (Step 1b): candidate stories are ALL stories with
  `priority == 0` and `passes != true`, regardless of `epicId`. These take precedence
  over everything.
- Otherwise: find all stories whose `epicId` maps to an epic whose
  `targetIncrement == NEXT_INCREMENT.id` (check `prd/epics.json`), ordered by `priority`
  (ascending).

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

### Step 6 — Select stories for the sprint (shi-informed, respect WIP ceiling)

**Use the shi reading from Step 2 to guide selection.** Priority numbers are a
starting point, but leverage matters more than priority. A story that unblocks 10
downstream stories is more valuable than a story that only completes itself, even
if its priority number is higher.

**E1 ceremony story cap:** Stories with `epicId == "E1"` improve the delivery machine,
not the platform. They have real value but must never crowd out product work. Apply this
hard rule:

1. Select all product stories (`epicId != "E1"`) first, up to WIP ceiling.
2. Only after product stories are selected, fill remaining capacity with E1 stories — **maximum 1 E1 story per sprint**, regardless of remaining capacity.
3. If there are no ready product stories at all (everything blocked), up to 3 E1 stories are allowed — but note this explicitly in the sprint summary as a signal to run groom and unblock the product pipeline.

Selection order:
1. **Priority-0 stories first** — pulled regardless of phase or WIP ceiling.
2. **Highest-leverage product stories** — from the shi analysis, which story or chain
   unblocks the most downstream work? Pull those next.
3. **Remaining ready product stories by priority** — fill remaining product capacity.
4. **E1 ceremony stories (max 1)** — fill any remaining capacity, highest priority first.

Add stories until the next story would exceed `wip_ceiling` total points.
- If a story would push the total over the ceiling, skip it and continue checking remaining stories
  (a 2-point story may fit even if a 5-point story didn't).
- Record why each skipped story was not included (over WIP / not ready / oversized / lower leverage / E1 cap).

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

### Step 6b — Pre-accepted story capacity audit

After assembling the sprint stories, check whether already-accepted stories (passes:true, reviewed:true)
or review-confirmation stories (passes:true, reviewed:false) crowd out implementation work.
Sprints with too many pre-accepted stories consume ceremony pipeline slots without requiring any
implementation, leaving new stories starved of execution capacity.

```python
import json

sprint_stories = [<the story list you just assembled>]

total_points = sum(s.get('points', 1) for s in sprint_stories)
pre_accepted_points = sum(
    s.get('points', 1) for s in sprint_stories
    if s.get('passes') is True and s.get('reviewed') is True
)
review_confirmation_points = sum(
    s.get('points', 1) for s in sprint_stories
    if s.get('passes') is True and s.get('reviewed') is False
)

crowded_points = pre_accepted_points + review_confirmation_points
crowded_pct = (crowded_points / total_points * 100) if total_points > 0 else 0

if crowded_pct > 50:
    print(f"WARNING: {crowded_pct:.0f}% of sprint capacity ({crowded_points}/{total_points} pts) "
          f"is already-accepted or review-confirmation stories.")
    print("These stories require no implementation work but consume ceremony pipeline slots.")
    print("SUGGESTION: Remove pre-accepted stories (passes:true, reviewed:true) from this sprint.")
    print("They do not need to be re-executed — the review ceremony will pick them up automatically.")
    print("Freed capacity should be filled with implementation-pending stories (passes:false).")
else:
    print(f"Capacity audit OK: {crowded_pct:.0f}% pre-accepted/review-confirmation "
          f"({crowded_points}/{total_points} pts) — under 50% threshold.")
```

> This check is advisory — it does not block the sprint from being created. But if the WARNING fires,
> strongly consider removing the already-accepted stories before writing the sprint file. A sprint
> crowded with review-confirmations will exhaust the execute pipeline on stories requiring no code,
> and implementation-pending stories will be returned to backlog unimplemented at retro.

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

Update `prd/manifest.json` with exactly these fields — **nothing else**:

```python
import json, datetime

with open("prd/manifest.json") as f:
    m = json.load(f)

# Find the increment entry
for inc in m["increments"]:
    if str(inc["id"]) == str(NEXT_INCREMENT_ID):
        inc["status"] = "active"
        if not inc.get("startDate"):
            inc["startDate"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        inc["pointsTotal"] = TOTAL_POINTS
        inc["storiesTotal"] = TOTAL_STORIES
        break

m["activeSprint"] = NEXT_INCREMENT_FILE
m["currentIncrement"] = NEXT_INCREMENT_ID

with open("prd/manifest.json", "w") as f:
    json.dump(m, f, indent=2)
```

> **HARD CONSTRAINTS — never violate:**
> - **NEVER set `status: "complete"`** on any increment. Only the **advance ceremony** closes sprints.
> - **NEVER write to `velocity[]`** — only the advance ceremony adds velocity entries.
> - **NEVER write to `sprintHistory[]`** — only the advance ceremony adds history entries.
> - **NEVER set `endDate`, `pointsCompleted`, `storiesAccepted`, `reviewPassRate`** — retro/advance only.
> - **NEVER plan more than one increment** — write one sprint file and one manifest update, then stop.
>
> The plan ceremony creates a sprint. The retro ceremony closes it. The advance ceremony moves the
> pointer. These are three separate ceremonies and their responsibilities must never be mixed.

**Always update the manifest.** The sprint file just written is not referenced by anything until
`activeSprint` and `currentIncrement` are set. A sprint file without a manifest pointer is invisible
to all ceremonies. The manifest update IS the plan's final step — then stop.

### Step 9 — Ensure a pending increment stub exists (GGE G5 guard)

After activating the sprint, check whether `prd/manifest.json` has any increment with
`status: "pending"`. If none exists, append a minimal pending stub now — this ensures
GGE G5 (`planning pipeline always has a pending increment`) never fires after this ceremony.

```python
import json

with open('prd/manifest.json') as f:
    manifest = json.load(f)

pending = [i for i in manifest.get('increments', []) if i.get('status') == 'pending']
if not pending:
    increments = manifest.get('increments', [])
    numeric_ids = [i['id'] for i in increments if isinstance(i['id'], int)]
    next_id = max(numeric_ids) + 1 if numeric_ids else 1
    active_id = manifest.get('currentIncrement', next_id - 1)
    stub = {
        "id": next_id,
        "name": "pending-stub",
        "description": (
            f"Placeholder pending increment. "
            f"Will be properly planned when increment {active_id} completes."
        ),
        "file": f"prd/increment-{next_id}-pending-stub.json",
        "status": "pending",
        "themeGoal": f"TBD \u2014 planned by plan ceremony after increment {active_id} advances.",
        "dependsOn": [active_id]
    }
    increments.append(stub)
    manifest['increments'] = increments
    with open('prd/manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2)
    print(f"Appended pending stub: increment {next_id} (GGE G5 guard)")
else:
    print(f"Pending increment already exists: {pending[0]['id']} ({pending[0].get('name', '')}) \u2014 GGE G5 OK")
```

Verify GGE G5 passes:

```python
import json
m = json.load(open('prd/manifest.json'))
pending = [i for i in m.get('increments', []) if i.get('status') == 'pending']
assert len(pending) >= 1, f"FAIL: no pending increment after plan — GGE G5 will fire!"
print(f"GGE G5 check: {len(pending)} pending increment(s) — OK")
```

### Step 10 — Print sprint planning summary

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
