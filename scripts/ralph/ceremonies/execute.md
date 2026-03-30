# Execute Ceremony — AC Self-Check Protocol

You are running the **execute ceremony** for the Sovereign Platform.

Ralph implements stories from the active sprint. The core discipline that prevents
wasted iterations is the **mandatory self-check**: after creating any artifact, you
**must** run every command from the story's `acceptanceCriteria` array and show the
verbatim output before setting `passes: true`.

---

## The Self-Check Rule

> **Never mark `passes: true` without running all AC commands and showing their output.**

This rule exists because five stories in sprint 33 (HA-005a, TEST-004a, TEST-005a,
TEST-006, KAIZEN-015) were marked done after creating plausible artifacts — but the
review ceremony found the AC commands failed. Each of those stories was returned to the
backlog, wasting a full sprint cycle.

**The self-check prevents this**: if you run the AC commands and one fails, you fix it
before marking done. The review ceremony confirms what you verified. It does not
re-do your work; it catches what you skipped.

---

## Execute Protocol

### Step 1 — Read the active sprint and pick the highest-priority story

```bash
cat prd/manifest.json        # find activeSprint field
cat prd/<sprint-file>.json   # find highest-priority story with passes:false, reviewed:false
```

If all stories have `passes: true`, output `<promise>COMPLETE</promise>` and stop.

### Step 2 — Checkout the story branch

```bash
git fetch origin
git checkout <story.branchName>  # create from main if new
git merge main --no-edit          # merge main if existing
```

### Step 3 — Implement the story

Read the story's `description`, `acceptanceCriteria`, and `testPlan` fields.
Read the relevant CLAUDE.md files for the directories you will modify.

Create or modify the required artifacts.

### Step 4 — Mandatory AC self-check (run this before touching the sprint file)

After creating your artifacts, run every AC command from the story's `acceptanceCriteria`
array verbatim. Show the full output. Do not paraphrase.

```
For each criterion in story.acceptanceCriteria:
  1. Show the exact command you are running
  2. Run it
  3. Show the complete output
  4. Explicitly state: PASS or FAIL

If any AC command fails:
  - Fix the artifact
  - Re-run the failing AC command
  - Repeat until all AC commands pass
  - Only then proceed to Step 5

Do NOT set passes:true if any AC command returned a non-zero exit code.
Do NOT set passes:true if any AC command produced output that does not match the criterion.
```

This is the self-check. It is not optional. There is no exception for "obvious" criteria.

**Example: how to run AC commands for a helm chart story**

The story's `acceptanceCriteria` might be:
```json
[
  "helm lint platform/charts/wiremock/ exits 0 with '0 chart(s) failed'",
  "helm template platform/charts/wiremock/ | grep PodDisruptionBudget returns at least 1 match"
]
```

Run them:
```bash
helm lint platform/charts/wiremock/
# Show output verbatim

helm template platform/charts/wiremock/ | grep PodDisruptionBudget
# Show output verbatim
```

If `grep` returns no output (exit code 1), the criterion FAILS. Fix the template and
re-run before proceeding.

### Step 5 — Update the sprint file

Only after all AC commands have passed:

```python
import json

sprint_file = "prd/<active-sprint>.json"  # from manifest.json
with open(sprint_file) as f:
    sprint = json.load(f)

for story in sprint["stories"]:
    if story["id"] == "<story-id>":
        story["passes"] = True
        # Never set reviewed: True — that is the review ceremony's job
        break

with open(sprint_file, "w") as f:
    json.dump(sprint, f, indent=2)
```

### Step 6 — Push and open a PR

```bash
git add -A
git commit -m "<story-id>: <title>"
git push -u origin <branchName>
gh pr create --title "<story-id>: <title>" --body "$(cat <<'EOF'
## Story

<story description>

## AC Self-Check Results

<paste the verbatim output from Step 4 here>

All acceptanceCriteria verified against live output.
EOF
)"
```

---

## Prohibited patterns

The following are **never acceptable** in an execute ceremony run:

❌ Setting `passes: true` before running the AC commands
❌ Running AC commands but not showing the output
❌ Writing "this should work" or "the file exists" instead of running the command
❌ Skipping an AC command because "it's similar to one that passed"
❌ Marking done after a partial run where one command was skipped

If a command is not available on this machine, document the blocker:
```python
story["passes"] = False
story["reviewNotes"].append("[BLOCKED] <tool> not available: <install instructions>")
```

---

## Idempotency

- Stories already `passes: true` are skipped.
- Running execute twice produces the same result.
- The ceremony loop retries execute up to `max_retries` times if `ralph.sh` exits non-zero.

---

## Self-check summary

Before marking any story `passes: true`, verify this checklist:

- [ ] I ran every command in `acceptanceCriteria` and showed the output
- [ ] Every AC command exited 0 (or matched its expected output pattern)
- [ ] I did not paraphrase or infer the output — I showed it verbatim
- [ ] The sprint file now has `passes: true` for this story only
- [ ] The branch has been pushed and a PR has been created
