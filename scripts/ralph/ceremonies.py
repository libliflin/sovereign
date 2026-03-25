#!/usr/bin/env python3
"""
ceremonies.py — Sovereign Platform delivery machine.

One entry point. One decision at a time.

Default run (no flags) starts at ORIENT, which reads KPIs and decides
the correct next step automatically. Every step is reachable via
--start-at for manual override only.

Full step sequence:
  orient        — read KPIs, decide next step (no AI, no mutations)
  theme-review  — AI: validate / update strategic themes
  epic-breakdown— AI: decompose epics into sprint-sized stories
  backlog-groom — AI: score and refine story readiness
  plan          — AI: pull sprint-ready stories into sprint file
  preflight     — bash: tools, credentials (hard exit on fail)
  smart         — AI: score stories; bash validates all >= 3
  execute       — ralph.sh: implement stories
  smoke         — bash: helm lint, shellcheck, yq (hard gate)
  proof         — bash: git ls-remote, gh pr list (hard gate)
  review        — AI: adversarial AC verification
  retro         — AI: 5 Whys, backlog remediation, honest close
  sync          — AI: rewrite docs/state/architecture.md + agent.md (chart, not log)
  advance       — Python: close sprint, activate next phase

Usage:
  ./ceremonies.sh                          # orient decides everything
  ./ceremonies.sh --start-at execute       # manual override
  ./ceremonies.sh --start-at retro         # skip to retro
  ./ceremonies.sh --dry-run                # preview without mutations
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
REPO_ROOT = (SCRIPT_DIR / "../..").resolve()

sys.path.insert(0, str(SCRIPT_DIR))
from lib import prd_model, sprint as sprint_lib, gates, ai as ai_lib
from lib import advance as advance_lib, orient as orient_lib

# ---------------------------------------------------------------------------
# Step ordering — single source of truth
# ---------------------------------------------------------------------------
STEPS = [
    "orient",
    "theme-review",
    "epic-breakdown",
    "backlog-groom",
    "plan",
    "preflight",
    "smart",
    "execute",
    "smoke",
    "proof",
    "review",
    "retro",
    "sync",
    "advance",
]

TOTAL = len(STEPS) - 1  # orient is step 0


def step_num(name: str) -> int:
    return STEPS.index(name)


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
def sep(label: str = "") -> None:
    line = "=" * 64
    print(f"\n{line}")
    if label:
        print(f"  {label}")
        print(line)


def log_step(name: str) -> None:
    n = step_num(name)
    label = name.upper().replace("-", " ")
    print(f"\nSTEP {n}/{TOTAL} — {label}")


def _find_not_smart(sprint: dict) -> list[dict]:
    result = []
    for s in sprint.get("stories", []):
        sm = s.get("smart")
        if not sm:
            continue
        scores = [sm.get(d, 0) for d in ("specific", "measurable", "achievable", "relevant", "timeBound")]
        if all(v == 0 for v in scores):
            continue
        if min(scores) < 3:
            result.append(s)
    return result


def _eject_not_smart_stories(sprint_file: Path, not_smart: list[dict]) -> None:
    """Remove still-failing stories from sprint file and return them to backlog
    with a readinessNote explaining why they were ejected. This keeps the flow
    moving — no fatal, no carry-over. Toyota: half-finished work = 0 value."""
    import json

    bad_ids = {s["id"] for s in not_smart}

    # Update sprint file — remove the failing stories
    with open(sprint_file) as f:
        sprint = json.load(f)
    kept = [s for s in sprint.get("stories", []) if s["id"] not in bad_ids]
    sprint["stories"] = kept
    with open(sprint_file, "w") as f:
        json.dump(sprint, f, indent=2)

    # Return them to backlog with a readinessNote
    backlog_file = REPO_ROOT / "prd" / "backlog.json"
    with open(backlog_file) as f:
        backlog = json.load(f)

    backlog_ids = {s["id"] for s in backlog["stories"]}
    for story in not_smart:
        sid = story["id"]
        sm = story.get("smart", {})
        low_dims = [d for d in ("specific", "measurable", "achievable", "relevant", "timeBound")
                    if sm.get(d, 0) < 3]
        note = (f"Ejected from sprint by SMART gate (post-split still failing). "
                f"Low dimensions: {', '.join(low_dims)}. "
                f"Achievable < 3 usually means the story is too large — split further.")
        if sid in backlog_ids:
            for bs in backlog["stories"]:
                if bs["id"] == sid:
                    bs["readinessNote"] = note
        else:
            story["readinessNote"] = note
            backlog["stories"].append(story)

    with open(backlog_file, "w") as f:
        json.dump(backlog, f, indent=2)

    print(f"  Ejected {len(not_smart)} stories to backlog: {', '.join(sorted(bad_ids))}")


def _ai(tool: str, ceremony: str, log_file: Path) -> str:
    """Run an AI ceremony, sleeping on rate limit, returning output."""
    output = ai_lib.run_ceremony(tool, SCRIPT_DIR / "ceremonies" / ceremony, log_file)
    while ai_lib.is_rate_limited(output):
        ai_lib.sleep_until_reset(output)
        output = ai_lib.run_ceremony(tool, SCRIPT_DIR / "ceremonies" / ceremony, log_file)
    return output


def _git_commit(step: str, files: list[str], extra_msg: str = "") -> None:
    """Stage and commit ceremony outputs so each step leaves a clean git state.

    This is intentional and necessary: AI ceremonies write files but never
    commit them. Without commits after each step, a restart (rate limit,
    crash, manual re-run) triggers the sprint-file restore logic and reverts
    durable state like SMART scores, reviewed:true, and retro writes.

    Only called for durable state changes. Gate failure fields
    (_lastSmokeTestFailures, _lastProofOfWorkFailures, passes resets) are
    intentionally NOT committed — they are volatile and should be restored.
    """
    if not files:
        return
    add_cmd = f"git add {' '.join(files)}"
    rc1, _ = subprocess.run(add_cmd, shell=True, cwd=REPO_ROOT,
                             capture_output=True, text=True).returncode, None
    # Check if there's actually anything to commit
    rc_diff = subprocess.run("git diff --cached --quiet", shell=True, cwd=REPO_ROOT).returncode
    if rc_diff == 0:
        return  # nothing staged, skip commit
    msg = f"ceremonies: {step} — committed by delivery machine"
    if extra_msg:
        msg += f"\n\n{extra_msg}"
    subprocess.run(
        f'git commit -m "{msg}"',
        shell=True, cwd=REPO_ROOT, capture_output=True
    )
    print(f"  ✓ git committed: {step}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sovereign delivery machine — orient decides, machine executes.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--start-at",
        choices=STEPS,
        default="orient",
        metavar="STEP",
        help=f"Skip directly to STEP. One of: {', '.join(STEPS)}. Default: orient",
    )
    parser.add_argument("--tool", choices=["claude", "amp"], default="claude")
    parser.add_argument("--max-retries", type=int, default=3)
    parser.add_argument("--dry-run", action="store_true", help="Print what would run; no mutations")
    args = parser.parse_args()

    # Resolved at runtime so orient can override for default runs
    start_at = args.start_at
    user_overrode_start = (args.start_at != "orient")

    # -- Logging ---------------------------------------------------------------
    log_dir = REPO_ROOT / "prd" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_file = log_dir / f"ceremonies-{timestamp}.log"

    def should_run(step: str) -> bool:
        return step_num(step) >= step_num(start_at)

    # -- STEP 0: ORIENT --------------------------------------------------------
    log_step("orient")
    assessment = orient_lib.assess(REPO_ROOT)
    assessment.print_report()

    if assessment.is_blocked():
        return 1

    # DONE is intentionally unreachable — the machine never stops improving.

    # Orient sets start_at unless the user explicitly overrode it
    if not user_overrode_start:
        start_at = assessment.start_at()
        print(f"  Orient decision: starting at '{start_at}'")
    else:
        print(f"  Manual override: --start-at {start_at} (orient recommended '{assessment.start_at()}')")

    if args.dry_run:
        print(f"\n  [DRY RUN] Steps that would execute from '{start_at}':")
        for s in STEPS:
            marker = "→" if should_run(s) else "·"
            print(f"    {marker} {s}")
        print("\n  No files modified.")
        return 0

    # -- Resolve sprint --------------------------------------------------------
    manifest = prd_model.Manifest(REPO_ROOT)
    active_sprint = manifest.active_sprint
    increment_num = manifest.current_increment
    sprint_file = REPO_ROOT / active_sprint if active_sprint else None

    # Restore sprint file only if the uncommitted changes are gate-failure
    # fields (_lastSmokeTestFailures, _lastProofOfWorkFailures, passes resets).
    # Durable state (SMART scores, reviewed, retro writes) is committed after
    # each step so it is never in the "uncommitted changes" bucket on restart.
    if sprint_file and sprint_file.exists() and active_sprint:
        diff_result = subprocess.run(
            f"git diff HEAD -- {active_sprint}",
            shell=True, cwd=REPO_ROOT, capture_output=True, text=True
        )
        if diff_result.returncode == 0 and diff_result.stdout:
            diff_text = diff_result.stdout
            # Only restore if the diff contains gate-failure markers
            is_gate_noise = (
                "_lastSmokeTestFailures" in diff_text
                or "_lastProofOfWorkFailures" in diff_text
            )
            if is_gate_noise:
                print(f"\n  Sprint file has uncommitted gate-reset changes — restoring from HEAD...")
                subprocess.run(f"git restore -- {active_sprint}", shell=True, cwd=REPO_ROOT)
            else:
                print(f"\n  WARNING: sprint file has unexpected uncommitted changes (not gate noise).")
                print(f"  Inspect with: git diff HEAD -- {active_sprint}")

    # -- STEP 1: THEME-REVIEW --------------------------------------------------
    log_step("theme-review")
    if not should_run("theme-review"):
        print("  skipped")
    else:
        sep("AI CEREMONY: Theme Review")
        _ai(args.tool, "theme-review.md", log_file)
        _git_commit("theme-review", ["prd/gge.json", "prd/themes.json", "prd/epics.json"])

    # -- STEP 2: EPIC-BREAKDOWN ------------------------------------------------
    log_step("epic-breakdown")
    if not should_run("epic-breakdown"):
        print("  skipped")
    else:
        sep("AI CEREMONY: Epic Breakdown")
        _ai(args.tool, "epic-breakdown.md", log_file)
        _git_commit("epic-breakdown", ["prd/backlog.json", "prd/epics.json"])

    # -- STEP 3: BACKLOG-GROOM -------------------------------------------------
    log_step("backlog-groom")
    if not should_run("backlog-groom"):
        print("  skipped")
    else:
        sep("AI CEREMONY: Backlog Grooming")
        _ai(args.tool, "backlog-groom.md", log_file)
        _git_commit("backlog-groom", ["prd/backlog.json"])

    # -- STEP 4: PLAN ----------------------------------------------------------
    log_step("plan")
    if not should_run("plan"):
        print("  skipped")
        if sprint_file and not sprint_file.exists():
            print(f"FATAL: Sprint file missing: {sprint_file}", file=sys.stderr)
            return 1
    else:
        increment_data = manifest.increment(increment_num)
        increment_status = increment_data.get("status", "unknown") if increment_data else "unknown"
        if not sprint_file or not sprint_file.exists() or increment_status == "pending":
            print(f"  Running plan ceremony (increment={increment_status}, sprint={'missing' if not sprint_file or not sprint_file.exists() else 'exists'})...")
            sep("AI CEREMONY: Sprint Planning")
            _ai(args.tool, "plan.md", log_file)
            # Reload after plan writes the sprint file
            manifest = prd_model.Manifest(REPO_ROOT)
            active_sprint = manifest.active_sprint
            sprint_file = REPO_ROOT / active_sprint if active_sprint else None
            if not sprint_file or not sprint_file.exists():
                print(f"FATAL: Plan ceremony ran but sprint file still missing.", file=sys.stderr)
                return 1
            sprint = sprint_lib.load(sprint_file)
            print(f"\n  Sprint ready: {active_sprint} ({len(sprint.get('stories', []))} stories)")
            _git_commit("plan", [str(active_sprint), "prd/manifest.json"])
        else:
            sprint = sprint_lib.load(sprint_file)
            print(f"  skipped (sprint exists, increment={increment_status}, {len(sprint.get('stories', []))} stories)")

    if not sprint_file or not sprint_file.exists():
        print("FATAL: No sprint file available. Cannot continue.", file=sys.stderr)
        return 1

    sprint = sprint_lib.load(sprint_file)

    # -- STEP 5: PREFLIGHT -----------------------------------------------------
    log_step("preflight")
    if not should_run("preflight"):
        print("  skipped")
    else:
        sep()
        passed, missing = gates.preflight(REPO_ROOT, sprint)
        if not passed:
            print(f"\nFATAL: Pre-flight failed. Install: {', '.join(missing)}")
            return 1
        print("\n  Pre-flight passed.")

    # -- STEP 6: SMART CHECK ---------------------------------------------------
    log_step("smart")
    if not should_run("smart"):
        print("  skipped")
    else:
        sep("AI CEREMONY: SMART Check")
        _ai(args.tool, "smart-check.md", log_file)
        sprint = sprint_lib.load(sprint_file)
        not_smart = _find_not_smart(sprint)
        if not_smart:
            print(f"\n  {len(not_smart)} stories scored < 3 — auto-splitting...")
            sep("AI CEREMONY: Story Split")
            _ai(args.tool, "story-split.md", log_file)
            sep("AI CEREMONY: SMART Check (post-split)")
            _ai(args.tool, "smart-check.md", log_file)
            sprint = sprint_lib.load(sprint_file)
            not_smart = _find_not_smart(sprint)

        if not_smart:
            # Split didn't fully resolve — eject still-failing stories back to
            # backlog and re-plan rather than fatal.  Half-finished work = 0 value.
            bad_ids = [s["id"] for s in not_smart]
            print(f"\n  {len(bad_ids)} stories still not SMART after split "
                  f"({', '.join(bad_ids)}) — ejecting to backlog and re-planning.")
            _eject_not_smart_stories(sprint_file, not_smart)
            _git_commit("smart-eject", [str(active_sprint), "prd/backlog.json"])
            sprint = sprint_lib.load(sprint_file)
            if not sprint.get("stories"):
                print("  Sprint is now empty — returning to plan.")
                _git_commit("smart-empty-replan", [str(active_sprint), "prd/manifest.json"])
                sep("AI CEREMONY: Sprint Planning (re-plan after SMART eject)")
                _ai(args.tool, "plan.md", log_file)
                sprint = sprint_lib.load(sprint_file)
                if not sprint.get("stories"):
                    print("\nFATAL: Re-plan produced an empty sprint. Backlog needs new stories.")
                    return 1
                _git_commit("plan-replan", [str(active_sprint), "prd/backlog.json", "prd/manifest.json"])
            else:
                print(f"  Continuing with {len(sprint.get('stories', []))} SMART-ready stories.")

        print(f"\n  SMART passed — {len(sprint.get('stories', []))} stories sprint-ready.")
        _git_commit("smart", [str(active_sprint), "prd/backlog.json"])

    # -- STEPS 7-9: EXECUTE + SMOKE + PROOF (gate retry loop) -----------------
    run_execute = should_run("execute")
    run_smoke   = should_run("smoke")
    run_proof   = should_run("proof")

    if not run_execute and not run_smoke and not run_proof:
        log_step("execute"); print("  skipped")
        log_step("smoke");   print("  skipped")
        log_step("proof");   print("  skipped")
    else:
        for retry in range(args.max_retries + 1):
            if retry > 0:
                print(f"\n{'─' * 20} RETRY {retry}/{args.max_retries} {'─' * 20}")

            # EXECUTE
            log_step("execute")
            if not run_execute:
                print("  skipped")
            else:
                sprint = sprint_lib.load(sprint_file)
                needing = sprint_lib.stories_needing_work(sprint)
                if not needing:
                    print(f"  All {len(sprint.get('stories', []))} stories passing — skipping execute.")
                else:
                    print(f"  {len(needing)}/{len(sprint.get('stories', []))} stories need work.")
                    sprint_lib.clear_failures(sprint_file)
                    ralph_exit = ai_lib.run_ralph(SCRIPT_DIR / "ralph.sh", sprint_file, args.tool, 10, log_file)
                    if ralph_exit != 0:
                        print(f"  WARNING: ralph.sh exited {ralph_exit}")
                    sprint = sprint_lib.load(sprint_file)
                    passing = sprint_lib.stories_passing(sprint)
                    print(f"\n  Passing: {len(passing)}/{len(sprint.get('stories', []))}")
                    _git_commit("execute", [str(active_sprint)])

            # SMOKE
            log_step("smoke")
            if not run_smoke:
                print("  skipped")
            else:
                sep()
                smoke_ok, smoke_fail = gates.smoke_test(REPO_ROOT)
                sprint_lib.write_failures(sprint_file, "_lastSmokeTestFailures", smoke_fail)
                if not smoke_ok:
                    count = sprint_lib.reset_passing_to_false(sprint_file, "[SMOKE-FAIL] see _lastSmokeTestFailures")
                    print(f"\n  SMOKE FAILED ({len(smoke_fail)} checks). Reset {count} stories.")
                    if retry < args.max_retries:
                        continue
                    print("\nFATAL: Smoke test failed after max retries.")
                    return 1
                print("\n  Smoke passed.")

            # PROOF
            log_step("proof")
            if not run_proof:
                print("  skipped")
            else:
                sep()
                sprint = sprint_lib.load(sprint_file)
                proof_ok, proof_fail = gates.proof_of_work(REPO_ROOT, sprint)
                sprint_lib.write_failures(sprint_file, "_lastProofOfWorkFailures", proof_fail)
                if not proof_ok:
                    count = sprint_lib.reset_passing_to_false(sprint_file, "[PROOF-FAIL] see _lastProofOfWorkFailures")
                    print(f"\n  PROOF FAILED ({len(proof_fail)} checks). Reset {count} stories.")
                    if retry < args.max_retries:
                        continue
                    print("\nFATAL: Proof of work failed after max retries.")
                    return 1
                print("\n  Proof passed.")

            break  # gates cleared

    # -- STEP 10: REVIEW -------------------------------------------------------
    log_step("review")
    if not should_run("review"):
        print("  skipped")
    else:
        sep("AI CEREMONY: Review")
        _ai(args.tool, "review.md", log_file)

        # The review ceremony's job is adversarial: it reopens stories that fail.
        # Any story that passes:true and was NOT reopened by the review is accepted.
        # ceremonies.py enforces this — we do not trust the AI to write reviewed:true.
        sprint = sprint_lib.load(sprint_file)
        newly_accepted = 0
        for s in sprint.get("stories", []):
            if s.get("passes", False) and not s.get("reviewed", False):
                s["reviewed"] = True
                newly_accepted += 1
        if newly_accepted:
            sprint_lib.save(sprint_file, sprint)
            print(f"  ceremonies.py set reviewed=True on {newly_accepted} passing stories not reopened by review.")

        sprint = sprint_lib.load(sprint_file)
        accepted   = [s for s in sprint.get("stories", []) if s.get("reviewed")]
        incomplete = [s for s in sprint.get("stories", []) if not s.get("reviewed") and not s.get("returnedToBacklog") and s.get("status") != "killed"]
        print(f"\n  Accepted: {len(accepted)}/{len(sprint.get('stories', []))}")
        if incomplete:
            print(f"  Incomplete → retro will return to backlog: {len(incomplete)}")
            for s in incomplete:
                print(f"    - {s['id']}: {s['title']}")
        _git_commit("review", [str(active_sprint)])

    # -- STEP 11: RETRO --------------------------------------------------------
    log_step("retro")
    if not should_run("retro"):
        print("  skipped")
    else:
        sep("AI CEREMONY: Retrospective")
        _ai(args.tool, "retro.md", log_file)
        _git_commit("retro", [
            str(active_sprint), "prd/backlog.json", "prd/manifest.json",
            "prd/",  # captures retro-patch-*.md new files
        ])

    # -- STEP 12: SYNC ---------------------------------------------------------
    log_step("sync")
    if not should_run("sync"):
        print("  skipped")
    else:
        sep("AI CEREMONY: State Sync")
        _ai(args.tool, "sync.md", log_file)
        print("\n  docs/state/architecture.md and docs/state/agent.md rewritten.")
        _git_commit("sync", [
            "docs/state/",
            "prd/backlog.json", "prd/epics.json", "prd/manifest.json", "prd/",
        ])

    # -- STEP 13: ADVANCE ------------------------------------------------------
    log_step("advance")
    if not should_run("advance"):
        print("  skipped")
    else:
        rc = advance_lib.run(REPO_ROOT, dry_run=args.dry_run)
        if rc != 0:
            return rc
        _git_commit("advance", ["prd/manifest.json", str(active_sprint) if active_sprint else "prd/"])

    print("\n" + "═" * 66)
    print(f"  CEREMONIES COMPLETE  —  {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print(f"  Log: {log_file}")
    print("═" * 66)
    return 0


if __name__ == "__main__":
    sys.exit(main())
