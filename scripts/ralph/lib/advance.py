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
import os
import sys
import time
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
        first_pass = len([story for story in accepted if len(story.get("reviewNotes", [])) == 0])
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
            manifest.pop("activeSprint", None)
            manifest.pop("currentIncrement", None)
            with open(manifest_path, "w") as f:
                json.dump(manifest, f, indent=2)
            print("  ✓ activeSprint cleared — orient will report platform complete.")
        _cleanup(repo_root, manifest, dry_run)
        return 0

    print(f"  Next increment : {next_phase} → {next_file}")

    if dry_run:
        print("\n  [DRY RUN] Would:")
        print(f"    - Increment {current_phase} → complete")
        print(f"    - Increment {next_phase} → active")
        print(f"    - activeSprint → {next_file}")
        print(f"    - currentIncrement → {next_phase}")
        _cleanup(repo_root, manifest, dry_run=True)
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

    _cleanup(repo_root, manifest, dry_run=False)

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


def _prune_backlog(repo_root: Path) -> int:
    """Remove completed/superseded stories from backlog.json. Git history is the archive."""
    backlog_path = repo_root / "prd" / "backlog.json"
    with open(backlog_path) as f:
        backlog = json.load(f)

    before = len(backlog["stories"])
    backlog["stories"] = [
        s for s in backlog["stories"]
        if s.get("status") not in ("complete", "superseded")
    ]
    pruned = before - len(backlog["stories"])

    if pruned:
        with open(backlog_path, "w") as f:
            json.dump(backlog, f, indent=2)
            f.write("\n")

    return pruned


def _delete_old_increments(repo_root: Path, manifest: dict) -> list[str]:
    """Delete increment files for completed phases. Manifest metadata is preserved."""
    deleted = []
    for phase in manifest.get("increments", []):
        if phase.get("status") != "complete":
            continue
        fpath = phase.get("file")
        if not fpath:
            continue
        full = repo_root / fpath
        if full.exists():
            full.unlink()
            deleted.append(fpath)
        phase.pop("file", None)
    return deleted


def _rotate_logs(repo_root: Path, max_age_days: int = 7) -> int:
    """Delete ceremony logs older than max_age_days. Logs are gitignored."""
    log_dir = repo_root / "prd" / "logs"
    if not log_dir.is_dir():
        return 0
    cutoff = time.time() - (max_age_days * 86400)
    deleted = 0
    for entry in log_dir.iterdir():
        if entry.is_file() and entry.stat().st_mtime < cutoff:
            entry.unlink()
            deleted += 1
    return deleted


def _cleanup(repo_root: Path, manifest: dict, dry_run: bool) -> None:
    """Run all post-advance cleanup. Called after manifest is written."""
    backlog_path = repo_root / "prd" / "backlog.json"
    backlog = json.load(open(backlog_path))
    n_prunable = sum(1 for s in backlog["stories"] if s.get("status") in ("complete", "superseded"))

    inc_files = []
    for p in manifest.get("increments", []):
        if p.get("status") == "complete" and p.get("file"):
            fp = repo_root / p["file"]
            if fp.exists():
                inc_files.append(p["file"])

    log_dir = repo_root / "prd" / "logs"
    cutoff = time.time() - (7 * 86400)
    n_old_logs = 0
    if log_dir.is_dir():
        n_old_logs = sum(1 for e in log_dir.iterdir() if e.is_file() and e.stat().st_mtime < cutoff)

    if dry_run:
        print(f"\n  [DRY RUN] Cleanup would:")
        print(f"    - Prune {n_prunable} completed stories from backlog.json")
        print(f"    - Delete {len(inc_files)} old increment files")
        print(f"    - Rotate {n_old_logs} log files older than 7 days")
        return

    pruned = _prune_backlog(repo_root)
    deleted_incs = _delete_old_increments(repo_root, manifest)
    rotated = _rotate_logs(repo_root)

    # Re-write manifest since _delete_old_increments removed file keys
    manifest_path = repo_root / "prd" / "manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    if pruned or deleted_incs or rotated:
        print(f"\n  Cleanup:")
        if pruned:
            print(f"    ✓ Pruned {pruned} completed stories from backlog.json")
        if deleted_incs:
            print(f"    ✓ Deleted {len(deleted_incs)} old increment files")
        if rotated:
            print(f"    ✓ Rotated {rotated} log files older than 7 days")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Advance active sprint to next phase")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).parent.parent.parent.parent)
    args = parser.parse_args()
    sys.exit(run(args.repo_root, dry_run=args.dry_run))
