# Smoke Test Ceremony — Artifact Execution Verification

You are running the **smoke test ceremony** for the Sovereign Platform. This runs AFTER sprint
execution (Ralph has self-graded) but BEFORE the review ceremony. Your job is to actually
execute the built artifacts and verify they produce no errors — not to check that files exist,
but to confirm they run correctly.

**This ceremony is idempotent.** It is safe to run multiple times. Stories already `reviewed: true`
are skipped. A story that fails smoke testing has its `passes` reset to `false` so Ralph can fix it
before review begins.

**Show actual output, not summaries.** If helm lint produces a warning, show the warning verbatim.
If a script's --dry-run outputs nothing, note "no output — expected or suspicious?". The smoke
test is evidence, not just a thumbs up/down.

## Your task

### Step 1 — Read the active sprint

```bash
cat prd/manifest.json
# Then read the activeSprint file, e.g.:
cat prd/phase-0-ceremonies.json
```

Find all stories where `passes: true` AND `reviewed: false`. These are the stories to smoke-test.
If none exist, print "No stories pending smoke test." and exit.

### Step 2 — Determine artifact type per story

For each story to smoke-test, inspect its `branchName` and `title` to identify what type of
artifact it produced. Use the following rules in order (first match wins):

| Pattern | Artifact type |
|---|---|
| `branchName` matches `feature/helm-*` | Helm chart |
| `branchName` matches `feature/bootstrap-*` | Shell script(s) in `bootstrap/` |
| `branchName` matches `feature/ceremonies-*` or `feature/ralph-*` | Ralph/ceremony scripts |
| `branchName` matches `feature/prd-*` | JSON/schema files in `prd/` |
| `branchName` matches `feature/argocd-*` | ArgoCD Application YAML(s) |
| Title contains "helm" | Helm chart |
| Title contains "bootstrap" or "script" | Shell script(s) |
| Title contains "argocd" or "app-of-apps" | ArgoCD Application YAML(s) |
| Title contains "prd" or "manifest" or "schema" | JSON/schema files |
| Title contains "ralph" or "ceremony" | Ralph/ceremony scripts |

If none of the above match, note "artifact type unknown" and run a best-effort check (file
existence + bash -n on any .sh files found, python3 JSON validation on any .json files found).

### Step 3 — Run the appropriate smoke tests

Execute the commands below verbatim. Capture **all output** (stdout and stderr). Record the
exit code. Do not suppress warnings — they are part of the evidence.

---

#### Helm charts (`feature/helm-*`)

Derive the chart name from the branch: `feature/helm-<name>` → `charts/<name>/`.

```bash
# 1. Dependency update (allowed to fail if no dependencies declared)
helm dependency update charts/<name>/ 2>&1; echo "dep_update_exit:$?"

# 2. Lint — the primary gate
helm lint charts/<name>/ 2>&1; echo "lint_exit:$?"

# 3. Template render — catches missing values, broken helpers, syntax errors
helm template test-release charts/<name>/ --debug 2>&1 | tail -30; echo "template_exit:$?"

# 4. Count rendered resource kinds (sanity check — zero means broken chart)
helm template test-release charts/<name>/ 2>/dev/null | grep -c "kind:" ; echo "kind_count_exit:$?"

# 5. HA gates — these are REQUIRED by the platform standards
helm template test-release charts/<name>/ 2>/dev/null | grep "kind: PodDisruptionBudget" \
  && echo "PDB:FOUND" || echo "PDB:MISSING"

helm template test-release charts/<name>/ 2>/dev/null | grep "podAntiAffinity" \
  && echo "ANTI-AFFINITY:FOUND" || echo "ANTI-AFFINITY:MISSING"

# 6. Forbidden :latest image tags
helm template test-release charts/<name>/ 2>/dev/null | grep "image:" | grep ":latest" \
  && echo "LATEST-TAG:FOUND (FAIL)" || echo "LATEST-TAG:NONE (PASS)"

# 7. Domain hardcoding check — no literal domain names allowed
helm template test-release charts/<name>/ 2>/dev/null | grep -E "sovereign-autarky\.dev" \
  && echo "HARDCODED-DOMAIN:FOUND (FAIL)" || echo "HARDCODED-DOMAIN:NONE (PASS)"
```

