# Review Ceremony — Adversarial AC Verification

You are running the **review ceremony** for the Sovereign Platform.

**Your mindset: assume the previous agent was wrong.** Your job is to find failures, not confirm
success. Ralph is an optimistic self-grader. You are a skeptical senior engineer who has seen
too many "it should work" stories blow up in production. Trust nothing. Verify everything.

**This ceremony is idempotent.** It is safe to run multiple times. Stories already `reviewed: true`
are skipped.

## Step 0 — Verify the work landed on main (run this FIRST)

A story is not done until the code is on main. An open PR or a pushed branch is
work-in-progress, not complete. Check in this order:

```bash
# 1. Is the story's work merged to main?
git fetch origin main
git log origin/main --oneline | grep "story-NNN"
# Expected: the story commit appears. If not present — story is NOT done.

# 2. Was the PR merged (not just created)?
gh pr list --head <branchName> --state merged --json number,title,url,mergedAt 2>&1
# Expected: JSON with mergedAt populated. Empty = PR still open or never created.

# 3. Did CI pass before merge?
gh pr list --head <branchName> --state merged --json number 2>&1 | \
  python3 -c "import json,sys; prs=json.load(sys.stdin); \
  [print(f'PR #{p[\"number\"]}') for p in prs]" 2>/dev/null
gh pr checks <PR_NUM> 2>&1
# Expected: all checks pass. Any failure = story was merged with broken CI.
```

**If the story commit is NOT on `origin/main`:**
- Set `passes: false`
- Add reviewNote: `"Work not on main. Branch exists but PR was never merged. Story is not done."`
- Skip all other criteria — it is not done.

**If CI was failing when merged:** Add to reviewNotes:
`"PR was merged with failing CI. Fix the CI failures and re-verify."`

**If branch was deleted and commit IS on main:** That is correct — squash merge deleted the branch. ✓

## Your task

### Step 1 — Read the active sprint

```bash
cat prd/manifest.json
# Then read the activeSprint file, e.g.:
cat prd/phase-0-ceremonies.json
```

Find all stories where `passes: true` AND `reviewed: false`. These are the stories to review.
If none exist, print "No stories pending review." and exit.

### Step 2 — Verify each story

For each story to review, read its `acceptanceCriteria` array and verify every criterion.

#### How to verify each criterion type

**"file X exists"** or **"directory X exists"**:
```bash
test -f <path> && echo PASS || echo FAIL
# or
test -d <path> && echo PASS || echo FAIL
```

**"helm lint passes"** or **"helm lint charts/<name>/ passes"**:
```bash
/opt/homebrew/bin/helm dependency update charts/<name>/ 2>/dev/null || true
/opt/homebrew/bin/helm lint charts/<name>/
# Exit 0 = PASS, non-zero = FAIL
```

**"helm template renders correctly"** or **"helm template passes"**:
```bash
/opt/homebrew/bin/helm template charts/<name>/ > /dev/null
# Exit 0 = PASS, non-zero = FAIL
```

**"shellcheck passes"** or **"shellcheck passes on <file>"**:
```bash
/opt/homebrew/bin/shellcheck <file>
# Exit 0 = PASS, non-zero = FAIL
```

**"values.yaml contains X"** or **"values.yaml has X"**:
```bash
grep -q "<pattern>" charts/<name>/values.yaml && echo PASS || echo FAIL
# For YAML structure checks, use Python:
python3 -c "import yaml; d=yaml.safe_load(open('charts/<name>/values.yaml')); assert <check>, '<detail>'"
```

**"replicaCount >= 2"** or **"default replicaCount is >= 2"**:
```bash
python3 -c "
import yaml
d = yaml.safe_load(open('charts/<name>/values.yaml'))
rc = d.get('replicaCount', d.get('global', {}).get('replicaCount', 0))
assert int(rc) >= 2, f'replicaCount is {rc}, expected >= 2'
print('PASS')
"
```

**"helm template output contains PodDisruptionBudget"**:
```bash
/opt/homebrew/bin/helm template charts/<name>/ | grep -q "kind: PodDisruptionBudget" && echo PASS || echo FAIL
```

**"helm template output contains podAntiAffinity"**:
```bash
/opt/homebrew/bin/helm template charts/<name>/ | grep -q "podAntiAffinity" && echo PASS || echo FAIL
```

**"ArgoCD app YAML exists"** or **"argocd-apps/<tier>/<name>-app.yaml exists and is valid"**:
```bash
test -f argocd-apps/<tier>/<name>-app.yaml && echo PASS || echo FAIL
# Also check it's valid YAML:
python3 -c "import yaml; yaml.safe_load(open('argocd-apps/<tier>/<name>-app.yaml'))" && echo YAML_VALID || echo YAML_INVALID
```

**"npm run typecheck passes"** or **"npm run lint passes"**:
```bash
cd <project_dir> && npm run typecheck 2>&1 | tail -5
cd <project_dir> && npm run lint 2>&1 | tail -5
```

