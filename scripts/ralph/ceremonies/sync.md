# Sync Ceremony

You are running the **sync ceremony** for the Sovereign Platform.

This ceremony runs after retro, before advance. Its job is to rewrite two living documents
so they reflect the current state of the platform — not the history, not the aspiration.

The rule is: **rewrite, not append.** These documents answer "where are we right now."
Anything uncertain or risky has already been escalated to the backlog by the retro ceremony.
These documents only contain what is known and decided.

---

## Step 1 — Read current state

```python
import json
from pathlib import Path

with open('prd/manifest.json') as f:
    manifest = json.load(f)

sprint_file = manifest['activeSprint']
with open(sprint_file) as f:
    sprint = json.load(f)

with open('prd/themes.json') as f:
    themes = json.load(f)

with open('prd/epics.json') as f:
    epics = json.load(f)

with open('prd/backlog.json') as f:
    backlog = json.load(f)

# What was accepted this sprint
accepted = [s for s in sprint['stories'] if s.get('reviewed')]
returned = [s for s in sprint['stories'] if s.get('returnedToBacklog')]
killed   = [s for s in sprint['stories'] if s.get('status') == 'killed']

# Platform phase state
phases_complete = [p for p in manifest.get('phases', []) if p.get('status') == 'complete']
phase_active    = next((p for p in manifest.get('phases', []) if p.get('status') == 'active'), None)
phases_pending  = [p for p in manifest.get('phases', []) if p.get('status') == 'pending']

# Epic state
epics_complete = [e for e in epics.get('epics', []) if e.get('status') == 'complete']
epics_active   = [e for e in epics.get('epics', []) if e.get('status') == 'active']
epics_backlog  = [e for e in epics.get('epics', []) if e.get('status') == 'backlog']
```

Also read the retro patch for this sprint if it exists:
```bash
cat prd/retro-patch-phase*.md 2>/dev/null | tail -100
```

And read the current versions of both living documents:
```bash
cat docs/state/architecture.md
cat docs/state/agent.md
```

---

## Step 2 — Rewrite `docs/state/architecture.md`

Produce a complete rewrite of `docs/state/architecture.md`. Rules:

- **Present tense only.** "The platform uses X" — not "we decided to use X in phase N."
- **No dates.** No sprint references. No phase references in decision statements.
- **Decisions only.** If something is in the backlog or pending, it is not a decision yet.
  Do not document what you intend to build — only what is built and running.
- **Rewrite completely.** Do not append. The file should read as if written today from scratch.
- **If a decision from the previous version is no longer true**, remove it. Don't add a note
  saying it changed — just reflect the current truth.
- **If this sprint delivered something new**, incorporate the architectural decision it represents.

Structure to maintain:
1. Platform identity (one paragraph — what this thing is)
2. Delivery model table (GitOps, composition, secrets, bootstrap, Helm standards)
3. Sovereignty policy (two-tier, with link to governance doc)
4. Network and security table
5. Storage (one paragraph)
6. Identity (one paragraph)
7. Observability stack table
8. Quality gates (non-negotiable list)
9. What this platform is not (three bullets)

Keep it to one printed page. If a section grows beyond 3–4 lines, it belongs in a dedicated
governance doc, not here.

---

## Step 3 — Rewrite `docs/state/agent.md`

Produce a complete rewrite of `docs/state/agent.md`. Rules:

- This is the briefing any agent reads before touching the codebase.
- **Patterns that must not be broken** — update if this sprint surfaced a new pattern or
  fixed a recurring mistake. Patterns from retro patches that have been applied go here.
  If a pattern was in the previous version and is still true, keep it unchanged.
  If a pattern was fixed and is no longer an issue, remove it.
- **Current platform state** section — update to reflect which phases are complete, active,
  pending. Update active epics.
- **Hard stops** — only add a hard stop if it is non-negotiable and unambiguous. Do not add
  soft guidance here. Hard stops are "do not proceed" rules, not "be careful about" notes.
- **Rewrite completely.** Same rule as architecture.md — no appending.

Sections to maintain:
1. What you are doing (2–3 sentences)
2. Where things live (table)
3. Patterns that must not be broken (specific, actionable, no vague guidance)
4. How to implement a story (numbered steps)
5. What the ceremonies do (one line each)
6. Current platform state (phase/epic status — updated this sprint)
7. Hard stops

---

## Step 4 — Apply and verify

Write both files. Then verify the rewrite is coherent:

```python
# Read back and check minimum structure
arch = open('docs/state/architecture.md').read()
agent = open('docs/state/agent.md').read()

required_arch = ['Platform identity', 'Delivery model', 'Sovereignty', 'Quality gates']
required_agent = ['What you are doing', 'Where things live', 'Patterns', 'Hard stops', 'Current platform state']

for section in required_arch:
    assert section in arch, f"architecture.md missing section: {section}"

for section in required_agent:
    assert section in agent, f"agent.md missing section: {section}"

print("Sync complete.")
print(f"  architecture.md: {len(arch.splitlines())} lines")
print(f"  agent.md: {len(agent.splitlines())} lines")
```

---

## Step 5 — Dismiss resolved retro patches

After applying any patterns from retro patches to `agent.md`, delete the patch files
for phases that are now complete and whose patterns have been incorporated:

```python
import os
from pathlib import Path

patches = list(Path('prd').glob('retro-patch-phase*.md'))
for patch in patches:
    content = open(patch).read()
    # Only delete if the patch's phase is complete in manifest
    # (patterns applied → file no longer needed)
    print(f"  Reviewed and applied: {patch.name} — deleting")
    os.remove(patch)
```

Only delete patches whose patterns you actually reviewed and either applied to `agent.md`
or explicitly decided are no longer relevant. Do not delete patches you didn't read.

---

## Constraints

- Do NOT invent decisions that haven't been made.
- Do NOT document pending or in-progress work as if it's complete.
- Do NOT add historical context ("previously we used X, now we use Y").
- Do NOT add aspirational statements ("we plan to").
- These documents are the chart, not the log. Write what is true now.
