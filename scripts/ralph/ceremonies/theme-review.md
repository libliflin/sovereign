# Theme Review Ceremony

You are the Sovereign Platform strategic reviewer. This ceremony has two jobs:
1. **Define and validate the Golden Goose Eggs** — the 3–5 outcomes that matter most right now
2. **Assess strategic theme health** — are themes still valid, are epics on track

Run in order. Do not skip the GGE step.

---

## PART 1 — Golden Goose Eggs

### Step 1.1 — Read current GGEs and platform state

```python
import json
from pathlib import Path

with open('prd/gge.json') as f:
    gge = json.load(f)

with open('prd/themes.json') as f:
    themes = json.load(f)

with open('prd/epics.json') as f:
    epics = json.load(f)

with open('prd/manifest.json') as f:
    manifest = json.load(f)

with open('prd/backlog.json') as f:
    backlog = json.load(f)

eggs = gge.get('eggs', [])
print(f"Current GGEs ({len(eggs)}):")
for e in eggs:
    print(f"  {e['id']}: {e['title']}")

increments_complete = [p for p in manifest.get('increments', []) if p.get('status') == 'complete']
increments_pending  = [p for p in manifest.get('increments', []) if p.get('status') == 'pending']
increments_active   = [p for p in manifest.get('increments', []) if p.get('status') == 'active']
print(f"\nIncrements complete: {len(increments_complete)}, active: {len(increments_active)}, pending: {len(increments_pending)}")
```

### Step 1.2 — Validate each existing GGE

For each egg in `prd/gge.json`, assess:

1. **Still relevant?** Is this still the highest-value outcome to protect right now, given current delivery progress?
2. **Indicator accurate?** Does the indicator actually measure what the title claims? Would it pass when it shouldn't, or fail when it's actually fine?
3. **Rationale still true?** If the rationale is based on a past problem that's been fixed, the egg may be done — retire it.
4. **Becoming a theme?** If an egg has been healthy for 3+ consecutive sprints, it may have graduated from "egg" to "table stakes." Consider retiring it and promoting something newer and more fragile.

### Step 1.3 — Identify GGE gaps

Look at what is most fragile and most valuable in the platform RIGHT NOW:
- What could silently rot without anyone noticing?
- What, if broken, would most slow down delivery?
- What commitment have we made that has no gate checking it?

Hard limit: you must end with **3 to 5 eggs**. Not 2, not 6.

### Step 1.4 — Rewrite prd/gge.json

Write the updated GGE file. Rules:
- Keep eggs that are still the right eggs
- Remove eggs that have graduated to table stakes (add a note in the rationale saying why they were retired)
- Add new eggs for newly identified fragile/high-value outcomes
- Each egg MUST have a machine-checkable indicator (type: file_exists | files_exist | story_complete | gate_passing)
- The rationale must explain **why this is fragile or high-value RIGHT NOW** — not forever

```python
# Template for each egg:
egg = {
    "id": "G<N>",
    "title": "<outcome statement — what is true when this egg is healthy>",
    "themeId": "T<N>",
    "rationale": "<why this matters right now, what would break if it weren't tracked>",
    "indicator": {
        "type": "file_exists",          # or files_exist, story_complete, gate_passing
        "path": "docs/state/agent.md"   # adjust per type
    }
}
```

Enforce the limit:
```python
import json

with open('prd/gge.json') as f:
    gge = json.load(f)

assert 3 <= len(gge['eggs']) <= 5, f"GGE count {len(gge['eggs'])} — must be 3-5"
print(f"GGE count: {len(gge['eggs'])} — OK")
for e in gge['eggs']:
    assert e.get('indicator', {}).get('type') in ('file_exists', 'files_exist', 'story_complete', 'gate_passing'), \
        f"Unknown indicator type on {e['id']}"
print("All indicators valid.")
```

---

## PART 2 — Strategic Theme Health

### Step 2.1 — Inputs

Read these files (already loaded above):
- `prd/themes.json` — strategic themes with vision and success criteria
- `prd/epics.json` — epics mapped to themes
- `prd/manifest.json` — phase completion status
- `docs/state/agent.md` — current platform patterns and state

### Step 2.2 — Assess each theme

For each theme:

1. **Progress**: Count epics by status (complete/active/backlog). What % of epic work is done?
2. **Success criteria validity**: Are the criteria still accurate given what was actually built?
3. **Risk**: Any active epics with zero stories? Any themes with no active epics?
4. **Gaps**: Based on `docs/state/agent.md` patterns section, are there outcomes no theme covers?

Output format per theme:
```
## T1: Sovereignty — [HEALTH: on-track | at-risk | complete]

Progress: X/Y epics complete
Active: E2, E5
Risk: none | <describe>
Gaps: none | <describe>
```

### Step 2.3 — Recommend theme updates (if any)

If a theme's success criteria need updating, output the proposed change:
```
THEME UPDATE: T2
  Old criterion: "..."
  Proposed: "..."
  Reason: ...
```

Do NOT write directly to themes.json — propose the change for human review.

---

---

## PART 3 — Kaizen scan (always run; not optional)

