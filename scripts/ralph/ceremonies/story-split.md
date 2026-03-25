# Story Split Ceremony

You are running the **story-split ceremony** for the Sovereign Platform.

This ceremony fires automatically when the SMART check finds any story with a dimension < 3.
Your job: decompose every failing story into sub-stories that **all score ≥ 3 on every SMART
dimension before you write a single file**. Do not defer the problem — split recursively until
every proposed sub-story passes the scope budget check below.

---

## Step 1 — Find the active sprint and failing stories

```bash
cat prd/manifest.json
```

Then read the active sprint file (the `activeSprint` path from manifest):

```python
import json

with open('prd/manifest.json') as f:
    manifest = json.load(f)

sprint_file = manifest['activeSprint']
with open(sprint_file) as f:
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
print("Failing:", [s['id'] for s in failing])
```

---

## Step 2 — Diagnose each failing story

For each failing story, read its `smart.notes` and its `acceptanceCriteria`.
Identify **why** it fails — the cause determines the correct split strategy.

| Root cause | Symptom | Strategy to use |
|---|---|---|
| Too many charts/files bundled together | `achievable < 3`, long ACs list | **One deliverable per story** |
| Ordered phases in one story (build, configure, wire) | `achievable < 3`, sequential ACs | **Vertical slice** |
| Shared infrastructure mixed with consumers | `achievable < 2`, multiple sub-systems | **Extract shared infra first** |
| Story covers multiple epics/themes | `specific < 3` or `relevant < 3` | **Split by ownership** |
| ACs that require a live system to verify | `measurable < 3` | **Separate static-verifiable from runtime-verifiable** |
| Unbounded scope ("all charts", "all services") | `timeBound < 3`, open list | **Enumerate and cap** |

---

## Step 3 — Choose a splitting strategy

### Strategy A: One deliverable per story (most common)

Use when: a story bundles multiple Helm charts, scripts, or independent files.

**Hard rule: maximum 5 Helm charts per story. Maximum 3 files created/modified per story.**

```
Parent:  "HA hardening for 23 charts"
Split:
  031b-1  HA hardening: identity tier  (keycloak, gitlab, harbor, argocd)          [3 pts]
  031b-2  HA hardening: service mesh + security  (istio, kiali, opa-gatekeeper)    [2 pts]
  031b-3  HA hardening: observability  (prometheus-stack, loki, thanos, tempo)     [3 pts]
  031b-4  HA hardening: devex + testing  (backstage, code-server, sonarqube, ...)  [3 pts]
```

### Strategy B: Vertical slice (scaffold → implement → harden)

Use when: a story mixes creating the skeleton, filling in logic, and wiring to CI/GitOps.

```
Parent:  "Backstage Helm chart with Keycloak, GitLab catalog, ArgoCD plugin, TechDocs"
Split:
  027a  Backstage Helm scaffold: Chart.yaml, values.yaml, basic Deployment + Service + Ingress  [2 pts]
  027b  Backstage plugins: Keycloak OIDC, GitLab catalog-info, Kubernetes plugin config         [3 pts]
  027c  Backstage TechDocs: Ceph bucket config, ArgoCD app in argocd-apps/devex/               [2 pts]
  (027b depends on 027a; 027c depends on 027b)
```

### Strategy C: Extract shared infrastructure first

Use when: a story creates a shared helper/template AND applies it to consumers — these are two
different tasks and the consumers cannot be tested until the helper exists.

```
Parent:  "Create HA helpers tpl + apply to 6 charts"
Split:
  031a  Create charts/_globals/templates/_ha-helpers.tpl with PDB and anti-affinity macros  [2 pts]
  031b  Apply HA helpers to: cilium, cert-manager, crossplane, sealed-secrets, vault        [3 pts]
  (031b depends on 031a)
```

### Strategy D: Separate static-verifiable from runtime-verifiable ACs

Use when: some ACs can be checked with `helm lint` / `grep` / file-exists, but others need a
live cluster. Keep static-verifiable ACs in the sprint; move runtime-verifiable ACs to a
future increment or flag them as integration-test stories.