**Smoke test passes if:** `lint_exit:0` AND `template_exit:0` AND `kind_count > 0` AND
`LATEST-TAG:NONE` AND `HARDCODED-DOMAIN:NONE`.

`PDB:MISSING` and `ANTI-AFFINITY:MISSING` are recorded as failures but only block pass if the
chart's story acceptance criteria explicitly required them. Always note them regardless.

---

#### Shell scripts (`feature/bootstrap-*`)

Find all `.sh` files modified or created by this story. If uncertain, check `bootstrap/` for
recently modified files.

```bash
# 1. ShellCheck — static analysis
shellcheck <script> 2>&1; echo "shellcheck_exit:$?"

# 2. Bash syntax check — catches parse errors shellcheck may miss
bash -n <script> 2>&1; echo "syntax_exit:$?"

# 3. Dry-run execution — the script must support --dry-run
<script> --dry-run 2>&1 | head -30; echo "dryrun_exit:$?"
# If the script produced no output, note: "no output — expected or suspicious?"
# If the script does not recognise --dry-run, note: "--dry-run unsupported (FAIL)"
```

**Smoke test passes if:** `shellcheck_exit:0` AND `syntax_exit:0` AND `dryrun_exit:0`.

A script that exits 0 on `--dry-run` but produces no output should be flagged with a warning,
not a failure, unless the story's acceptance criteria required printed output.

---

#### Ralph / ceremony scripts (`feature/ceremonies-*` or `feature/ralph-*`)

```bash
# 1. Syntax check ralph.sh
bash -n scripts/ralph/ralph.sh 2>&1; echo "ralph_syntax_exit:$?"

# 2. Syntax check ceremonies.sh
bash -n scripts/ralph/ceremonies.sh 2>&1; echo "ceremonies_syntax_exit:$?"

# 3. ShellCheck both
shellcheck scripts/ralph/ralph.sh 2>&1; echo "ralph_shellcheck_exit:$?"
shellcheck scripts/ralph/ceremonies.sh 2>&1; echo "ceremonies_shellcheck_exit:$?"

# 4. For any new ceremony .md files, confirm they are valid UTF-8 text
file scripts/ralph/ceremonies/*.md 2>&1

# 5. Dry-run ralph.sh to verify flag parsing (must not execute any story)
./scripts/ralph/ralph.sh --dry-run 2>&1 | head -20; echo "ralph_dryrun_exit:$?"
```

**Smoke test passes if:** all `*_syntax_exit:0` AND all `*_shellcheck_exit:0`.

Ceremony `.md` file checks are informational — they do not block the smoke test pass/fail.

---

#### ArgoCD Application YAMLs (`feature/argocd-*`)

Find all `.yaml` files under `argocd-apps/` modified or created by this story.

```bash
# 1. YAML parse validation — all ArgoCD app files must be valid YAML
python3 - <<'EOF'
import glob, yaml, sys
files = glob.glob('argocd-apps/**/*.yaml', recursive=True)
errors = []
for f in files:
    try:
        yaml.safe_load(open(f))
    except yaml.YAMLError as e:
        errors.append(f"{f}: {e}")
if errors:
    print("YAML_INVALID:")
    for e in errors:
        print(f"  {e}")
    sys.exit(1)
else:
    print(f"YAML_VALID: {len(files)} files parsed successfully")
EOF
echo "yaml_exit:$?"

# 2. Check all apps declare revisionHistoryLimit (platform standard)
grep -rn "revisionHistoryLimit" argocd-apps/ 2>&1
echo "revisionHistoryLimit_count:$(grep -r 'revisionHistoryLimit' argocd-apps/ | wc -l | tr -d ' ')"

# 3. Check all apps reference the correct chart repo (no hardcoded external URLs except allowed ones)
grep -rn "repoURL:" argocd-apps/ 2>&1

# 4. Confirm no app references a hardcoded domain
grep -rn "sovereign-autarky\.dev" argocd-apps/ 2>&1 \
  && echo "HARDCODED-DOMAIN:FOUND (FAIL)" || echo "HARDCODED-DOMAIN:NONE (PASS)"
```

