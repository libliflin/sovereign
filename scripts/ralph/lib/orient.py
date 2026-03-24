"""
orient.py — Platform state assessment engine.

Reads objective data (GGEs, themes, epics, backlog, velocity, retro patches),
computes KPIs against fixed thresholds, and returns ONE decision: what
the machine does next and why.

No AI. No options presented. One state, one action, one reason.

Check order (first failing KPI wins):
  1. GGEs (golden goose eggs) — unhealthy egg → Andon priority-0 story
  2. GGE count (3-5 required) → theme-review if out of range
  3. Priority-0 stories → plan immediately
  4. Retro debt → BLOCKED
  5. Sprint active → resume
  6. Epic coverage → epic-breakdown
  7. Backlog depth → backlog-groom or plan
"""
from __future__ import annotations

import json
import subprocess
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
STORY_MAX_POINTS = 8          # stories above this cannot enter planning
GGE_MIN = 3                   # minimum golden goose eggs
GGE_MAX = 5                   # maximum golden goose eggs


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


def _check_gge_indicator(repo_root: Path, indicator: dict, all_stories: list[dict]) -> bool:
    """Return True if the GGE indicator is healthy."""
    kind = indicator.get("type")
    if kind == "file_exists":
        return (repo_root / indicator["path"]).exists()
    if kind == "files_exist":
        return all((repo_root / p).exists() for p in indicator.get("paths", []))
    if kind == "story_complete":
        sid = indicator.get("storyId")
        story = next((s for s in all_stories if s["id"] == sid), None)
        return story is not None and story.get("passes", False)
    if kind == "gate_passing":
        cmd = indicator.get("command", "")
        result = subprocess.run(cmd, shell=True, cwd=repo_root, capture_output=True)
        return result.returncode == 0
    return True  # unknown indicator type → assume healthy


def _retro_patch_ages(repo_root: Path, velocity: list[dict]) -> list[int]:
    """
    Return ages (in sprints) of retro patches that appear unresolved.
    A patch is 'unresolved' if its file still exists and the phase it covers
    is not in the velocity history with a reviewPassRate >= 50.
    Simple heuristic: any retro-patch-phase<N>.md that exists and phase N
    is in the last RETRO_DEBT_MAX_SPRINTS+1 completed phases.
    """
    patches = list((repo_root / "prd").glob("retro-patch-increment*.md"))
    completed_increments = {str(v.get("increment", v.get("phase", ""))) for v in velocity}
    ages = []
    for p in patches:
        # Extract increment ID from filename: retro-patch-increment6.md → "6"
        stem = p.stem  # e.g. retro-patch-increment6
        try:
            inc_str = stem.split("increment")[-1]
            if inc_str in completed_increments:
                # Find position from end of velocity list
                inc_positions = [
                    i for i, v in enumerate(velocity)
                    if str(v.get("increment", v.get("phase", ""))) == inc_str
                ]
                if inc_positions:
                    age = len(velocity) - inc_positions[-1]
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
    current_phase = manifest.get("currentIncrement")
    phases = manifest.get("increments", [])

    kpis: list[KPI] = []
    gge_data = _load_json(prd / "gge.json") or {}
    eggs = gge_data.get("eggs", [])

    # ── KPI 1: EMPTY check ──────────────────────────────────────────────────
    if not themes and not epics and not all_stories:
        kpis.append(KPI("Platform state", "empty", "FAIL", "no themes, epics, or stories"))
        return Assessment(
            state=PlatformState.EMPTY,
            action=NextAction.THEME_REVIEW,
            reason="Platform has no themes yet. Run theme-review to establish strategic direction.",
            kpis=kpis,
        )

    # ── KPI 2: Golden Goose Eggs ────────────────────────────────────────────
    # GGE count gate: must have 3-5 eggs or theme-review is required
    egg_count = len(eggs)
    if egg_count < GGE_MIN or egg_count > GGE_MAX:
        kpis.append(KPI(
            "GGE count",
            f"{egg_count} eggs",
            "FAIL",
            f"must have {GGE_MIN}–{GGE_MAX} eggs (prd/gge.json)"
        ))
        return Assessment(
            state=PlatformState.EMPTY,
            action=NextAction.THEME_REVIEW,
            reason=(
                f"Golden Goose Eggs count is {egg_count}, must be {GGE_MIN}–{GGE_MAX}. "
                "Run theme-review to define or trim the eggs."
            ),
            kpis=kpis,
        )

    # GGE health: check each egg's indicator
    broken_eggs = [e for e in eggs if not _check_gge_indicator(repo_root, e.get("indicator", {}), all_stories)]
    if broken_eggs:
        kpis.append(KPI(
            "GGEs healthy",
            f"{len(broken_eggs)}/{egg_count} broken",
            "FAIL",
            f"{', '.join(e['id'] for e in broken_eggs)} — Andon: priority-0 story needed"
        ))
        # Andon: create a priority-0 backlog story for the first broken egg
        # (ceremonies.py will then pick it up immediately in the p0 check)
        first_broken = broken_eggs[0]
        backlog_path = prd / "backlog.json"
        if backlog_path.exists():
            with open(backlog_path) as f:
                backlog = json.load(f)
            andon_id = f"GGE-{first_broken['id']}-andon"
            existing_ids = {s["id"] for s in backlog.get("stories", [])}
            if andon_id not in existing_ids:
                backlog.setdefault("stories", []).insert(0, {
                    "id": andon_id,
                    "title": f"ANDON: Restore broken GGE — {first_broken['title']}",
                    "description": (
                        f"Golden Goose Egg {first_broken['id']} indicator is failing. "
                        f"Indicator type: {first_broken.get('indicator', {}).get('type')}. "
                        f"Restore it immediately. Rationale: {first_broken.get('rationale', '')}"
                    ),
                    "acceptanceCriteria": [f"GGE {first_broken['id']} indicator passes in orient"],
                    "priority": 0,
                    "points": 2,
                    "passes": False,
                    "reviewed": False,
                    "epicId": "E1",
                    "themeId": first_broken.get("themeId", "T3"),
                    "branchName": f"fix/gge-{first_broken['id'].lower()}-andon",
                    "dependencies": [],
                    "attempts": 0,
                })
                with open(backlog_path, "w") as f:
                    json.dump(backlog, f, indent=2)
                print(f"  ⚑  ANDON: created priority-0 story '{andon_id}' for broken GGE {first_broken['id']}")
    else:
        kpis.append(KPI(
            "GGEs healthy",
            f"{egg_count}/{egg_count} passing",
            "OK",
            " | ".join(e["id"] for e in eggs)
        ))

    # ── KPI 3: Priority-0 stories ───────────────────────────────────────────
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

    # ── KPI 4: Retro debt ───────────────────────────────────────────────────
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

    # ── KPI 5: Sprint active? ───────────────────────────────────────────────
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

    # ── KPI 6: Epic coverage ────────────────────────────────────────────────
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

    # ── KPI 7: Backlog depth ────────────────────────────────────────────────
    def is_sprint_ready(s: dict) -> bool:
        if s.get("passes", False) or s.get("reviewed", False):
            return False
        if s.get("status") == "killed":
            return False
        if isinstance(s.get("points"), int) and s["points"] > STORY_MAX_POINTS:
            return False  # oversized — must be split before it can be planned
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

    # ── KPI 8: SMART readiness ──────────────────────────────────────────────
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

    # ── KPI 9: Increment pace ───────────────────────────────────────────────
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
