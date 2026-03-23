# Retro Patch: Phase 2 — foundations
Generated: 2026-03-22T00:00:00Z

## Suggested additions to CLAUDE.md (LEARNINGS section)

### New patterns discovered this sprint

- **AC "file X exists" is literal**: Even if a functional requirement is met via a subchart
  or upstream dependency, acceptance criteria about file existence must be verified on disk.
  Do not assume "functionally equivalent" satisfies a file existence AC.

- **shellcheck SC2317 unreachable code**: Fires when a function with `exit 1` is called and
  shellcheck thinks downstream code is unreachable — do NOT source interface.sh (it has exit-1
  stubs). Only source actual implementations.

- **SSH_OPTS must be bash array**: `SSH_OPTS=(-o StrictHostKeyChecking=no -i "$KEY")` expanded
  as `"${SSH_OPTS[@]}"` — not a string variable — to satisfy shellcheck SC2086.

- **Provider doc filenames must match content**: "Remove all references to X" means the filename
  too, not just the content. `aws-ec2-free-tier.md` must be renamed to `aws-ec2.md` if the doc
  no longer covers free tier.

## Stories that failed review (re-opened)

| Story | Attempts | Root cause |
|-------|----------|------------|
| 015 | 2 | docs/providers/aws-ec2-free-tier.md still named with "free-tier" and contained 3 free-tier references despite AC saying "remove all references" |

## Quality gate improvements suggested

- Add explicit filename check to quality gates: when an AC says "remove references to X",
  run `find . -name "*X*"` as well as `grep -r "X"` to catch both filename and content matches.

## Velocity note

Sprint points: 10 / 10 planned
Review pass rate: 75% (3 stories accepted on first review / 4 total)
Stories accepted: 4/4
