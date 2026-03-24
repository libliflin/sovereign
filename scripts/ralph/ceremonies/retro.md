# Retrospective Ceremony

You are running the **retrospective ceremony** for the Sovereign Platform sprint.

The sprint is closing **now** — regardless of how many stories completed. Partial delivery is
honest delivery. Your job is to close cleanly, understand why incomplete stories didn't finish,
generate backlog stories to fix the root causes, and return the incomplete work to the backlog.

---

## Step 1 — Read the sprint

```python
import json, sys
from pathlib import Path
from datetime import datetime, timezone

with open('prd/manifest.json') as f:
    manifest = json.load(f)

sprint_file = manifest['activeSprint']

with open(sprint_file) as f:
    sprint = json.load(f)

stories = sprint['stories']
accepted  = [s for s in stories if s.get('reviewed', False)]
incomplete = [s for s in stories if not s.get('reviewed', False)]

print(f"Sprint   : {sprint.get('name', sprint_file)}")
print(f"Accepted : {len(accepted)} / {len(stories)}")
print(f"Incomplete: {len(incomplete)}")
```

---

## Step 2 — 5 Whys for every incomplete story

For each story in `incomplete`, work through the 5 Whys to find the **real** root cause.
Don't stop at the first "why" — surface the systemic issue, not the symptom.

Example structure:
```
Story 026c: Helm chart — Tempo distributed tracing
  Why 1: Story didn't pass review → acceptance criteria weren't verifiable locally
  Why 2: AC required a live cluster with Jaeger UI running
  Why 3: Story scope assumed cluster access that doesn't exist in the test env
  Why 4: Story was written without checking what the smoke gate can actually validate
  Why 5: SMART check didn't catch that "measurable" requires a runnable gate, not a live cluster

  Root cause: Stories that need live-cluster validation are systematically not achievable
              in our environment. The SMART "achievable" scoring doesn't account for this.

  Fix: Add a backlog story to improve the SMART ceremony's achievable scoring prompt to
       explicitly ask: "can this AC be verified by helm lint + dry-run only?"
```

Write the 5 Whys analysis to the retro patch file (see Step 4).

For each incomplete story, also decide:
- **Return to backlog as-is** (worth doing, just needs more time / better environment)
- **Split into smaller stories** (was too big — use what was learned to right-size)
- **Kill it** (not worth the effort relative to value delivered — mark as `status: killed`)

---

## Step 3 — Generate remediation backlog stories

For each distinct root cause identified in Step 2, generate one or more new backlog stories
that **fix the system**, not just the symptom.

These go into `prd/backlog.json`. Each new story needs:
- A new unique ID (find the current max ID, increment from there — use suffix `r` for
  remediation, e.g. `028r-smart-achievable-gate`)
- `title`, `description`, `acceptanceCriteria` (specific and verifiable)
- `epicId` and `themeId` inherited from the incomplete story
- `phase` same as current phase or one earlier if it's a process fix
- `priority` 1 (remediation stories are high priority — fix the system first)
- `points` ≤ 3
- `passes`: false
- `returnedFromSprint`: the sprint file name
- `returnedReason`: one-sentence root cause summary

```python
with open('prd/backlog.json') as f:
    backlog = json.load(f)

# Find max numeric ID
existing_ids = [s['id'] for s in backlog.get('stories', [])]
# Add new remediation stories...
backlog['stories'].append({
    "id": "028r-smart-achievable-gate",
    "title": "...",
    ...
})

with open('prd/backlog.json', 'w') as f:
    json.dump(backlog, f, indent=2)
```

Also update the incomplete stories themselves in the sprint file — set:
```python
story['returnedToBacklog'] = True
story['returnedReason'] = "<one-sentence root cause>"
```

And add the incomplete stories to `backlog.json` with their `returnedFromSprint` field set,
so they can be repulled in a future sprint once the system fixes are in place.

---

## Step 4 — Write retro patch

