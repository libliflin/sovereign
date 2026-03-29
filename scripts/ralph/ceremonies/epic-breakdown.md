# Epic Breakdown Ceremony

You are the Sovereign Platform story writer. Your task is to generate sprint-sized stories for
epics that are in backlog or active status but have few or no stories.

## Inputs

Read these files:

1. `prd/epics.json` — find epics with status "backlog" or "active" that have 0 or few storyIds
2. `prd/constitution.json` — themes and strategic intent
3. `prd/schema/story.schema.json` — the required story format (follow it exactly)
4. `prd/backlog.json` — read existing stories to find the current max story id and avoid collisions

## Rules for story generation

Each generated story MUST:
- Have `id` as a string: next sequential number after the current max (e.g., if max is "036",
  next is "037", then "038", etc.)
- Have `epicId` set to the parent epic's id
- Have `themeId` set to the parent epic's themeId
- Have `phase` set to the epic's `targetIncrement` (use integer if possible, string if "2i" etc.)
- Have `points` of 1, 2, or 3 — never 5 (stories with 5 points must be split before entering sprint)
- Have at least 3 `acceptanceCriteria` — each must be independently verifiable with a command
  or file check (e.g., "helm lint charts/foo exits 0", "kubectl get ns foo returns Ready")
- Have `testPlan` with the actual commands to verify completion
- Have `passes: false`, `reviewed: false`, `reviewNotes: []`, `attempts: 0`
- Have `branchName` starting with "feature/" followed by a slug
- Have `dependencies` as an array (empty if none)
- Have `smart` object with all 5 scores set to 0 and notes "Not yet SMART-scored."
- Have `priority` as an integer (1 = highest)

Generate 2-5 stories per epic that together deliver the epic's stated goal in sprint-sized chunks.
Each story should be independently deployable — avoid stories that are blocked by other new stories
in the same batch unless absolutely necessary.

## Actions to take

1. Identify which epics need stories (status backlog/active with 0 storyIds or obviously incomplete)
2. Generate the stories
3. Append new stories to `prd/backlog.json` using Python — DO NOT overwrite existing stories:

```python
import json

with open('prd/backlog.json') as f:
    backlog = json.load(f)

new_stories = [
    # ... your generated stories here
]

existing_ids = {s['id'] for s in backlog['stories']}
added = 0
for s in new_stories:
    if s['id'] not in existing_ids:
        backlog['stories'].append(s)
        added += 1

with open('prd/backlog.json', 'w') as f:
    json.dump(backlog, f, indent=2)

print(f"Added {added} stories to backlog")
```

4. Update `prd/epics.json` storyIds arrays for each epic you added stories to:

```python
import json

with open('prd/epics.json') as f:
    epics_data = json.load(f)

# Add story IDs to the relevant epics
updates = {
    'E9': ['037', '038'],   # example
    'E10': ['039', '040'],  # example
}

for epic in epics_data['epics']:
    if epic['id'] in updates:
        existing = set(epic.get('storyIds', []))
        epic['storyIds'] = list(existing | set(updates[epic['id']]))

with open('prd/epics.json', 'w') as f:
    json.dump(epics_data, f, indent=2)

print("Updated epic storyIds")
```

## Output

Print a summary table:

```
Epic Breakdown Summary
======================
E9  (Prometheus/Grafana)    → added 3 stories: 037, 038, 039
E10 (Loki/Tempo/Thanos)     → added 3 stories: 040, 041, 042
E11 (Backstage/code-server) → added 2 stories: 043, 044
...

Total: X new stories added to prd/backlog.json
```

Focus on epics that are "active" first, then "backlog" epics for the next 1-2 phases.
Do not generate stories for phase 0 epics (E1) — those are complete infrastructure.
