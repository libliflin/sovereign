# Retro Patch: Increment 22 — remediation
Generated: 2026-03-29T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 6 | 8 pts |
| Incomplete → backlog | 1 | 1 pt |
| Killed | 0 | — |

## 5 Whys: incomplete stories

### KAIZEN-004r: Kaizen: Pre-retro guard — auto-run review before retro if passes:true stories exist

- Why 1: Story didn't pass review (2 attempts) → AC2 could not be verified; the test requires running ceremonies.sh with a fixture sprint file, but the command errored because ceremonies.py resolves sprint from manifest.json only.
- Why 2: AC2 required ceremonies.py to accept a `--sprint` flag → that flag was never built; the test infrastructure assumed a capability the code doesn't have.
- Why 3: Why was AC2 written to require a `--sprint` flag? → The story author wrote an integration test that mirrors how a developer would manually test the guard behavior, without checking whether ceremonies.py supported fixture-based invocation.
- Why 4: Why wasn't the infrastructure gap caught before the story entered the sprint? → The SMART "achievable" score (4/5) flagged "fixture creation adds scope" but stopped short of verifying that `ceremonies.py --sprint <fixture>` was a supported invocation path.
- Why 5: Why did SMART achievable not catch the hard blocker? → The SMART achievable check asks "can this be done in this environment?" but doesn't include a step to verify that test commands in the testPlan are syntactically valid and use flags that actually exist on the target script.

**Root cause**: AC2 was written as an integration test that references a `--sprint` flag in ceremonies.py which does not exist. The guard code itself IS implemented (ceremonies.py:538-558) and ACs 1, 3, 4 all pass — the story fails solely because the test harness for AC2 is missing.

**Decision**: Return to backlog as-is. The guard code is good; only the acceptance criterion for testing it needs to change.

**Remediation story**: KAIZEN-010r — "KAIZEN-004r remediation: rewrite AC2 as unit test of pre-retro guard logic"

## Flow analysis

Sprint avg story size: 1.3 pts
Point distribution: {1: 5, 2: 2}
Oversized (> 8 pts): 0
Split candidates (5–8 pts): 0

No flow problems. All stories were correctly sized. The single incomplete story failed on an AC design issue, not on scope creep.

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **SMART achievable must validate test command flags**: Before accepting a story, verify that every shell command in `testPlan` and `acceptanceCriteria` uses only flags and invocation paths that actually exist. A command like `ceremonies.sh --sprint <fixture>` should be rejected if `--sprint` is not a documented flag.
- **Integration test ACs must be self-contained**: If an AC requires temporarily mutating a system file (e.g. manifest.json) or invoking a live AI ceremony, it is not verifiable in a CI-safe way. Rewrite such ACs as unit tests that import and call the logic directly.
- **Guard code ≠ verified story**: A story can have working implementation with all other ACs green and still fail review if the test harness for one AC doesn't exist. The review ceremony correctly refused to accept it — the process worked.

## Quality gate improvements

- Add a pre-grooming check: for any story with a `testPlan` or AC containing a shell invocation, verify the binary/script exists and the flags are valid (`<cmd> --help` or `grep` for the flag in the script). This would have caught `ceremonies.sh --start-at retro` with a fixture path before the story entered the sprint.
- SMART achievable scoring should include: "Does every command in the testPlan run against this codebase as written?" If yes → 5. If any command uses an assumed-but-unverified flag → max score 3.

## Velocity

| Increment | Points Completed | Stories Accepted | Pass Rate |
|-----------|-----------------|------------------|-----------|
| 22 (remediation) | 8 | 6 / 7 | 14.3% first-review |

Sprint points accepted: 8 / 9 planned
First-review pass rate: 14.3% (1 of 7 — GGE-G5-andon passed with attempts=0; all others needed 1 cycle)

Note: The 14.3% figure reflects the `attempts == 0` formula. In practice, 5 of 6 accepted stories passed on their first review attempt (attempts=1 = one review cycle, passed). Only KAIZEN-004r required 2 cycles and was not accepted. The formula undercounts first-pass success because it counts attempts=0 as "never reviewed" rather than "passed immediately."

Retro patch → prd/retro-patch-increment22.md
