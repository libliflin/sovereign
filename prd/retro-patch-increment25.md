# Retro Patch: Phase 25 — kaizen
Generated: 2026-03-29T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 7 | 9 pts |
| Incomplete → backlog | 1 | 1 pt |
| Killed | 0 | — |

## 5 Whys: incomplete stories

### KAIZEN-013: Fix retro ceremony first-pass formula: attempts == 0 never matches accepted stories

- **Why 1**: Story didn't pass review → AC1 (`grep -n 'attempts' scripts/ralph/ceremonies.py | grep -E '== 0|== 1'`) returned empty / exit 1, so the acceptance criterion was not met.
- **Why 2**: The grep targeted `ceremonies.py` but the first-pass formula lives in `scripts/ralph/ceremonies/retro.md:206`, not in the orchestrator file.
- **Why 3**: The story was written assuming the formula was inlined in `ceremonies.py`. The Ralph ceremony system splits concerns: `ceremonies.py` orchestrates, but ceremony-specific logic lives in per-ceremony markdown files under `ceremonies/`.
- **Why 4**: The test plan also pointed to `ceremonies.py`, so running the test plan pre-implementation would have produced the same false negative. No one verified the actual file location before authoring the AC.
- **Why 5**: The "test contract first" norm requires running tests *after* implementation, but there is no norm requiring story authors to *verify file location* before writing grep-based ACs. An assumed path that doesn't exist produces a silent failure that only surfaces at review.

**Root cause**: Story ACs referenced an assumed file location that was never verified. The implementation was actually correct — `retro.md:206` already uses `attempts == 1` — but the AC was unverifiable because it pointed to the wrong file.

**Decision**: Return to backlog with corrected AC1 (check `retro.md` instead of `ceremonies.py`). No re-implementation required; only the acceptance criterion needs updating.

**Remediation story**: KAIZEN-013r — Verify KAIZEN-013 implementation with corrected AC pointing to retro.md

---

## Flow analysis

- Sprint avg story size: **1.25 pts** (10 pts / 8 stories)
- Point distribution: `{1: 6, 2: 2}`
- Oversized (> 8 pts): **0** — no planning gate violation
- Split candidates (5–8 pts): **0**
- Incomplete stories that are split candidates: 0 / 1 — grooming was appropriately granular

No grooming remediation required. The one incomplete story was 1 pt and failed due to an AC authoring error, not size.

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Verify file paths before writing grep-based ACs.** When a story's acceptance criterion uses `grep <pattern> <file>`, run that grep on the current codebase before committing the AC. If the file doesn't exist or the pattern returns empty, the AC is wrong — not the implementation. This is especially important in multi-file systems like Ralph where logic is split across `ceremonies.py` and `ceremonies/*.md`.
- **The "test contract first" norm applies to both pre-authoring and post-implementation.** Running the exact test command before writing the story catches wrong file assumptions early. The current norm only specifies post-implementation verification.

---

## Quality gate improvements

- The SMART ceremony's "measurable" scoring should ask: "Can you run the exact test command on the current codebase RIGHT NOW and get a non-empty result?" If the answer is no (e.g., the file doesn't exist yet), the story requires either a setup step or a different verification approach. KAIZEN-013 scored measurable: 5, but AC1 was fundamentally unverifiable because it assumed code lived in the wrong file.

---

## Velocity

| Increment | Stories Accepted | Points |
|-----------|-----------------|--------|
| 25 (kaizen) | 7 / 8 | 9 pts |

Sprint points accepted: **9 / 10 planned**
First-review pass rate: **87.5%** (7 of 8 stories accepted on first attempt)