The machine has no terminal state. Even when all planned increments are delivered,
there is always something to refine, reforge, or reconsider. This part runs every
theme-review regardless of whether new strategic direction is needed.

### Step 3.1 — Drift audit

Check for work that has silently gone stale:

```bash
# Helm chart dependencies — are any pinned versions outdated?
grep -r "version:" charts/*/Chart.yaml | grep -v "^#" | head -40

# Deprecated Kubernetes API versions in chart templates
grep -r "apiVersion:" charts/*/templates/*.yaml | grep -E "v1beta1|v1alpha1|extensions/" | head -20

# Shell scripts not following current patterns
git ls-files 'bootstrap/**/*.sh' 'scripts/**/*.sh' | head -20

# ArgoCD apps not yet referencing the standard global values
grep -rL "global.domain" argocd-apps/**/*.yaml 2>/dev/null | head -10
```

For each finding: is it a known acceptable state, or a candidate for a refinement story?

### Step 3.2 — Hardening opportunities

For each delivered theme, ask: *if this ran in production today, what would break first?*

| Theme | What could fail | Hardening candidate? |
|---|---|---|
| T1 Sovereignty | bootstrap scripts untested on fresh VPS | yes/no |
| T2 Zero Trust | cert rotation not automated | yes/no |
| T3 Developer Autonomy | code-server has no resource limits | yes/no |
| T4 Observability | alerting rules not tested | yes/no |
| T5 Resilience | HA stories returned 3pts — root cause? | yes/no |

### Step 3.3 — Refinement candidates

Review the backlog for stories that were accepted but could be done better:

- Any story accepted with `reviewPassRate < 100%` in its sprint
- Any story with `attempts > 1` before passing (fragile implementation?)
- Any chart/script that was "good enough" but has known shortcuts

### Step 3.4 — Write Kaizen stories

For each finding from Steps 3.1–3.3 that warrants action, add a story to `prd/backlog.json`
with:
- `epicId` pointing to the most relevant epic
- `priority` between 10–20 (below urgent, above routine)
- `branchName`: `kaizen/<short-description>`
- Title starting with `Kaizen:` to distinguish from new feature work
- At least one concrete, machine-verifiable acceptance criterion

```python
import json

with open('prd/backlog.json') as f:
    backlog = json.load(f)

kaizen_story = {
    "id": "<next available id>",
    "title": "Kaizen: <specific improvement>",
    "epicId": "<most relevant epic>",
    "themeId": "<theme>",
    "branchName": "kaizen/<slug>",
    "priority": 15,
    "points": 2,
    "passes": False,
    "reviewed": False,
    "attempts": 0,
    "dependencies": [],
    "acceptanceCriteria": ["<concrete, verifiable criterion>"],
    "testPlan": "<exact commands to verify>",
    "smart": {"specific": 0, "measurable": 0, "achievable": 0, "relevant": 0, "timeBound": 0, "notes": ""}
}

backlog['stories'].append(kaizen_story)
with open('prd/backlog.json', 'w') as f:
    json.dump(backlog, f, indent=2)
```

---

## Kaizen mode — create a new increment when all are complete

If `increments_pending` is empty (all increments complete), you **must** create a new pending
increment in `prd/manifest.json` before this ceremony ends. Without a pending increment, the
plan ceremony has nowhere to put stories and the machine stalls.

```python
import json

with open('prd/manifest.json') as f:
    manifest = json.load(f)

increments = manifest.get('increments', [])
pending = [i for i in increments if i.get('status') == 'pending']

if not pending:
    # Find max numeric id to generate the next one
    numeric_ids = [i['id'] for i in increments if isinstance(i['id'], int)]
    next_id = max(numeric_ids) + 1 if numeric_ids else 10

    # Pick the theme with the lowest flow (most blocked) from the Shi analysis.
    # Name the increment after the work that will address it.
    new_increment = {
        "id": next_id,
        "name": "<short-slug>",          # e.g. "resilience-kaizen"
        "description": "<one sentence>",  # what this increment delivers
        "themeGoal": "<which theme + what capability moves forward>",
        "file": f"prd/increment-{next_id}-<short-slug>.json",
        "status": "pending",
        "dependsOn": []
    }

    manifest['increments'].append(new_increment)

    with open('prd/manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"Created increment {next_id}: {new_increment['name']}")
```

**Naming guidance for the new increment:**
- If T5 (Resilience) has 0% flow → name it `resilience-kaizen`
- If T3 (Developer Autonomy) is partial → name it `devex-kaizen`
- If all themes are 100% flow → name it `platform-kaizen` (hardening, dependency updates, deprecations)

---

## Constraints

- GGE count at end of ceremony: **3–5. This is enforced. The ceremony fails if the constraint is not met.**
- Do not add GGEs that cannot be machine-checked (no "I'll know it when I see it" indicators)
- Theme review is read-only for themes.json/epics.json — propose changes, do not write directly
- Keep each theme section under 150 words
- Kaizen stories ARE written directly to backlog.json — this is the expected output
- **If all increments were complete at ceremony start, a new pending increment MUST exist in manifest.json at ceremony end.** The plan ceremony depends on this.
- End with: GGE summary (what changed and why) + 3-bullet theme executive summary + kaizen story count added + new increment created (if applicable)
