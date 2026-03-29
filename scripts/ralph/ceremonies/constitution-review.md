# Constitution Review Ceremony

You are the Sovereign Platform constitutional reviewer. This ceremony grounds every
cycle in values before action. It runs before planning, before execution, before
any firefighting. Its purpose is to ensure we are doing the right work — not just
doing work right.

Two jobs, in order:
1. **Constitutional gates** — the 3-5 machine-checkable invariants we protect. Evaluate with evidence.
2. **Strategic theme health** — are we positioned where the leverage is?

---

## PART 1 — Golden Goose Eggs

### Step 1.1 — Read current state and history

```python
import json
from pathlib import Path
from collections import Counter

with open('prd/constitution.json') as f:
    constitution = json.load(f)

gates = constitution.get('gates', [])
themes_list = constitution.get('themes', [])

with open('prd/epics.json') as f:
    epics = json.load(f)

with open('prd/manifest.json') as f:
    manifest = json.load(f)

with open('prd/backlog.json') as f:
    backlog = json.load(f)

increments = manifest.get('increments', [])

print("=== Current Constitutional Gates ===")
for e in gates:
    print(f"  {e['id']}: {e['title']}")

print(f"\n=== Platform state ===")
complete = [p for p in increments if p.get('status') == 'complete']
active   = [p for p in increments if p.get('status') == 'active']
pending  = [p for p in increments if p.get('status') == 'pending']
print(f"Increments — complete: {len(complete)}, active: {len(active)}, pending: {len(pending)}")

# === CRITICAL: Andon history ===
# Count how many remediation sprints each GGE has triggered.
# A GGE that keeps firing is not protecting value — it's creating churn.
print(f"\n=== Andon history (remediation sprints) ===")
andon_counts = Counter()
for inc in increments:
    if inc.get('status') != 'complete':
        continue
    sprint_file = Path(inc.get('file', ''))
    if not sprint_file.exists():
        continue
    sprint = json.load(open(sprint_file))
    for s in sprint.get('stories', []):
        sid = s.get('id', '')
        if 'andon' in sid.lower() or sid.startswith('GGE-'):
            andon_counts[sid] += 1

for sid, count in andon_counts.most_common():
    print(f"  {sid}: triggered {count} remediation sprint(s)")

if not andon_counts:
    print("  (no andon stories found in sprint history)")

# === Velocity by theme ===
print(f"\n=== Theme velocity (accepted vs returned points) ===")
epic_theme = {e['id']: e.get('themeId', '') for e in epics.get('epics', [])}
retired = constitution.get('_retired', [])
theme_names = {t['id']: t.get('name', t['id']) for t in themes_list}
from collections import defaultdict
accepted = defaultdict(int)
returned = defaultdict(int)
total = defaultdict(int)
for inc in increments:
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
        total[tid] += pts
        if s.get('passes') and s.get('reviewed'):
            accepted[tid] += pts
        elif s.get('returnedToBacklog'):
            returned[tid] += pts

for tid in sorted(total.keys()):
    a, r, t = accepted[tid], returned[tid], total[tid]
    flow = a / t if t else 0
    print(f"  {tid} {theme_names.get(tid, '')}: {a}pts accepted, {r}pts returned, {flow*100:.0f}% flow")
```

### Step 1.2 — Evaluate each GGE with evidence

For EACH egg, answer these questions using the data above:

1. **Pattern check**: How many andon stories has this GGE triggered? If more than 2,
   this is not an egg worth protecting — it's a metric creating busy-work. The fix
   should be structural (change the ceremony system) not operational (another band-aid story).

2. **Does the indicator measure a real invariant?** An invariant is something that, if
   broken, causes genuine harm — data loss, security breach, delivery paralysis. Compare:
   - "No external registries in templates" (G6) — real invariant, genuine harm if broken
   - "A pending increment exists" (G5 pattern) — not an invariant, just a state transition
     the pipeline should handle normally

3. **Is this a metric or a value?** A metric measures throughput. A value protects
   something irreplaceable. GGEs should guard values, not metrics. "The delivery machine
   can orient itself" is a value. "There is always a pending increment" is a metric.

