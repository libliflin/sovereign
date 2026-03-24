"""
orient.py — Platform state assessment engine.

Reads objective data (themes, epics, backlog, velocity, retro patches),
computes KPIs against fixed thresholds, and returns ONE decision: what
the machine does next and why.

No AI. No options presented. One state, one action, one reason.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# KPI thresholds — not configurable, not negotiable
# ---------------------------------------------------------------------------
BACKLOG_DEPTH_MIN = 2.0       # sprints of ready work required before planning
EPIC_COVERAGE_MIN = 1         # every epic must have at least this many stories
RETRO_DEBT_MAX_SPRINTS = 2    # unresolved retro patches older than this → BLOCKED
INCREMENT_PACE_MIN = 0.70     # 70% of target velocity required
SMART_READINESS_MIN = 0.80    # 80% of backlog stories must be SMART-scored
DEFAULT_SPRINT_SIZE = 4       # stories per sprint when no velocity history exists


# ---------------------------------------------------------------------------
# State + Action enums
# ---------------------------------------------------------------------------
class PlatformState(Enum):
    EMPTY         = "empty"          # no themes or epics yet
    NEEDS_EPICS   = "needs_epics"    # epics exist but have no stories
    THIN_BACKLOG  = "thin_backlog"   # depth < BACKLOG_DEPTH_MIN
    RETRO_DEBT    = "retro_debt"     # unresolved patterns too old → blocked
    SPRINT_ACTIVE = "sprint_active"  # sprint file exists with incomplete stories
    SPRINT_READY  = "sprint_ready"   # all KPIs green, ready to plan + execute
    COMPLETE      = "complete"       # all phases done


class NextAction(Enum):
    THEME_REVIEW    = "theme-review"
    EPIC_BREAKDOWN  = "epic-breakdown"
    BACKLOG_GROOM   = "backlog-groom"
    PLAN            = "plan"
    RESUME_SPRINT   = "execute"      # maps to --start-at execute
    BLOCKED         = "blocked"
    DONE            = "done"


# ---------------------------------------------------------------------------
# KPI result
# ---------------------------------------------------------------------------
@dataclass
class KPI:
    name: str
    value: str
    status: str          # OK | WARN | FAIL
    detail: str = ""


# ---------------------------------------------------------------------------
# Assessment result
# ---------------------------------------------------------------------------
@dataclass
class Assessment:
    state: PlatformState
    action: NextAction
    reason: str
    kpis: list[KPI] = field(default_factory=list)
    blocked_reason: str = ""
    resume_step: Optional[str] = None  # for SPRINT_ACTIVE: which step to resume at

    def start_at(self) -> str:
        """Return the --start-at value ceremonies.py should use."""
        if self.resume_step:
            return self.resume_step
        return self.action.value

    def is_blocked(self) -> bool:
        return self.action == NextAction.BLOCKED

    def print_report(self) -> None:
        width = 66
        bar = "═" * width
        thin = "─" * 50
        print(f"\n{bar}")
        print(f"  ORIENT  —  {datetime.now().strftime('%Y-%m-%d %H:%M')}")
        print(bar)
        print()
        print("  KPIs")
        print(f"  {thin}")
        for kpi in self.kpis:
            flag = {"OK": "✓", "WARN": "▲", "FAIL": "✗"}[kpi.status]
            print(f"  {flag}  {kpi.name:<22} {kpi.value:<14} {kpi.detail}")
        print()
        print(f"  {thin}")
        print(f"  State   : {self.state.value}")
        if self.is_blocked():
            print(f"  Action  : BLOCKED")
            print(f"  Reason  : {self.blocked_reason}")
        else:
            print(f"  Action  : {self.action.value}")
            print(f"  Reason  : {self.reason}")
        print(bar)
        print()


# ---------------------------------------------------------------------------
# Data loading helpers
# ---------------------------------------------------------------------------
def _load_json(path: Path) -> dict | list | None:
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def _retro_patch_ages(repo_root: Path, velocity: list[dict]) -> list[int]:
    """
    Return ages (in sprints) of retro patches that appear unresolved.
    A patch is 'unresolved' if its file still exists and the phase it covers
    is not in the velocity history with a reviewPassRate >= 50.
    Simple heuristic: any retro-patch-phase<N>.md that exists and phase N
    is in the last RETRO_DEBT_MAX_SPRINTS+1 completed phases.
    """
    patches = list((repo_root / "prd").glob("retro-patch-phase*.md"))
    completed_phases = {str(v["phase"]) for v in velocity}
    ages = []
    for p in patches:
        # Extract phase number from filename
        stem = p.stem  # e.g. retro-patch-phase6
        try:
            phase_str = stem.split("phase")[-1]
            if phase_str in completed_phases:
                # Find position from end of velocity list
                phase_positions = [i for i, v in enumerate(velocity) if str(v["phase"]) == phase_str]
                if phase_positions:
                    age = len(velocity) - phase_positions[-1]
                    ages.append(age)
        except (ValueError, IndexError):
            pass
    return ages


# ---------------------------------------------------------------------------
# Core assessment function
# ---------------------------------------------------------------------------
def assess(repo_root: Path) -> Assessment:
    prd = repo_root / "prd"
    manifest = _load_json(prd / "manifest.json") or {}
    themes_data = _load_json(prd / "themes.json") or {}
    epics_data = _load_json(prd / "epics.json") or {}
    backlog_data = _load_json(prd / "backlog.json") or {}

    themes = themes_data.get("themes", [])
    epics = epics_data.get("epics", [])
    all_stories = backlog_data.get("stories", [])
    velocity = manifest.get("velocity", [])
    active_sprint_file = manifest.get("activeSprint")
    current_phase = manifest.get("currentPhase")
    phases = manifest.get("phases", [])

    kpis: list[KPI] = []

    # ── KPI 1: EMPTY check ──────────────────────────────────────────────────
    if not themes and not epics and not all_stories:
        kpis.append(KPI("Platform state", "empty", "FAIL", "no themes, epics, or stories"))
        return Assessment(
            state=PlatformState.EMPTY,
            action=NextAction.THEME_REVIEW,
            reason="Platform has no themes yet. Run theme-review to establish strategic direction.",
            kpis=kpis,
        )

    # ── KPI 2: Priority-0 stories (outranks everything including retro debt) ─
    urgent = [
        s for s in all_stories
        if s.get("priority") == 0
        and not s.get("passes", False)
        and not s.get("reviewed", False)
        and s.get("status") != "killed"
    ]
    if urgent:
        kpis.append(KPI(
            "Urgent (p0)",
            f"{len(urgent)} stories",
            "FAIL",
            f"{', '.join(s['id'] for s in urgent)} — pull before anything else"
        ))
        return Assessment(
            state=PlatformState.SPRINT_READY,
            action=NextAction.PLAN,
            reason=(
                f"{len(urgent)} priority-0 story/stories must be pulled into the next sprint immediately: "
                f"{', '.join(s['id'] + ' (' + s['title'] + ')' for s in urgent)}. "
                "These unblock the delivery system itself."
            ),
            kpis=kpis,
        )

    # ── KPI 3: Retro debt ───────────────────────────────────────────────────
    patch_ages = _retro_patch_ages(repo_root, velocity)
    old_patches = [a for a in patch_ages if a > RETRO_DEBT_MAX_SPRINTS]
    retro_status = "FAIL" if old_patches else "OK"
    retro_detail = f"{len(old_patches)} patch(es) unresolved > {RETRO_DEBT_MAX_SPRINTS} sprints" if old_patches else "all resolved"
    kpis.append(KPI("Retro debt", f"{len(old_patches)} old", retro_status, retro_detail))

    if old_patches:
        return Assessment(
            state=PlatformState.RETRO_DEBT,
            action=NextAction.BLOCKED,
            reason="",
            kpis=kpis,
            blocked_reason=(
                f"{len(old_patches)} retro patch(es) unresolved for > {RETRO_DEBT_MAX_SPRINTS} sprints. "
                "Apply or explicitly dismiss them in CLAUDE.md before continuing."
            ),
        )

    # ── KPI 3: Sprint active? ───────────────────────────────────────────────
    active_sprint = None
    if active_sprint_file:
        sprint_path = repo_root / active_sprint_file
        active_sprint = _load_json(sprint_path) if sprint_path.exists() else None

    if active_sprint:
        stories = active_sprint.get("stories", [])
        limbo = [
            s for s in stories
            if not s.get("reviewed", False)
            and not s.get("returnedToBacklog", False)
            and s.get("status") != "killed"
        ]
        if limbo:
            passing = [s for s in stories if s.get("passes", False)]
            has_passing = len(passing) > 0
            kpis.append(KPI(
                "Sprint active",
                f"{len(limbo)} stories left",
                "WARN",
                f"{len(passing)} passing, {len(limbo)} incomplete"
            ))
            resume = "review" if has_passing else "execute"
            return Assessment(
                state=PlatformState.SPRINT_ACTIVE,
                action=NextAction.RESUME_SPRINT,
                reason=(
                    f"Sprint '{active_sprint_file}' has {len(limbo)} stories not yet resolved. "
                    f"Resuming at {resume}."
                ),
                kpis=kpis,
                resume_step=resume,
            )

    # ── KPI 4: Epic coverage ────────────────────────────────────────────────
    story_epic_ids = {s.get("epicId") for s in all_stories if s.get("epicId")}
    empty_epics = [e for e in epics if e.get("id") not in story_epic_ids]
    epic_status = "FAIL" if empty_epics else "OK"
    epic_detail = (
        f"{', '.join(e['id'] for e in empty_epics[:3])}{'…' if len(empty_epics) > 3 else ''} need stories"
        if empty_epics else f"all {len(epics)} epics have stories"
    )
    kpis.append(KPI("Epic coverage", f"{len(empty_epics)} empty", epic_status, epic_detail))

    if empty_epics:
        return Assessment(
            state=PlatformState.NEEDS_EPICS,
            action=NextAction.EPIC_BREAKDOWN,
            reason=(
                f"{len(empty_epics)} epic(s) have no stories: "
                f"{', '.join(e['id'] for e in empty_epics)}. "
                "Run epic-breakdown to generate sprint-sized stories."
            ),
            kpis=kpis,
        )

    # ── KPI 5: Backlog depth ────────────────────────────────────────────────
    def is_sprint_ready(s: dict) -> bool:
        if s.get("passes", False) or s.get("reviewed", False):
            return False
        if s.get("status") == "killed":
            return False
        sm = s.get("smart", {})
        if not sm:
            return False
        scores = [sm.get(d, 0) for d in ("specific", "measurable", "achievable", "relevant", "timeBound")]
        return all(v > 0 for v in scores) and min(scores) >= 3

    ready_stories = [s for s in all_stories if is_sprint_ready(s)]
    avg_sprint_size = (
        sum(v.get("storiesAccepted", DEFAULT_SPRINT_SIZE) for v in velocity[-3:]) / min(len(velocity), 3)
        if velocity else DEFAULT_SPRINT_SIZE
    )
    depth = len(ready_stories) / avg_sprint_size if avg_sprint_size > 0 else 0.0
    depth_status = "OK" if depth >= BACKLOG_DEPTH_MIN else ("WARN" if depth >= 1.0 else "FAIL")
    kpis.append(KPI(
        "Backlog depth",
        f"{depth:.1f} sprints",
        depth_status,
        f"{len(ready_stories)} ready stories / {avg_sprint_size:.0f} avg sprint size"
    ))

    # ── KPI 6: SMART readiness ──────────────────────────────────────────────
    open_stories = [
        s for s in all_stories
        if not s.get("passes", False)
        and not s.get("reviewed", False)
        and s.get("status") != "killed"
    ]
    smart_scored = [s for s in open_stories if s.get("smart") and any(s["smart"].get(d, 0) > 0 for d in ("specific", "measurable", "achievable", "relevant", "timeBound"))]
    smart_ratio = len(smart_scored) / len(open_stories) if open_stories else 1.0
    smart_status = "OK" if smart_ratio >= SMART_READINESS_MIN else "WARN"
    kpis.append(KPI(
        "SMART readiness",
        f"{len(smart_scored)}/{len(open_stories)}",
        smart_status,
        f"{smart_ratio * 100:.0f}% scored (threshold: {SMART_READINESS_MIN * 100:.0f}%)"
    ))

    # ── KPI 7: Increment pace ───────────────────────────────────────────────
    if velocity and len(velocity) >= 2:
        recent = velocity[-3:]
        avg_pts = sum(v.get("pointsCompleted", 0) for v in recent) / len(recent)
        remaining_phases = len([p for p in phases if p.get("status") not in ("complete",)])
        target_pts = avg_pts * remaining_phases if remaining_phases > 0 else avg_pts
        pace = avg_pts / (target_pts / remaining_phases) if remaining_phases > 0 else 1.0
        pace_status = "OK" if pace >= INCREMENT_PACE_MIN else "WARN"
        kpis.append(KPI(
            "Increment pace",
            f"{pace * 100:.0f}%",
            pace_status,
            f"avg {avg_pts:.1f} pts/sprint, {remaining_phases} phases remain"
        ))
    else:
        kpis.append(KPI("Increment pace", "no data", "OK", "insufficient velocity history"))

    # ── Decision ────────────────────────────────────────────────────────────
    # All checks passed above — determine whether to groom or plan
    if depth < BACKLOG_DEPTH_MIN:
        return Assessment(
            state=PlatformState.THIN_BACKLOG,
            action=NextAction.BACKLOG_GROOM,
            reason=(
                f"Backlog depth {depth:.1f} is below {BACKLOG_DEPTH_MIN} sprint threshold. "
                f"Only {len(ready_stories)} sprint-ready stories available. "
                "Run backlog-groom to score and refine stories before planning."
            ),
            kpis=kpis,
        )

    # Check if all phases are complete
    remaining = [p for p in phases if p.get("status") not in ("complete",)]
    if not remaining:
        kpis.append(KPI("Platform", "complete", "OK", "all phases delivered"))
        return Assessment(
            state=PlatformState.COMPLETE,
            action=NextAction.DONE,
            reason="All phases complete. Platform delivered.",
            kpis=kpis,
        )

    return Assessment(
        state=PlatformState.SPRINT_READY,
        action=NextAction.PLAN,
        reason=(
            f"All KPIs green. {len(ready_stories)} sprint-ready stories available "
            f"({depth:.1f} sprints deep). Ready to plan next sprint."
        ),
        kpis=kpis,
    )