```
Parent:  "Backstage: Kubernetes plugin shows cluster resources, ArgoCD plugin shows status"
Split:
  027a  Helm chart scaffold with plugin configs in values.yaml (static: helm lint, grep)    [3 pts]
  027b  Integration test: verify plugins against live cluster  (future increment, pending)  [2 pts]
  (027b moved to backlog, blocked on 027a + running cluster)
```

### Strategy E: Enumerate and cap (for "all X" stories)

Use when: scope is unbounded ("all charts", "every namespace"). Never accept a story whose
scope grows as the repo grows.

```
Parent:  "Add resource limits to all charts"
Split:
  →  List every chart explicitly. Group into tiers of ≤ 5. Create one story per tier.
  →  Each story names the exact charts: "Add resource limits: cilium, cert-manager, crossplane,
     sealed-secrets, vault"  — not "foundations charts".
```

---

## Step 4 — Self-validate BEFORE writing any file

For every proposed sub-story, answer ALL of these before touching the filesystem:

### Scope budget check (achievable)
- [ ] ≤ 5 Helm charts modified/created
- [ ] ≤ 3 new files created (excluding test/lint output)
- [ ] Mental token budget: could this be done in ~2000 tokens of code output? If not, split further.
- [ ] Every acceptance criterion is independently verifiable (shell command with expected output, file-exists, grep match)

### Clarity check (specific + measurable)
- [ ] Title names the exact deliverable (chart name, script name — not "improve" or "update")
- [ ] No AC says "verify X works" — every AC has a concrete command that proves it

### Dependency check
- [ ] If sub-story B needs sub-story A's output, then B has A in its `dependencies` array
- [ ] No circular dependencies

### Completeness check
- [ ] Every acceptance criterion from the parent appears in exactly one sub-story
- [ ] No parent ACs are silently dropped

**If any sub-story fails this check, do not write it. Split it further using the strategies above.**
**Repeat Step 3 → Step 4 until every sub-story passes all checks.**

---

## Step 5 — Generate the sub-stories

Use the following template for each sub-story:

```json
{
  "id": "031b-1",
  "epicId": "<inherit from parent>",
  "themeId": "<inherit from parent>",
  "branchName": "feature/<specific-name>",
  "title": "Exact, specific deliverable name",
  "description": "One paragraph. What to build. Names exact files/charts.",
  "acceptanceCriteria": [
    "charts/cilium/values.yaml has replicaCount: 2",
    "helm template charts/cilium/ | grep -q 'minAvailable: 1'",
    "helm lint charts/cilium/ passes with 0 errors"
  ],
  "passes": false,
  "points": 3,
  "testPlan": "helm lint charts/cilium/; helm template charts/cilium/ | grep minAvailable; grep replicaCount charts/cilium/values.yaml",
  "dependencies": ["031a"],
  "reviewed": false,
  "reviewNotes": [],
  "attempts": 0,
  "priority": 31,
  "smart": { "specific": 0, "measurable": 0, "achievable": 0, "relevant": 0, "timeBound": 0, "notes": "" }
}
```

**ID format:**
- Parent `031` → children `031a`, `031b`, `031c` ...
- Parent `031b` → children `031b-1`, `031b-2`, `031b-3` ...
- Parent `031b-1` → children `031b-1a`, `031b-1b` ... (rarely needed; if you reach this depth, revisit epic scope)

**Priority:** sub-stories get priorities incrementing from the parent (`031a = parent.priority`, `031b = parent.priority + 1`, etc.)

---

## Step 6 — Write the files

Only write after every proposed sub-story passed the self-validation in Step 4.

### Update the sprint file

```python
import json

with open(sprint_file) as f:
    sprint = json.load(f)

failing_ids = {s['id'] for s in failing}
new_stories = []
for story in sprint['stories']:
    if story['id'] in failing_ids:
        new_stories.extend(splits_for[story['id']])
    else:
        new_stories.append(story)

sprint['stories'] = new_stories

with open(sprint_file, 'w') as f:
    json.dump(sprint, f, indent=2)
```