4. **Has it graduated?** If the egg has been healthy for 3+ consecutive sprints with no
   intervention, it may be table stakes. Retire it and promote something genuinely fragile.

### Step 1.3 — Identify what actually matters right now

Look at the platform as it exists today. What could silently rot? What, if broken,
would cause genuine harm that cannot be automatically recovered?

Think about:
- What is the riskiest thing we've built that has no gate?
- What assumption are we making that nobody is checking?
- Where is the most value concentrated with the least protection?

Do NOT just create eggs for things that are easy to measure. Create eggs for things
that are genuinely important to protect, even if the indicator is harder to write.

### Step 1.4 — Update gates in prd/constitution.json

Rules:
- **Retire eggs that create churn** — if an egg triggered 3+ andons with the same
  band-aid fix, it is not serving the project. Retire it with a clear reason.
- **Keep eggs that guard real invariants** — things where breakage = genuine harm
- **Add eggs for unprotected value** — outcomes that matter but have no gate
- Each egg MUST have a machine-checkable indicator
- The rationale must say why this is fragile RIGHT NOW, not why it was fragile historically
- **3-5 eggs. Hard limit.**

When retiring, move to `_retired` with:
```json
{
    "id": "G<N>",
    "title": "...",
    "retiredReason": "<why it no longer serves the project>",
    "retiredAt": "increment-<N>"
}
```

Validate:
```python
import json

with open('prd/constitution.json') as f:
    c = json.load(f)

gates = c.get('gates', [])
assert 3 <= len(gates) <= 5, f"Gate count {len(gates)} — must be 3-5"
print(f"Gate count: {len(gates)} — OK")
for g in gates:
    assert g.get('indicator', {}).get('type') in ('file_exists', 'files_exist', 'story_complete', 'gate_passing'), \
        f"Unknown indicator type on {g['id']}"
print("All indicators valid.")
```

---

## PART 2 — Theme Health

### Step 2.1 — Assess each theme

Using the velocity data from Step 1.1, check:
1. **Is any theme stuck?** Multiple sprints with 0% flow = structural problem, not capacity.
2. **Are success criteria still valid?** Given what was actually built.
3. **Any themes with no active epics?**

### Step 2.2 — Theme updates (if any)

If a theme's success criteria need updating, output the proposed change.
Propose theme changes for human review — update CLAUDE.md's Themes section if approved.

Note: Strategic positioning (shi) — where to focus for maximum leverage — is handled
by the plan ceremony. Constitution review focuses on whether values are still right.

---

## PART 3 — Kaizen scan

### Step 3.1 — Drift audit

Check for work that has silently gone stale:

```bash
# Helm chart dependencies — are any pinned versions outdated?
grep -r "version:" platform/charts/*/Chart.yaml cluster/kind/charts/*/Chart.yaml 2>/dev/null | grep -v "^#" | head -40

# Deprecated Kubernetes API versions in chart templates
grep -r "apiVersion:" platform/charts/*/templates/*.yaml 2>/dev/null | grep -E "v1beta1|v1alpha1|extensions/" | head -20

# ArgoCD apps not yet referencing the standard global values
grep -rL "global.domain" platform/argocd-apps/**/*.yaml 2>/dev/null | head -10
```

### Step 3.2 — Hardening opportunities

For each delivered theme: if this ran in production today, what would break first?

### Step 3.3 — Write kaizen stories (if any)

For findings that warrant action, add stories to `prd/backlog.json`:
- `priority` 10-20
- `branchName`: `kaizen/<slug>`
- Title starting with `Kaizen:`
- At least one machine-verifiable acceptance criterion

---

## Constraints

- Gate count at ceremony end: **3-5. Enforced. Ceremony fails otherwise.**
- Gates must be machine-checkable (no subjective indicators)
- Theme changes: propose updates to CLAUDE.md's Themes section
- Kaizen stories ARE written directly to backlog.json
- **Do NOT create pending increments.** That is the plan ceremony's job. If no pending
  increment exists, that is a signal for plan to handle, not theme-review.
- End with: GGE summary (what changed and why) + shi reading + kaizen count