Write `prd/retro-patch-phase<N>.md`:

```markdown
# Retro Patch: Phase <N> — <sprint name>
Generated: <ISO timestamp>

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | N | N pts |
| Incomplete → backlog | N | N pts |
| Killed | N | — |

## 5 Whys: incomplete stories

### <story id>: <title>
- Why 1: ...
- Why 2: ...
- Why 3: ...
- Why 4: ...
- Why 5: ...
**Root cause**: ...
**Decision**: return / split / kill
**Remediation story**: <new story id> — <title>

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- <Specific actionable pattern>
- <Another pattern>

## Quality gate improvements

<If a gate consistently missed something, propose making it more explicit>

## Velocity

Sprint points accepted: <N> / <planned>
First-review pass rate: <X>% (<N> of <total> accepted on first review)
```

**Do NOT modify CLAUDE.md directly.** A human reviews the retro patch first.

---

## Step 5 — Update manifest.json

```python
end_date = datetime.now(timezone.utc).isoformat()
current_phase = manifest['currentPhase']

total = len(stories)
n_accepted = len(accepted)
n_incomplete = len(incomplete)
first_pass = len([s for s in accepted if s.get('attempts', 0) == 0])
pass_rate = round(first_pass / total * 100, 1) if total > 0 else 0
points_done = sum(s.get('points', 0) for s in accepted)

for phase in manifest.get('phases', []):
    if phase['id'] == current_phase:
        phase['status'] = 'complete'
        phase['endDate'] = end_date
        phase['pointsCompleted'] = points_done
        phase['storiesAccepted'] = n_accepted
        phase['storiesIncomplete'] = n_incomplete
        phase['reviewPassRate'] = pass_rate

# Guard: don't double-append if retro runs twice
history_phases = [h['phase'] for h in manifest.get('sprintHistory', [])]
if current_phase not in history_phases:
    manifest.setdefault('sprintHistory', []).append({
        'phase': current_phase,
        'name': sprint.get('name', ''),
        'endDate': end_date,
        'pointsCompleted': points_done,
        'storiesTotal': total,
        'storiesAccepted': n_accepted,
        'storiesIncomplete': n_incomplete,
        'reviewPassRate': pass_rate
    })
    manifest.setdefault('velocity', []).append({
        'phase': current_phase,
        'pointsCompleted': points_done,
        'storiesAccepted': n_accepted,
        'reviewPassRate': pass_rate,
        'date': end_date
    })

with open('prd/manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)

with open(sprint_file, 'w') as f:
    json.dump(sprint, f, indent=2)
```

---

## Step 6 — Print retrospective summary

```
════════════════════════════════════════════════════════════════════
  RETROSPECTIVE: Phase <N> — <sprint name>
════════════════════════════════════════════════════════════════════

  Delivery
  ─────────────────────────────
  Accepted     : <N> / <total> stories  (<points> pts)
  Incomplete   : <N> stories → returned to backlog
  Killed       : <N> stories

  Quality
  ─────────────────────────────
  First-review pass rate : <X>%
  Gate retries           : <N>

  Root causes (incomplete stories)
  ─────────────────────────────
  <one line per root cause found>

  Remediation stories added to backlog
  ─────────────────────────────
  <id>: <title>

  Velocity trend
  ─────────────────────────────
  <list prior phases and points>

  Retro patch → prd/retro-patch-phase<N>.md
════════════════════════════════════════════════════════════════════
```

---

## Constraints

- **Close the sprint regardless** of how many stories completed. Partial delivery is honest.
- **Never carry stories forward** by leaving them in the sprint file as-is. Either mark
  `returnedToBacklog: true` (and add to backlog.json) or `status: killed`.
- Do NOT modify CLAUDE.md directly — retro patch only.
- Do NOT set `reviewed: true` on incomplete stories — that would be dishonest.
- This ceremony is idempotent: check `sprintHistory` before appending.