**Smoke test passes if:** `yaml_exit:0` AND `HARDCODED-DOMAIN:NONE`.

`revisionHistoryLimit` absence is a warning, not a failure, unless the story AC required it.

---

#### JSON / schema files (`feature/prd-*`)

```bash
# 1. Validate manifest.json
python3 -c "import json; json.load(open('prd/manifest.json'))" \
  && echo "manifest:VALID" || echo "manifest:INVALID"

# 2. Validate backlog.json
python3 -c "import json; json.load(open('prd/backlog.json'))" \
  && echo "backlog:VALID" || echo "backlog:INVALID"

# 3. Validate any story schema files
python3 - <<'EOF'
import glob, json, sys
files = glob.glob('prd/**/*.json', recursive=True)
errors = []
for f in files:
    try:
        json.load(open(f))
    except json.JSONDecodeError as e:
        errors.append(f"{f}: {e}")
if errors:
    print("JSON_INVALID:")
    for e in errors:
        print(f"  {e}")
    sys.exit(1)
else:
    print(f"JSON_VALID: {len(files)} files parsed successfully")
EOF
echo "json_exit:$?"

# 4. Confirm manifest.json has required top-level keys
python3 - <<'EOF'
import json
d = json.load(open('prd/manifest.json'))
required = ['activeSprint', 'sprints']
missing = [k for k in required if k not in d]
if missing:
    print(f"MANIFEST_SCHEMA:MISSING_KEYS: {missing}")
    exit(1)
print("MANIFEST_SCHEMA:VALID")
EOF
echo "manifest_schema_exit:$?"

# 5. Confirm every story in the active sprint has required fields
python3 - <<'EOF'
import json
manifest = json.load(open('prd/manifest.json'))
sprint_file = manifest['activeSprint']
sprint = json.load(open(sprint_file))
required = ['id', 'title', 'acceptanceCriteria', 'passes']
errors = []
for story in sprint.get('stories', []):
    missing = [k for k in required if k not in story]
    if missing:
        errors.append(f"{story.get('id','?')}: missing {missing}")
if errors:
    print("STORY_SCHEMA:INVALID:")
    for e in errors:
        print(f"  {e}")
    exit(1)
print(f"STORY_SCHEMA:VALID: {len(sprint['stories'])} stories checked")
EOF
echo "story_schema_exit:$?"
```

**Smoke test passes if:** `json_exit:0` AND `manifest_schema_exit:0` AND `story_schema_exit:0`.

### Step 4 — Record smoke test results

After running the appropriate tests for each story, record results on the story object using
Python. Update the sprint file in place:

```python
import json

sprint_file = "prd/phase-0-ceremonies.json"  # from manifest.json activeSprint
with open(sprint_file) as f:
    sprint = json.load(f)

for story in sprint['stories']:
    if not story.get('passes') or story.get('reviewed'):
        continue  # skip: not a smoke-test target

    # Set from actual test run:
    passed = True   # or False
    failures = []   # list of failure strings, e.g. ["lint_exit:1", "PDB:MISSING"]
    summary = "..."  # one-line summary of what ran

    story.setdefault('smokeTestResults', {})
    story['smokeTestResults'] = {
        'ran': True,
        'passed': passed,
        'summary': summary,
        'failures': failures,
    }

    if not passed:
        story['passes'] = False
        story['reviewed'] = False
        story.setdefault('reviewNotes', [])
        story['attempts'] = story.get('attempts', 0) + 1
        story['reviewNotes'].append(
            f"[Smoke Test {story['attempts']}] FAILED: {', '.join(failures)}. "
            f"Fix these before review ceremony."
        )

with open(sprint_file, 'w') as f:
    json.dump(sprint, f, indent=2)
```

**Important:** The `summary` field must be a condensed but accurate description of what ran.
Include exit codes and key findings. Example:

```
"helm lint: exit 0 (1 warning: missing icon), template: exit 0 (14 kinds), PDB: FOUND, anti-affinity: FOUND, latest-tag: NONE"
```

Do not write "all checks passed" as a summary — write what actually ran and what it produced.

### Step 5 — Write STORIES_REOPENED signal

After processing all stories, check if any had `passes` reset to `false`:

```python
import os

any_reopened = any(
    not story.get('passes') and story.get('smokeTestResults', {}).get('ran')
    for story in sprint['stories']
)

if any_reopened:
    with open('/tmp/sovereign-smoke-signal', 'w') as f:
        f.write('STORIES_REOPENED=true\n')
    print("Signal written: /tmp/sovereign-smoke-signal")
else:
    try:
        os.remove('/tmp/sovereign-smoke-signal')
    except FileNotFoundError:
        pass
```

### Step 6 — Print smoke test report

Print the full report after all tests have run. Use this format exactly:

```
=== Smoke Test Ceremony ===
Sprint: prd/phase-0-ceremonies.json
Stories tested: <N>

P0-001 scripts/ralph/ralph.sh  [ralph/ceremony scripts]
  bash -n ralph.sh:        exit 0
  bash -n ceremonies.sh:   exit 0
  shellcheck ralph.sh:     exit 0
  shellcheck ceremonies.sh exit 0
  --dry-run:               exit 0  [3 lines of output]
  RESULT: PASS

P0-002 prd/ structure  [JSON/schema files]
  manifest.json:           VALID
  backlog.json:            VALID
  all prd/**/*.json:       VALID (6 files)
  manifest schema:         VALID (activeSprint, sprints present)
  story schema:            VALID (4 stories checked)
  RESULT: PASS

P0-003 charts/cilium  [Helm chart]
  helm dependency update:  exit 0
  helm lint:               exit 0  [WARNING: chart icon not set]
  helm template:           exit 0  (14 kinds rendered)
  PDB:                     FOUND
  anti-affinity:           FOUND
  :latest tags:            NONE (PASS)
  hardcoded domain:        NONE (PASS)
  RESULT: PASS

P0-004 charts/vault  [Helm chart]
  helm dependency update:  exit 0
  helm lint:               exit 1
    [1 chart(s) linted, 0 chart(s) failed]
    Error: ... values.yaml: replicaCount: value must be >= 2
  helm template:           SKIPPED (lint failed)
  RESULT: FAIL  → passes reset to false, attempts: 2, reviewNote appended

---
Stories smoke-tested: 4
  PASS: 3
  FAIL: 1 (passes reset to false, reviewNotes updated)

STORIES_REOPENED signal written to /tmp/sovereign-smoke-signal
Ralph must be re-run to fix the above stories before review ceremony.
```

If all stories pass:

```
---
Stories smoke-tested: 4
  PASS: 4
  FAIL: 0

All stories passed smoke testing.
Run review ceremony next:
  claude < scripts/ralph/ceremonies/review.md
```

## Output verbosity rules

- Always show the actual exit code, not just PASS/FAIL.
- Always show warnings even when exit code is 0 — a lint warning today is a failure tomorrow.
- If a command produces more than 20 lines of output, show the first 10 and last 10, with
  `... (<N> lines omitted) ...` in between.
- If a command produces no output at all, note: `(no output)` — do not silently skip it.
- If a required tool is not installed, note it explicitly:
  ```
  shellcheck:  SKIP (not installed — brew install shellcheck)
  ```
  Do NOT mark as PASS when you cannot verify. Record `'passed': False` in `smokeTestResults`
  and append a reviewNote: `"Cannot smoke test: shellcheck not installed."`.

## Idempotency guarantee

- Stories with `reviewed: true` are always skipped.
- Stories with `passes: false` (not yet rebuilt by Ralph) are skipped — nothing to test.
- Running this ceremony twice produces the same result: the second run will find no stories
  where `passes: true AND reviewed: false` (they were either already smoke-tested and passed,
  or reset to `passes: false` and are now awaiting Ralph).
- A story's `smokeTestResults` is overwritten on each run, not appended.
