# Brand

## Identity

Technically precise, zero-compromise, working-engineer voice. The project speaks like a
senior infrastructure engineer with strong opinions about correctness — terse in output,
specific in error messages, willing to say "this is not configurable" without softening it.
It names things deliberately (autarky, not self-hosted-mode; invariant, not setting; gate,
not check; ceremony, not step) and trusts the reader to know what those words mean.

The project has principles it will not trade away, and it says so plainly. But it doesn't
moralize — it states the invariant and moves on.

---

## How We Speak

**When we say no:**
Hard stops with exact locations. `BLOCKER.` is a term of art, not a mood. The scope
document doesn't hedge: "Cloud equivalents are not acceptable substitutes — they
reintroduce vendor dependency." The contract validator doesn't offer a workaround:
`"AUTARKY VIOLATION: {field} must be true (got {value!r}). This is not configurable —
it is an invariant of the sovereign contract."` (from `contract/validate.py:104–106`).
When the answer is no, the no is complete.

**When we fail:**
Machine-parseable output, always the same shape.
`FAIL:{chart_name}:{specific_reason}` — colon-delimited, no prose wrapper
(from `scripts/ha-gate.sh:119,129,134,149`).
`CONTRACT VALIDATION FAILED: {values_path}` followed by `  x {error}`, one per line
(from `contract/validate.py:120–126`).
The structure is designed to be diffed, grepped, and scripted against — not read aloud.

**When we explain:**
Numbered criteria, falsifiable claims. "A component qualifies as foundation-neutral if
ALL of the following are true" — then four specific, checkable conditions
(from `docs/governance/sovereignty.md`). Not "we prefer" or "generally speaking."
Past incidents are taught as lessons: "The lesson: do not wait for the official
'community fork' announcement before acting." Present tense, assumes reader has agency
(from `docs/governance/sovereignty.md:81–83`).

**When we onboard a new user:**
Reassurance through negation. Prerequisites for the kind path: "That's it. No cloud
account, no domain, no credentials." (from `README.md:116`). The README closes the
quick-start section with three verbs: "Clone, configure, run." — no feature list,
no promise of magic (from `README.md:4`).

**When we succeed:**
Equally terse. `PASS:{chart_name}` (from `scripts/ha-gate.sh:172`).
`CONTRACT VALID: {values_path}` (from `contract/validate.py:128`).
`Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed` — summary line, always printed,
never omitted even on full success (from `scripts/ha-gate.sh:178`). No celebration,
no congratulations. The output ends.

---

## The Thing We'd Never Do

We'd never bury the actionable detail in prose. Every failure output has the same
structure: `FAIL:{thing}:{reason}`. The reason is specific (not "validation failed" but
`replicaCount < 2`, `no PodDisruptionBudget in rendered templates`,
`chart not found in platform/charts/ or cluster/kind/charts/`). A reader should be able
to fix the error in one read. Wall-of-explanation output that makes the user scan for
what actually went wrong is not our voice.

---

## Signals to Preserve

**Colon-delimited status output.** `PASS:`/`FAIL:` then name, then reason. This shape
appears in `ha-gate.sh` and `cost-gate.sh`. New scripts should match it — it's a pattern
readers and scripts depend on.

**Vocabulary with precise meaning.** Autarky (not "air-gap"), invariant (not "required
setting"), gate (not "check"), sovereign contract (not "config spec"). These words carry
specific governance meaning throughout the repo. Diluting them with synonyms blurs the
concepts they name.

**"Not configurable" as a complete sentence.** When something is a hard invariant, the
project says so directly and stops. It does not offer a workaround, a flag, or an escape
hatch. The absence of an escape hatch IS the guarantee.
