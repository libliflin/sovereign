# Retrospective Ceremony

You are running the **retrospective ceremony** for the Sovereign Platform.

This ceremony runs after all stories in the active sprint are `reviewed: true`. It extracts
learnings, generates CLAUDE.md improvement suggestions, and closes out the sprint in the manifest.

## Your task

### Step 1 — Guard: all stories must be reviewed

Read the active sprint file:

```bash
cat prd/manifest.json
# Then read activeSprint, e.g.:
cat prd/phase-0-ceremonies.json
```

Check if any story has `reviewed: false`:

```python
import json

with open('prd/manifest.json') as f:
    manifest = json.load(f)

sprint_file = manifest['activeSprint']

with open(sprint_file) as f:
    sprint = json.load(f)

not_reviewed = [s for s in sprint['stories'] if not s.get('reviewed')]
if not_reviewed:
    print("ERROR: Cannot run retro — the following stories are not yet reviewed:")
    for s in not_reviewed:
        print(f"  {s['id']}: passes={s.get('passes')} reviewed={s.get('reviewed')}")
    print("Run the review ceremony first: claude < scripts/ralph/ceremonies/review.md")
    exit(1)
```

If any story is `reviewed: false`, abort and instruct the user to run the review ceremony first.

### Step 2 — Collect failure patterns

Gather all `reviewNotes` from stories that were re-opened (stories where `attempts > 0`):

```python
failures = []
for story in sprint['stories']:
    if story.get('attempts', 0) > 0:
        for note in story.get('reviewNotes', []):
            failures.append({
                'storyId': story['id'],
                'title': story['title'],
                'note': note
            })
```

Also read `progress.txt` and extract entries since the sprint's `startDate` (if set in manifest).
Look for patterns: which types of implementation does Ralph consistently get wrong?

Common failure patterns to look for:
- shellcheck SC2086/SC2001 (unquoted variables, sed vs parameter expansion)
- Missing HA requirements (replicaCount, PDB, anti-affinity)
- Hardcoded domains or image registries
- helm lint failing on missing Chart.lock
- kubectl dry-run failing due to no live cluster (should be treated as acceptable)
- Missing `--dry-run` flag on vendor scripts
- JSON/YAML schema violations

### Step 3 — Write CLAUDE.md update suggestions

Write `prd/retro-patch-phase<N>.md` (e.g. `prd/retro-patch-phase0.md`) with suggested updates
to CLAUDE.md's LEARNINGS FROM PRIOR SESSIONS section.

Format:

```markdown
# Retro Patch: Phase <N> — <name>
Generated: <ISO timestamp>

## Suggested additions to CLAUDE.md (LEARNINGS section)

### New patterns discovered this sprint

- <Specific actionable pattern, e.g.:>
  "helm dependency update must be run before helm lint when a chart has dependencies —
   do this automatically at the start of every chart story"

- <Another pattern, e.g.:>
  "shellcheck SC2001: use ${var//search/replace} instead of echo | sed for simple substitutions"

## Stories that failed review (re-opened)

| Story | Attempts | Root cause |
|-------|----------|------------|
| P0-002 | 2 | Missing prd/schema/ directory — files created in wrong location |

## Quality gate improvements suggested

<If any quality gate was consistently missed, suggest making it more explicit in CLAUDE.md>

## Velocity note

Sprint points: <completed> / <planned>
Review pass rate: <X>% (stories accepted on first review / total stories)
```

**Do NOT apply this patch directly to CLAUDE.md.** A human reviews it first.

### Step 4 — Update manifest.json

Calculate sprint metrics:

```python
total_stories = len(sprint['stories'])
accepted_stories = len([s for s in sprint['stories'] if s.get('reviewed')])
first_review_passes = len([s for s in sprint['stories'] if s.get('reviewed') and s.get('attempts', 0) == 0])
review_pass_rate = round(first_review_passes / total_stories * 100, 1) if total_stories > 0 else 0
points_completed = sum(s.get('points', 0) for s in sprint['stories'] if s.get('reviewed'))
```

Update the manifest:

```python
import json
from datetime import datetime, timezone

end_date = datetime.now(timezone.utc).isoformat()
current_phase = manifest['currentPhase']

# Update the phase entry
for phase in manifest['phases']:
    if phase['id'] == current_phase:
        phase['status'] = 'complete'
        phase['endDate'] = end_date
        phase['pointsCompleted'] = points_completed
        phase['storiesAccepted'] = accepted_stories
        phase['reviewPassRate'] = review_pass_rate

# Append to sprintHistory
manifest['sprintHistory'].append({
    'phase': current_phase,
    'name': sprint.get('name', ''),
    'endDate': end_date,
    'pointsCompleted': points_completed,
    'storiesTotal': total_stories,
    'storiesAccepted': accepted_stories,
    'reviewPassRate': review_pass_rate
})

# Append velocity data point
manifest['velocity'].append({
    'phase': current_phase,
    'pointsCompleted': points_completed,
    'storiesAccepted': accepted_stories,
    'reviewPassRate': review_pass_rate,
    'date': end_date
})

with open('prd/manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)
```

### Step 5 — Print retrospective summary

```
=== Retrospective: Phase <N> — <name> ===

Sprint metrics:
  Stories accepted  : <accepted> / <total>
  Points completed  : <points>
  First-review pass : <X>% (<N> stories accepted on first try)

What went well:
  <List stories that passed review on first attempt with brief note about why>

Patterns to fix:
  <List recurring failure patterns with specific fix>

Velocity trend:
  Phase 0: <N> pts
  Phase 1: <N> pts   ← if available
  (trend: improving / stable / declining)

Retro patch written: prd/retro-patch-phase<N>.md
  Review and apply relevant sections to CLAUDE.md manually.

Next step: run advance.sh to move to the next phase.
  ./prd/advance.sh
  (or ./prd/advance.sh --dry-run to preview)
```

## Important constraints

- Do NOT modify CLAUDE.md directly. Write suggestions to `prd/retro-patch-phase<N>.md` only.
- Do NOT set `reviewed: false` on any story — retro is read-only for story fields.
- Update `manifest.json` sprint metrics even if there were no failures (metrics are always useful).
- The retro ceremony is idempotent: running it twice overwrites the retro-patch file and re-calculates
  metrics, but does not corrupt sprint history (check if the phase entry already has `status: complete`
  before appending to `sprintHistory`).