### Update backlog.json

```python
import json

with open('prd/backlog.json') as f:
    backlog = json.load(f)

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

### Update epics.json

```python
import json

with open('prd/epics.json') as f:
    epics = json.load(f)

for epic in epics.get('epics', []):
    new_ids = []
    for sid in epic.get('storyIds', []):
        if sid in failing_ids:
            new_ids.extend([s['id'] for s in splits_for[sid]])
        else:
            new_ids.append(sid)
    epic['storyIds'] = new_ids

with open('prd/epics.json', 'w') as f:
    json.dump(epics, f, indent=2)
```

---

## Step 7 — Validate output

```bash
# Verify JSON is valid
python3 -m json.tool prd/backlog.json > /dev/null && echo "backlog OK"
python3 -m json.tool prd/epics.json > /dev/null && echo "epics OK"
python3 -m json.tool "$SPRINT_FILE" > /dev/null && echo "sprint OK"

# Verify no duplicate story IDs across sprint + backlog
python3 - <<'PYEOF'
import json
with open('prd/backlog.json') as f:
    backlog_ids = [s['id'] for s in json.load(f)['stories']]
with open('prd/manifest.json') as f:
    sf = json.load(f)['activeSprint']
with open(sf) as f:
    sprint_ids = [s['id'] for s in json.load(f)['stories']]
dupes = set(backlog_ids) & set(sprint_ids)
# It's OK for sprint stories to also be in backlog — they are.
# Check for duplicate IDs within each file instead:
assert len(backlog_ids) == len(set(backlog_ids)), f"Duplicate IDs in backlog: {[x for x in backlog_ids if backlog_ids.count(x) > 1]}"
assert len(sprint_ids) == len(set(sprint_ids)), f"Duplicate IDs in sprint: {[x for x in sprint_ids if sprint_ids.count(x) > 1]}"
print("No duplicate IDs")
PYEOF
```

---

## Step 8 — Print summary

```
=== Story Split Ceremony ===

Strategy used: <One deliverable per story / Vertical slice / Extract shared infra / ...>

Split N stories:

  031b  (HA hardening for 23 charts — achievable: 1)
    031b-1  HA hardening: identity tier (keycloak, gitlab, harbor, argocd)         [3 pts]
    031b-2  HA hardening: service mesh + security (istio, kiali, opa-gatekeeper)   [2 pts]
    031b-3  HA hardening: observability (prometheus-stack, loki, thanos, tempo)    [3 pts]
    031b-4  HA hardening: devex + testing (backstage, code-server, sonarqube, ...) [3 pts]

Scope budget check (pre-write validation):
  031b-1  charts: 4  files: ≤3  token-budget: OK  ✓
  031b-2  charts: 3  files: ≤3  token-budget: OK  ✓
  031b-3  charts: 4  files: ≤3  token-budget: OK  ✓
  031b-4  charts: 5  files: ≤3  token-budget: OK  ✓

Files updated:
  prd/increment-8-testing-and-ha.json
  prd/backlog.json
  prd/epics.json

SMART check will now re-evaluate the new sub-stories.
```

---

## Hard constraints (never violate)

1. **Never write a sub-story with > 5 Helm charts.** 5 charts × (values.yaml + PDB + anti-affinity + probe + resource limits) already fills a 3-point budget.
2. **Never write a sub-story whose scope is unbounded.** "All charts" is not a valid scope. Name them explicitly.
3. **Never output a sub-story that you know requires further splitting.** Split it now. The SMART check will reject it and force another ceremony cycle — wasted API calls.
4. **Never silently drop acceptance criteria.** Every parent AC must map to exactly one sub-story.
5. **Points ≤ 3 per sub-story.** A sub-story with points: 5 will be rejected by the planning WIP ceiling.
6. **Only split stories that have a SMART dimension < 3.** Do not split healthy stories.
