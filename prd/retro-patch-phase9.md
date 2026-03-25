# Retro Patch: Phase 9 — sovereign-pm
Generated: 2026-03-25T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 1 | 2 pts |
| Incomplete → backlog | 0 | — |
| Killed | 0 | — |

## 5 Whys: incomplete stories

None. All stories accepted.

## Observations

### Increment / sprint goal mismatch

Story 035 was a documentation story (quickstart, architecture, provider guides), but the increment
was named `sovereign-pm` with a declared theme of building a Node.js/React PM web app. The sprint
goal text in the JSON correctly described the documentation work, but the increment metadata
(name, description) described the PM app.

This mismatch was flagged by the SMART ceremony (`relevant: 3`, with a note that the story
"conflicts with the increment's declared theme"). The story was accepted anyway because the
documentation work was genuinely valuable and unblocked. However, the Sovereign PM web app
itself was never scoped into a story and was not delivered.

**Action**: The Sovereign PM web app needs its own increment and stories in the backlog if it
is still a priority. It was left as an aspirational section in CLAUDE.md without a corresponding
sprint commitment.

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Sprint goal vs increment metadata must match.** When the sprintGoal text diverges from the
  increment name/description/themeGoal, the SMART ceremony will flag stories as less relevant
  but still pass them. Operators must align these fields during planning or the system will
  silently accept mis-categorised work.

- **Documentation sprints are valid delivery.** A sprint that delivers only documentation is
  honest and complete when the docs are the sprint goal. The ceremony system handled this
  correctly: markdownlint + file existence checks are sufficient quality gates for doc stories.

- **2-point doc story at the boundary of a single iteration is achievable.** Story 035 covered
  7 files (quickstart, architecture, 4 provider guides, README). The SMART score flagged it
  as borderline (achievable: 3). It passed on first attempt (attempts: 0), confirming the sizing
  was acceptable. Future doc stories of similar scope can be sized at 2 pts.

## Quality gate improvements

The current quality gates for documentation stories are:
- `markdownlint docs/ README.md` exits 0
- `ls -la` to confirm files exist
- `grep -i 'cost' docs/providers/*.md` to confirm cost estimates

These are sufficient for structural checks. Consider adding a word-count floor (e.g. each
provider guide must be >500 words) to prevent stub files from passing lint while being
content-empty.

## Velocity

| Increment | Name | Points | Stories Accepted | Pass Rate |
|-----------|------|--------|-----------------|-----------|
| 0 | ceremonies | 15 | — | 100% |
| 1 | bootstrap | 14 | — | 100% |
| 2h | ci-hardening | 7 | 4 | 75% |
| 2 | foundations | 10 | 4 | 75% |
| 3 | gitops-engine | 12 | 2 | 100% |
| 4 | autarky | 13 | 5 | 80% |
| 5 | security | 12 | 5 | 20% |
| 6 | observability | 8 | 4 | 100% |
| 7 | devex | 2 | 1 | 0% |
| 8 | testing-and-ha | 0 | 0 | 0% |
| **9** | **sovereign-pm** | **2** | **1** | **100%** |

Sprint points accepted: 2 / 2 planned
First-review pass rate: 100% (1 of 1 accepted on first review)

Retro patch → prd/retro-patch-phase9.md
