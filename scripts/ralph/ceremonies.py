#!/usr/bin/env python3
"""
ceremonies.py — Sovereign Platform sprint orchestrator.

Replaces ceremonies.sh. Runs the full sprint lifecycle:
  0. Plan           — AI: backlog -> sprint file (skipped if sprint active)
  1. Pre-flight     — bash: tools, credentials, cluster access (hard exit on fail)
  2. SMART Check    — AI scores stories; bash validates scores >= 3
  3. Execute        — ralph.sh: AI implements stories (skipped if all passing)
  4. Smoke Test     — bash: helm lint, shellcheck, yq (hard gate)
  5. Proof of Work  — bash: git ls-remote, gh pr list (hard gate)
  6. Review         — AI: adversarial AC verification (runs once — no retry loop)
  7. Retro          — AI: 5 Whys on incomplete stories, generates remediation backlog
  8. Advance        — close sprint cleanly; partial delivery is honest delivery

Usage:
  ./ceremonies.py [--phase N] [--tool claude|amp] [--max-retries 3] [--dry-run] [--skip-plan]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Resolve repo root (ceremonies.py lives in scripts/ralph/)
SCRIPT_DIR = Path(__file__).parent.resolve()
REPO_ROOT = (SCRIPT_DIR / "../..").resolve()

# Add lib to path
sys.path.insert(0, str(SCRIPT_DIR))
from lib import prd_model, sprint as sprint_lib, gates, ai as ai_lib, advance as advance_lib


def _find_not_smart(sprint: dict) -> list[dict]:
    """Return stories with any SMART dimension < 3 (0 = unscored, skip those)."""
    result = []
    for s in sprint.get("stories", []):
        sm = s.get("smart")
        if not sm:
            continue
        scores = [
            sm.get("specific", 0),
            sm.get("measurable", 0),
            sm.get("achievable", 0),
            sm.get("relevant", 0),
            sm.get("timeBound", 0),
        ]
        # Skip if all zeros (not yet scored by SMART check)
        if all(v == 0 for v in scores):
            continue
        if min(scores) < 3:
            result.append(s)
    return result


def sep(label: str = "") -> None:
    line = "=" * 64
    if label:
        print(f"\n{line}")
        print(f"  {label}")
        print(line)
    else:
        print(line)


def header(phase_num, active_sprint: str, log_file: Path) -> None:
    print("\n" + "=" * 66)
    print(f"  PHASE {phase_num} SPRINT CEREMONIES  —  {datetime.now().strftime('%c')}")
    print(f"  Sprint : {active_sprint}")
    print(f"  Log    : {log_file}")
    print("=" * 66)


def log_step(n: int, total: int, label: str) -> None:
    print(f"\nSTEP {n}/{total} — {label}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Sovereign sprint ceremonies orchestrator")
    parser.add_argument("--phase", type=str, help="Phase number to run")
    parser.add_argument("--tool", choices=["claude", "amp"], default="claude")
    parser.add_argument("--max-retries", type=int, default=3)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-plan", action="store_true")
    parser.add_argument(
        "--start-at",
        choices=["plan", "preflight", "smart", "execute", "smoke", "proof", "review", "retro", "advance"],
        default="plan",
        help="Skip directly to a ceremony step (default: plan)",
    )
    args = parser.parse_args()

    # -- Resolve sprint --------------------------------------------------------
    manifest = prd_model.Manifest(REPO_ROOT)

    if args.phase:
        phase = manifest.phase(args.phase)
        if not phase:
            print(f"ERROR: Phase {args.phase} not found in manifest", file=sys.stderr)
            return 1
        active_sprint = phase["file"]
        phase_num = args.phase
    else:
        active_sprint = manifest.active_sprint
        phase_num = manifest.current_phase
        if not active_sprint:
            print("ERROR: No activeSprint in manifest. Use --phase N.", file=sys.stderr)
            return 1

    sprint_file = REPO_ROOT / active_sprint

    # -- Restore sprint file if it has uncommitted gate resets ----------------
    if sprint_file.exists():
        result = subprocess.run(
            f"git diff --quiet HEAD -- {active_sprint}",
            shell=True, cwd=REPO_ROOT
        )
        if result.returncode != 0:
            print(f"\n  Sprint file has uncommitted changes (likely from a gate reset).")
            print(f"  Restoring from HEAD to ensure clean state...")
            subprocess.run(
                f"git restore -- {active_sprint}",
                shell=True, cwd=REPO_ROOT
            )

    # -- Logging ---------------------------------------------------------------
    log_dir = REPO_ROOT / "prd" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_file = log_dir / f"phase-{phase_num}-{timestamp}.log"

    if args.dry_run:
        print(f"=== ceremonies.py DRY RUN ===")
        print(f"\nActive sprint : {active_sprint}")
        print(f"Sprint file   : {sprint_file}")
        print(f"Tool          : {args.tool}")
        print(f"Max retries   : {args.max_retries}")
        print(f"\nSteps that WOULD execute:")
        steps = [
            "PLAN         — AI populates sprint from backlog (skipped if sprint active)",
            "PRE-FLIGHT   — bash: tools, credentials (hard exit on fail)",
            "SMART CHECK  — AI scores stories; bash validates >= 3",
            "EXECUTE      — ralph.sh (skipped if all stories passing)",
            "SMOKE TEST   — bash: helm lint, shellcheck, yq",
            "PROOF CHECK  — bash: git ls-remote, gh pr list",
            "REVIEW       — AI: adversarial AC check",
            "RETRO        — AI: learnings extraction",
            "ADVANCE      — close sprint, activate next",
        ]
        for i, s in enumerate(steps):
            print(f"  {i}. {s}")
        print("\nNo files modified (--dry-run).")
        return 0

    # Step order for --start-at comparisons
    STEP_ORDER = ["plan", "preflight", "smart", "execute", "smoke", "proof", "review", "retro", "advance"]

    def should_run(step: str) -> bool:
        return STEP_ORDER.index(step) >= STEP_ORDER.index(args.start_at)

    header(phase_num, active_sprint, log_file)
    if args.start_at != "plan":
        print(f"  ⏭  --start-at {args.start_at}: skipping earlier steps.")

    phase_data = manifest.phase(phase_num)
    phase_status = phase_data.get("status", "unknown") if phase_data else "unknown"

    # -- STEP 0: PLAN ----------------------------------------------------------
    log_step(0, 8, "SPRINT PLANNING")
    if not should_run("plan") or args.skip_plan:
        print("  skipped (--start-at or --skip-plan)")
        if not sprint_file.exists():
            print(f"FATAL: Sprint file missing: {sprint_file}", file=sys.stderr)
            return 1
    elif not sprint_file.exists() or phase_status == "pending":
        print(f"  Phase status: {phase_status}. Sprint file: {'exists' if sprint_file.exists() else 'MISSING'}")
        print(f"  Running plan ceremony to select stories from backlog...")
        sep("AI CEREMONY: Sprint Planning")
        output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/plan.md", log_file)
        if ai_lib.is_rate_limited(output):
            ai_lib.sleep_until_reset(output)
            output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/plan.md", log_file)
        if not sprint_file.exists():
            print(f"FATAL: Plan ceremony ran but sprint file still missing: {sprint_file}", file=sys.stderr)
            return 1
        sprint = sprint_lib.load(sprint_file)
        print(f"\n  Sprint file ready: {sprint_file} ({len(sprint.get('stories', []))} stories)")
    else:
        print(f"  skipped (sprint exists, phase={phase_status})")

    sprint = sprint_lib.load(sprint_file)

    # -- STEP 1: PRE-FLIGHT ----------------------------------------------------
    log_step(1, 8, "PRE-FLIGHT (bash-enforced)")
    if not should_run("preflight"):
        print("  skipped (--start-at)")
    else:
        sep()
        print("  Core tools:")
        passed, missing = gates.preflight(REPO_ROOT, sprint)
        if not passed:
            print(f"\nFATAL: Pre-flight failed. Missing: {', '.join(missing)}")
            print("Fix the above and re-run ceremonies.py")
            return 1
        print("\n  Pre-flight passed — all required capabilities present.")

    # -- STEP 2: SMART CHECK ---------------------------------------------------
    log_step(2, 8, "SMART CHECK")
    if not should_run("smart"):
        print("  skipped (--start-at)")
    else:
        print("  (AI scores stories; bash reads the JSON and hard-exits if any score < 3)")
        sep("AI CEREMONY: SMART Check")
        output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/smart-check.md", log_file)
        while ai_lib.is_rate_limited(output):
            ai_lib.sleep_until_reset(output)
            output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/smart-check.md", log_file)

        sprint = sprint_lib.load(sprint_file)
        not_smart = _find_not_smart(sprint)
        if not_smart:
            print(f"\nSMART CHECK FAILED: {len(not_smart)} stories scored < 3 on at least one dimension:")
            for s in not_smart:
                sm = s["smart"]
                print(f"  - {s['id']}: {s['title']}")
                print(f"    {sm.get('notes', '')}")
            print(f"\n  Auto-invoking story-split ceremony to self-heal...")
            sep("AI CEREMONY: Story Split")
            split_output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/story-split.md", log_file)
            while ai_lib.is_rate_limited(split_output):
                ai_lib.sleep_until_reset(split_output)
                split_output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/story-split.md", log_file)

            print(f"\n  Re-scoring split stories with SMART check...")
            sep("AI CEREMONY: SMART Check (post-split)")
            rescore_output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/smart-check.md", log_file)
            while ai_lib.is_rate_limited(rescore_output):
                ai_lib.sleep_until_reset(rescore_output)
                rescore_output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/smart-check.md", log_file)

            sprint = sprint_lib.load(sprint_file)
            not_smart = _find_not_smart(sprint)
            if not_smart:
                print(f"\nSMART CHECK STILL FAILING after story split: {len(not_smart)} stories:")
                for s in not_smart:
                    sm = s["smart"]
                    print(f"  - {s['id']}: {s['title']}")
                    print(f"    {sm.get('notes', '')}")
                print("\nFATAL: Story split did not resolve SMART failures. Manual intervention required.")
                return 1
            print(f"  Story split resolved all SMART issues — sub-stories are sprint-ready.")

        print(f"\n  SMART check passed — all {len(sprint.get('stories', []))} stories are sprint-ready.")

    # -- EXECUTE + SMOKE + PROOF: retry only on gate failures ------------------
    if not should_run("execute"):
        log_step(3, 8, "EXECUTE")
        print("  skipped (--start-at)")
        log_step(4, 8, "SMOKE TEST")
        print("  skipped (--start-at)")
        log_step(5, 8, "PROOF OF WORK")
        print("  skipped (--start-at)")
    else:
        for retry in range(args.max_retries + 1):
            if retry > 0:
                print(f"\n{'─' * 20} RETRY {retry} of {args.max_retries} {'─' * 20}")

            # -- STEP 3: EXECUTE -----------------------------------------------
            log_step(3, 8, "EXECUTE")
            sprint = sprint_lib.load(sprint_file)
            needing_work = sprint_lib.stories_needing_work(sprint)

            if not needing_work:
                print(f"  All {len(sprint.get('stories', []))} stories already passing — skipping execute.")
                print("  Proceeding directly to smoke test.")
            else:
                print(f"  Stories needing work: {len(needing_work)} / {len(sprint.get('stories', []))}")
                print("  Clearing stale failure context...")
                sprint_lib.clear_failures(sprint_file)

                ralph = SCRIPT_DIR / "ralph.sh"
                print(f"  Running ralph.sh --prd {active_sprint} --tool {args.tool} 10")
                print()
                ralph_exit = ai_lib.run_ralph(ralph, sprint_file, args.tool, 10, log_file)
                if ralph_exit != 0:
                    print(f"  WARNING: ralph.sh exited {ralph_exit}")

                sprint = sprint_lib.load(sprint_file)
                passing = sprint_lib.stories_passing(sprint)
                print(f"\n  Stories passing after execute: {len(passing)} / {len(sprint.get('stories', []))}")

            # -- STEP 4: SMOKE TEST --------------------------------------------
            if not should_run("smoke"):
                log_step(4, 8, "SMOKE TEST")
                print("  skipped (--start-at)")
            else:
                log_step(4, 8, "SMOKE TEST (bash-enforced)")
                sep()
                smoke_passed, smoke_failures = gates.smoke_test(REPO_ROOT)
                sprint_lib.write_failures(sprint_file, "_lastSmokeTestFailures", smoke_failures)

                if not smoke_passed:
                    print(f"\nSMOKE TEST FAILED ({len(smoke_failures)} check(s) failed)")
                    print("  Failure details written to sprint._lastSmokeTestFailures[]")
                    count = sprint_lib.reset_passing_to_false(
                        sprint_file,
                        "[SMOKE-TEST-FAIL] Gates failed — see _lastSmokeTestFailures in sprint file."
                    )
                    print(f"  Reset {count} stories to passes:false.")
                    if retry < args.max_retries:
                        print(f"  Retrying execute (attempt {retry + 1} of {args.max_retries})...")
                        continue
                    else:
                        print(f"\nFATAL: Smoke test failed after {args.max_retries} retries. Manual intervention required.")
                        return 1

                print("\n  Smoke test passed.")

            # -- STEP 5: PROOF OF WORK -----------------------------------------
            if not should_run("proof"):
                log_step(5, 8, "PROOF OF WORK")
                print("  skipped (--start-at)")
            else:
                log_step(5, 8, "PROOF OF WORK (bash-enforced)")
                sep()
                sprint = sprint_lib.load(sprint_file)
                proof_passed, proof_failures = gates.proof_of_work(REPO_ROOT, sprint)
                sprint_lib.write_failures(sprint_file, "_lastProofOfWorkFailures", proof_failures)

                if not proof_passed:
                    print(f"\nPROOF OF WORK FAILED ({len(proof_failures)} check(s) failed)")
                    print("  Failure details written to sprint._lastProofOfWorkFailures[]")
                    count = sprint_lib.reset_passing_to_false(
                        sprint_file,
                        "[PROOF-FAIL] Branch not pushed or no PR — see _lastProofOfWorkFailures."
                    )
                    print(f"  Reset {count} stories to passes:false.")
                    if retry < args.max_retries:
                        print(f"  Retrying execute (attempt {retry + 1} of {args.max_retries})...")
                        continue
                    else:
                        print(f"\nFATAL: Proof of work failed after {args.max_retries} retries.")
                        return 1

                print("\n  Proof of work passed.")
            break  # Both gates passed — exit retry loop

    # -- STEP 6: REVIEW --------------------------------------------------------
    log_step(6, 8, "REVIEW")
    if not should_run("review"):
        print("  skipped (--start-at)")
    else:
        sep("AI CEREMONY: Review")
        output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/review.md", log_file)
        while ai_lib.is_rate_limited(output):
            ai_lib.sleep_until_reset(output)
            output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/review.md", log_file)

        # Surface what completed vs what didn't — retro handles the 5 Whys
        sprint = sprint_lib.load(sprint_file)
        accepted = [s for s in sprint.get("stories", []) if s.get("reviewed", False)]
        not_reviewed = [s for s in sprint.get("stories", []) if not s.get("reviewed", False)]
        print(f"\n  Accepted: {len(accepted)} / {len(sprint.get('stories', []))}")
        if not_reviewed:
            print(f"  Incomplete (returning to backlog via retro): {len(not_reviewed)}")
            for s in not_reviewed:
                print(f"    - {s['id']}: {s['title']}")

    # -- STEP 7: RETRO ---------------------------------------------------------
    log_step(7, 8, "RETRO")
    if not should_run("retro"):
        print("  skipped (--start-at)")
    else:
        sep("AI CEREMONY: Retrospective")
        output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/retro.md", log_file)
        while ai_lib.is_rate_limited(output):
            ai_lib.sleep_until_reset(output)
            output = ai_lib.run_ceremony(args.tool, SCRIPT_DIR / "ceremonies/retro.md", log_file)

    # -- STEP 8: ADVANCE -------------------------------------------------------
    log_step(8, 8, "ADVANCE")
    if not should_run("advance"):
        print("  skipped (--start-at)")
    else:
        rc = advance_lib.run(REPO_ROOT, dry_run=args.dry_run)
        if rc != 0:
            return rc

    print("\n" + "=" * 66)
    print(f"  SPRINT COMPLETE — Phase {phase_num} closed")
    print(f"  Log: {log_file}")
    print("=" * 66)
    return 0


if __name__ == "__main__":
    sys.exit(main())
