# Backlog Grooming Ceremony

You are the Sovereign Platform backlog groomer. Your job is to **fix what you can and flag what you can't** — not just annotate problems.

## Inputs

Read these files:

1. `prd/backlog.json` — the full backlog
2. `prd/epics.json` — epic context for understanding story intent
3. `prd/constitution.json` — themes and constitutional gates
4. `prd/manifest.json` — to know which phases have sprint files already (completed/active phases)

## Evaluation scope

Check **every** story in the backlog that:
- Does NOT have `passes: true`
- Is NOT in a phase with status "complete" in the manifest

**This includes stories that already have a `readinessNote`.** A story with an existing note must be re-evaluated — the blocking condition may have resolved since the note was written.

## Step 1 — Fix dependency problems

Before evaluating readiness, scan all unfinished stories for dependency problems and fix them:

**Ghost IDs**: If a story's `dependencies[]` contains an ID that does not exist in the backlog, it is a ghost reference. Resolve it:
- Check if the missing ID appears in any story's `supersededBy` field or `returnedFromSprint`/split notes
- If the successor stories are all `passes: true`, update `dependencies[]` to reference the actual successor IDs (or `[]` if the work is provably done)
- Clear any `readinessNote` that was only about this ghost dep
- If you cannot resolve it, set a `readinessNote` naming the ghost ID explicitly

**Stale BLOCKED notes**: If a story's `readinessNote` says "BLOCKED: dependency X" and X now has `passes: true`, clear the `readinessNote`. The story is no longer blocked.

**Cascading blocks**: After clearing a note, check if any OTHER stories were blocked waiting on this story — they may now be ready too.

## Step 2 — Evaluate readiness

For each story (including those you just unblocked in Step 1), check the **Definition of Ready**:

1. **Specific**: Title and description leave no ambiguity about what must be built
2. **Verifiable ACs**: Every AC is independently checkable with a command or file check. "Works correctly" or "is implemented" fail this check
3. **testPlan**: Has concrete commands, not just "run quality gates"
4. **Resolved dependencies**: All IDs in `dependencies[]` have `passes: true`
5. **Points <= 3**: Stories with `points: 5` must be split

If a story passes all checks, **remove its `readinessNote`** (if any) and count it as READY.

If a story fails, set `readinessNote` to a specific actionable explanation:
- "AC #2 is not verifiable: 'chart is working' needs a specific command like 'helm lint charts/foo exits 0'"
- "testPlan is generic — needs specific commands to verify each AC"
- "MUST-SPLIT: 5 points exceeds sprint limit. Suggested split: (1) X, (2) Y"
- "BLOCKED: dependency KIND-001a has passes:false. Resolve that story first."

## Step 3 — Write all changes

Write all changes (fixed deps, cleared notes, new notes) back to `prd/backlog.json`:

```python
import json

with open('prd/backlog.json') as f:
    backlog = json.load(f)

all_stories = {s['id']: s for s in backlog['stories']}

# Example of fixing a ghost dependency and clearing the note:
# story = all_stories['RESTRUCTURE-001c']
# story['dependencies'] = ['RESTRUCTURE-001b-1', 'RESTRUCTURE-001b-2']
# del story['readinessNote']  # condition resolved

# Example of clearing a stale BLOCKED note:
# story = all_stories['KIND-001a']
# if all(all_stories.get(dep, {}).get('passes') for dep in story.get('dependencies', [])):
#     story.pop('readinessNote', None)

# Example of setting a new note:
# all_stories['FOO-001']['readinessNote'] = 'AC #1 is not verifiable...'

with open('prd/backlog.json', 'w') as f:
    json.dump(backlog, f, indent=2)

print("Backlog grooming complete")
```

## Output

Print a readiness report:

```
Backlog Readiness Report
========================

Epic E2 — Monorepo Restructure (T1 Sovereignty):
  RESTRUCTURE-001c  [FIXED]   ghost dep RESTRUCTURE-001b resolved → deps updated, note cleared
  KIND-001a         [UNBLOCKED] RESTRUCTURE-001c now passes:true → note cleared
  KIND-001b         [READY]   no issues

Epic E1 — Sprint Ceremony Infrastructure (T3 Developer Autonomy):
  KAIZEN-005  [READY]
  KAIZEN-006  [NOT READY]  testPlan too vague

Summary
=======
Total stories evaluated   : X
Fixed (dep/note resolved) : A
Newly unblocked           : B
Ready                     : C
Still blocked             : D
Need refinement           : E
Must be split             : F
```

## Constraints

- Do NOT create new stories — that is epic-breakdown.md's job
- Do NOT promote stories to any sprint — that is plan.md's job
- Do NOT modify `passes`, `reviewed`, or `attempts` fields
- DO fix ghost dependency IDs when the resolution is clear
- DO clear `readinessNote` when the blocking condition has resolved
- Be conservative with MUST-SPLIT — only flag when points > 3 and the story genuinely has separable concerns