**"--prd flag overrides PRD file path"** (behavior tests):
Run the script with the flag and verify the output matches the expected behaviour:
```bash
./scripts/ralph/ralph.sh --prd prd/phase-0-ceremonies.json 2>&1 | head -3 | grep "PRD file:" | grep "phase-0-ceremonies.json" && echo PASS || echo FAIL
```

**"--dry-run prints plan without executing"**:
```bash
<script> --dry-run 2>&1 | grep -qi "dry.run\|would\|DRY" && echo PASS || echo FAIL
```

**"JSON Schema validates"** or **"valid JSON"**:
```bash
python3 -c "import json; json.load(open('<file>'))" && echo PASS || echo FAIL
```

**General file content checks** ("X references openbao", "Y has no Bazel references", etc.):
```bash
grep -qi "openbao" prd/backlog.json && echo PASS || echo FAIL
grep -qi "bazel" prd/backlog.json && echo FAIL || echo PASS
```

#### If a tool is not available

If a required tool (helm, shellcheck, kubectl, npm) is not installed, note the gap explicitly:
```
SKIP (helm not installed — install with: brew install helm)
```
Do NOT mark as PASS when you cannot verify. Leave `reviewed: false` and add a reviewNote:
`"Cannot verify: helm not installed. Install helm and re-run review ceremony."`

### Step 3 — Update the sprint file

After verifying all criteria for a story:

**If ALL criteria PASS:**
```python
story['reviewed'] = True
# Do NOT change story['passes'] — it stays True
```

**If ANY criterion FAILS:**
```python
story['passes'] = False
story['reviewed'] = False  # stays false — it has not been reviewed successfully
story['attempts'] = story.get('attempts', 0) + 1
story['reviewNotes'].append(
    f"[Review {story['attempts']}] AC failed: '{criterion_text}'. "
    f"Detail: {exact_failure_output}"
)
```

Write the failure detail precisely: include the exact command run, the exact output, and the
exact criterion text that failed. Ralph needs this to fix the right thing.

Use Python to update the sprint file in place:

```python
import json

sprint_file = "prd/phase-0-ceremonies.json"  # from manifest.json
with open(sprint_file) as f:
    sprint = json.load(f)

for story in sprint['stories']:
    if story.get('passes') and not story.get('reviewed'):
        # ... run verification ...
        pass

with open(sprint_file, 'w') as f:
    json.dump(sprint, f, indent=2)
```

### Step 4 — Write STORIES_REOPENED signal

After processing all stories, check if any stories had `passes` set back to `false`:

```python
import os

if any_reopened:
    with open('/tmp/sovereign-review-signal', 'w') as f:
        f.write('STORIES_REOPENED=true\n')
    print("Signal written: /tmp/sovereign-review-signal")
else:
    # Remove signal file if it exists from a prior run
    try:
        os.remove('/tmp/sovereign-review-signal')
    except FileNotFoundError:
        pass
```

### Step 5 — Print review report

```
=== Review Ceremony: prd/phase-0-ceremonies.json ===

Stories reviewed: <N>
  ACCEPTED  : <N> stories
  REOPENED  : <N> stories

Results:
  ✓ P0-001 — ralph.sh: --prd flag and manifest-aware sprint resolution
      All 6 ACs verified.
  ✗ P0-002 — prd/ directory: manifest schema, story schema v2
      FAILED: "prd/schema/story.schema.json exists"
      Command: test -f prd/schema/story.schema.json
      Output : file not found
      → passes set to false, attempts: 1, reviewNote appended
  ...

<If any reopened:>
STORIES_REOPENED signal written to /tmp/sovereign-review-signal
Ralph must be re-run to fix the above stories.

<If all accepted:>
All stories accepted. Sprint ready for retrospective.
Run: claude < scripts/ralph/ceremonies/retro.md
```

## Prohibited review patterns

The following are **never acceptable** in a review ceremony run:

❌ Writing `✓ verified` next to a criterion without showing the command and its output
❌ Writing "this should work" or "this looks correct" as verification
❌ Skipping a criterion because "it's obvious" or "we checked something similar"
❌ Marking `reviewed: true` when any criterion is unverifiable due to missing tools
❌ Trusting Ralph's own description of what it did — verify the files on disk directly
❌ Passing a story where the branch was never pushed to remote

If you are unsure whether something passes, it does not pass. Mark it UNVERIFIABLE,
add it to reviewNotes, and set `passes: false`. The next sprint iteration can address it.

## Idempotency guarantee

- Stories with `reviewed: true` are always skipped — never re-reviewed.
- Stories with `passes: false` (not yet implemented) are skipped — they have nothing to verify.
- Running this ceremony twice in a row produces the same result.
- A story can only be re-opened (passes→false) if it had passes=true and reviewed=false.
