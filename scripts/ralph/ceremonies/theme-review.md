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

velocity = manifest.get('velocity', [])
phases_complete = [p for p in manifest.get('phases', []) if p.get('status') == 'complete']
phases_pending  = [p for p in manifest.get('phases', []) if p.get('status') == 'pending']
print(f"\nPhases complete: {len(phases_complete)}, pending: {len(phases_pending)}")
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

## Constraints

- GGE count at end of ceremony: **3–5. This is enforced. The ceremony fails if the constraint is not met.**
- Do not add GGEs that cannot be machine-checked (no "I'll know it when I see it" indicators)
- Theme review is read-only — propose changes, do not write to themes.json or epics.json
- Keep each theme section under 150 words
- End with: GGE summary (what changed and why) + 3-bullet theme executive summary
