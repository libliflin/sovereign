# Story Split Ceremony

You are running the **story-split ceremony** for the Sovereign Platform.

This ceremony fires automatically when the SMART check detects one or more stories that scored
< 3 on any SMART dimension. Your job is to split each failing story into smaller, well-scoped
sub-stories and rewrite the sprint file so that ceremonies can continue.

## Your task

### Step 1 — Find and read the active sprint

```bash
cat prd/manifest.json
# Then read the activeSprint file, e.g.:
cat prd/increment-6-observability.json
```

### Step 2 — Identify failing stories

A story needs splitting if its `smart` object has **any dimension scoring < 3**:

```python
import json

with open('prd/increment-6-observability.json') as f:
    sprint = json.load(f)

failing = [
    s for s in sprint['stories']
    if s.get('smart') and min(
        s['smart'].get('specific', 5),
        s['smart'].get('measurable', 5),
        s['smart'].get('achievable', 5),
        s['smart'].get('relevant', 5),
        s['smart'].get('timeBound', 5),
    ) < 3
]
print([s['id'] for s in failing])
```

### Step 3 — Read the split guidance

For each failing story, read `smart.notes` carefully. The notes from the SMART check ceremony
will usually specify how the story should be split (e.g. "split into 026a Loki, 026b Thanos,
026c Tempo"). Use those notes as your primary guidance.

### Step 4 — Generate sub-stories

For **each failing story**, produce 2–4 sub-stories following these rules:

**ID format:** Append a letter suffix to the parent ID.
- Parent `026` → children `026a`, `026b`, `026c`
- Parent `007` → children `007a`, `007b`
- If the parent already has a letter suffix (e.g. `026a`), use `026a1`, `026a2`, etc.

**Each sub-story MUST:**
- Cover exactly one Helm chart, one script, or one clearly bounded deliverable
- Have `points` ≤ 3
- Inherit `phase`, `epicId`, `themeId`, `branchName` from the parent story (unless the split
  guidance specifies different branches)
- Have `priority` values incrementing from the parent's priority (026a = 25, 026b = 26, 026c = 27)
- Have concrete, binary `acceptanceCriteria` (shell commands with expected output, file existence checks)
- Have `passes: false`, `reviewed: false`, `attempts: 0`, `reviewNotes: []`
- Have a `smart` object reset to all zeros (the next SMART check will re-score them):
  ```json
  "smart": { "specific": 0, "measurable": 0, "achievable": 0, "relevant": 0, "timeBound": 0, "notes": "" }
  ```
- Have a `dependencies` array (use parent's dependencies for the first sub-story; add the
  previous sibling's ID for subsequent sub-stories if there is a natural ordering)
- Include a `testPlan` with the exact commands that verify the story is complete

**Do NOT:**
- Create sub-stories that are still too large (achievable < 4 for a sub-story is a warning sign)
- Duplicate acceptance criteria across sub-stories
- Leave any acceptance criteria from the parent uncovered

**Example sub-story shape:**
```json
{
  "id": "026a",
  "phase": 6,
  "priority": 26,
  "branchName": "feature/helm-loki",
  "title": "Helm chart: Loki log aggregation with S3-compatible storage",
  "description": "Create charts/loki/ wrapping grafana/loki (pin appVersion to 3.0.0). Configure SimpleScalable mode with S3-compatible backend pointing at MinIO/Ceph. ArgoCD app in argocd-apps/observability/loki-app.yaml.",
  "acceptanceCriteria": [
    "charts/loki/Chart.yaml pins appVersion to a specific Loki release",
    "helm lint charts/loki/ passes with 0 errors",
    "helm template charts/loki/ | yq e '.' - passes",
    "argocd-apps/observability/loki-app.yaml exists and passes yq e '.' check"
  ],
  "passes": false,
  "points": 3,
  "testPlan": "helm lint; helm template | yq e '.'; yq argocd manifest",
  "dependencies": [],
  "reviewed": false,
  "reviewNotes": [],
  "attempts": 0,
  "epicId": "E6-OBS",
  "themeId": "T4",
  "smart": { "specific": 0, "measurable": 0, "achievable": 0, "relevant": 0, "timeBound": 0, "notes": "" }
}
```

### Step 5 — Rewrite the sprint file

Use Python to replace each failing story with its sub-stories. Insert the sub-stories at the
same position as the parent (preserving sprint ordering). Remove the original parent story.

```python
import json

with open('prd/increment-6-observability.json') as f:
    sprint = json.load(f)

# Build a new stories list, replacing failing stories with their splits
new_stories = []
for story in sprint['stories']:
    if story['id'] in failing_ids:
        new_stories.extend(splits_for[story['id']])  # insert sub-stories
    else:
        new_stories.append(story)

sprint['stories'] = new_stories

with open('prd/increment-6-observability.json', 'w') as f:
    json.dump(sprint, f, indent=2)
```

### Step 6 — Update backlog.json

Read `prd/backlog.json`. For each parent story you split:
1. Find the parent story by ID and **remove it**
2. Insert the new sub-stories at the same position
3. Write the updated backlog back

```bash
cat prd/backlog.json
```

```python
import json

with open('prd/backlog.json') as f:
    backlog = json.load(f)

# Replace parent with sub-stories in backlog stories list
new_stories = []
for story in backlog.get('stories', []):
    if story['id'] in failing_ids:
        new_stories.extend(splits_for[story['id']])
    else:
        new_stories.append(story)

backlog['stories'] = new_stories

with open('prd/backlog.json', 'w') as f:
    json.dump(backlog, f, indent=2)
```

### Step 7 — Update epics.json

Read `prd/epics.json`. For each epic that contained the parent story ID in its `storyIds` array:
1. Remove the parent ID
2. Add the new sub-story IDs in its place

```python
import json

with open('prd/epics.json') as f:
    epics = json.load(f)

for epic in epics.get('epics', []):
    new_ids = []
    for sid in epic.get('storyIds', []):
        if sid in failing_ids:
            new_ids.extend(splits_for[sid].keys())  # or however you track sub-IDs
        else:
            new_ids.append(sid)
    epic['storyIds'] = new_ids

with open('prd/epics.json', 'w') as f:
    json.dump(epics, f, indent=2)
```

### Step 8 — Print summary

After all files are updated, print a summary:

```
=== Story Split Ceremony ===

Split 1 story into 3 sub-stories:

  026 (Helm charts: Loki, Thanos, Tempo)  →  3 sub-stories
    026a  Helm chart: Loki log aggregation with S3-compatible storage    [3 pts]
    026b  Helm chart: Thanos long-term Prometheus storage                [3 pts]
    026c  Helm chart: Tempo distributed tracing backend                  [2 pts]

Files updated:
  prd/increment-6-observability.json  (sprint file)
  prd/backlog.json
  prd/epics.json

SMART check will now re-evaluate the new sub-stories.
```

## Important constraints

- Only split stories that have a SMART dimension < 3. Do not split healthy stories.
- Every acceptance criterion from the parent must appear in exactly one sub-story.
- Sub-story IDs must be unique across the entire sprint file and backlog.
- The `priority` field for sub-stories must be integers that sort correctly within the sprint
  (the sprint is executed in priority order).
- After writing, verify the sprint file is valid JSON: `python3 -m json.tool prd/increment-6-observability.json > /dev/null`
- After writing, verify backlog.json is valid JSON: `python3 -m json.tool prd/backlog.json > /dev/null`
