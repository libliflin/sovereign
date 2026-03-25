"""
advance.py — Close the active sprint and activate the next phase.

Called by ceremonies.py step 8. Can also be run standalone via prd/advance.py.

Rules (honest-close model):
  - Every story must be reviewed:true, returnedToBacklog:true, or status:killed.
  - If any story is in limbo, the retro ceremony hasn't run yet — block.
  - Partial delivery is fine; the retro owns the honest accounting.
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def run(repo_root: Path, dry_run: bool = False) -> int:
    """
    Advance the active sprint to the next phase.
    Returns 0 on success, 1 on error.
    """
    manifest_path = repo_root / "prd" / "manifest.json"

    with open(manifest_path) as f:
        manifest = json.load(f)

    active_sprint = manifest.get("activeSprint")
    current_phase = manifest.get("currentIncrement")

    print(f"  Active sprint    : {active_sprint}")
    print(f"  Current increment: {current_phase}")

    # -- Guard: retro must have resolved every story ---------------------------
    sprint_path = repo_root / active_sprint if active_sprint else None
    if sprint_path and sprint_path.exists():
        with open(sprint_path) as f:
            sprint = json.load(f)

        limbo = [
            s for s in sprint.get("stories", [])
            if not s.get("reviewed", False)
            and not s.get("returnedToBacklog", False)
            and s.get("status") != "killed"
        ]
        if limbo:
            print(f"\n  ERROR: {len(limbo)} stories are neither accepted, returned, nor killed.", file=sys.stderr)
            print("  Run retro first:  ./scripts/ralph/ceremonies.sh --start-at retro", file=sys.stderr)
            for s in limbo:
                print(f"    - {s['id']}: passes={s.get('passes')} reviewed={s.get('reviewed')}", file=sys.stderr)
            return 1

        # Metrics
        stories = sprint.get("stories", [])
        total = len(stories)
        accepted = [s for s in stories if s.get("reviewed", False)]
        n_accepted = len(accepted)
        n_incomplete = len([s for s in stories if s.get("returnedToBacklog", False)])
        n_killed = len([s for s in stories if s.get("status") == "killed"])
        first_pass = len([s for s in accepted if s.get("attempts", 0) == 0])
        pass_rate = round(first_pass / total * 100, 1) if total > 0 else 0.0
        points_done = sum(s.get("points", 0) for s in accepted)

        print(f"\n  Sprint metrics:")
        print(f"    Accepted   : {n_accepted} / {total} stories  ({points_done} pts)")
        print(f"    Returned   : {n_incomplete}  |  Killed: {n_killed}")
        print(f"    First-pass : {pass_rate}%")
    else:
        points_done = 0
        pass_rate = 0.0
        n_accepted = 0
        n_incomplete = 0
        n_killed = 0

    # -- Find next increment ---------------------------------------------------
    phases = manifest.get("increments", [])
    phase_ids = [str(p.get("id")) for p in phases]

    try:
        current_idx = phase_ids.index(str(current_phase))
    except ValueError:
        print(f"\n  ERROR: currentIncrement '{current_phase}' not found in increments list.", file=sys.stderr)
        print(f"  Known increment IDs: {phase_ids}", file=sys.stderr)
        return 1

    if current_idx + 1 >= len(phases):
        next_phase_entry = None
        next_phase = None
    else:
        next_phase_entry = phases[current_idx + 1]
        next_phase = next_phase_entry.get("id")

    next_file = next_phase_entry.get("file") if next_phase_entry else None

    if not next_file:
        print(f"\n  All increments complete — no increment after '{current_phase}' found.")
        if not dry_run:
            _mark_complete(manifest, manifest_path, current_phase, points_done, pass_rate, n_accepted, n_incomplete)
        return 0

    print(f"  Next increment : {next_phase} → {next_file}")

    if dry_run:
        print("\n  [DRY RUN] Would:")
        print(f"    - Increment {current_phase} → complete")
        print(f"    - Increment {next_phase} → active")
        print(f"    - activeSprint → {next_file}")
        print(f"    - currentIncrement → {next_phase}")
        return 0

    # -- Update manifest — current state only, no historical log ---------------
    for p in phases:
        if str(p.get("id")) == str(current_phase):
            p["status"] = "complete"
        if str(p.get("id")) == str(next_phase):
            p["status"] = "active"

    manifest["activeSprint"] = next_file
    manifest["currentIncrement"] = next_phase

    # Strip any historical fields that may have been written by older versions
    manifest.pop("velocity", None)
    manifest.pop("sprintHistory", None)
    for p in phases:
        for field in ("endDate", "startDate", "pointsCompleted", "storiesAccepted",
                      "storiesIncomplete", "storiesKilled", "reviewPassRate",
                      "pointsTotal", "storiesTotal"):
            p.pop(field, None)

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"\n  ✓ Increment {current_phase} → complete")
    print(f"  ✓ Increment {next_phase} → active")
    print(f"  ✓ activeSprint → {next_file}")
    print(f"\n  Next: run planning ceremony to populate {next_file}")
    print(f"    ./scripts/ralph/ceremonies.sh --tool claude --start-at plan")
    return 0


def _mark_complete(manifest, path, phase, points, pass_rate, accepted, incomplete):
    for p in manifest.get("increments", []):
        if str(p.get("id")) == str(phase):
            p["status"] = "complete"
    # Strip any historical fields
    manifest.pop("velocity", None)
    manifest.pop("sprintHistory", None)
    with open(path, "w") as f:
        json.dump(manifest, f, indent=2)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Advance active sprint to next phase")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).parent.parent.parent.parent)
    args = parser.parse_args()
    sys.exit(run(args.repo_root, dry_run=args.dry_run))
