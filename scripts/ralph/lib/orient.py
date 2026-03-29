"""
orient.py — Platform state assessment engine.

Reads objective data (GGEs, themes, epics, backlog, velocity, retro patches),
computes KPIs against fixed thresholds, and returns ONE decision: what
the machine does next and why.

No AI. No options presented. One state, one action, one reason.

OODA loop: Observe (read sprint files, GGEs, agent state) →
           Orient (KPIs + Shi + Niti) →
           Decide (single NextAction) →
           Act (ceremonies execute it)

Check order (first failing KPI wins):
  1. GGEs (golden goose eggs) — unhealthy egg → Andon priority-0 story
  2. GGE count (3-5 required) → constitution-review if out of range
  3. Priority-0 stories → plan immediately
  4. Retro debt → BLOCKED
  5. Sprint active → resume
  6. Epic coverage → epic-breakdown
  7. Backlog depth → backlog-groom or plan

Field reading (always computed, informs but does not block):
  Shi (勢)  — propensity: per-theme flow rate from completed sprint files
  Niti (नीति) — right questions: sprint alignment, stuck stories, next increment fit
  Agent state — synthesized context from last sync (docs/state/agent.md)
"""
from __future__ import annotations

import json
import subprocess
from collections import defaultdict
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
    KAIZEN        = "kaizen"         # all planned increments delivered — continuous improvement


class NextAction(Enum):
    THEME_REVIEW    = "constitution-review"
    EPIC_BREAKDOWN  = "epic-breakdown"
    BACKLOG_GROOM   = "backlog-groom"
    PLAN            = "plan"
    RESUME_SPRINT   = "execute"      # maps to --start-at execute
    BLOCKED         = "blocked"
    # NOTE: DONE is intentionally absent. The machine never stops improving.
    # When all planned work is delivered, it returns to constitution-review to ask:
    # what drifted? what deprecated? what hardened? what refined?


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
    shi: list[dict] = field(default_factory=list)       # propensity per theme
    niti: list[str] = field(default_factory=list)       # right questions
    agent_context: str = ""                             # from docs/state/agent.md

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

        # ── Field reading ────────────────────────────────────────────────────
        if self.shi:
            print(f"  {thin}")
            print("  Shi (勢) — propensity")
            icon = {"flowing": "⟶", "neutral": "〜", "blocked": "✗"}
            for s in self.shi:
                print(f"    {icon.get(s['momentum'], '?')}  {s['themeId']:<6} {s['themeName'][:28]:<30} {s['detail']}")
            print()

        if self.niti:
            print(f"  {thin}")
            print("  Niti (नीति) — right questions")
            for q in self.niti:
                # Wrap long lines
                words = q.split()
                line, lines = "", []
                for w in words:
                    if len(line) + len(w) + 1 > 58:
                        lines.append(line)
                        line = w
                    else:
                        line = (line + " " + w).strip()
                if line:
                    lines.append(line)
                print(f"    ?  {lines[0]}")
                for extra in lines[1:]:
                    print(f"       {extra}")
            print()

        if self.agent_context:
            print(f"  {thin}")
            print("  Prior synthesis (last sync)")
            for line in self.agent_context.splitlines()[:6]:
                if line.strip():
                    print(f"    {line.strip()[:62]}")
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


def _compute_velocity(repo_root: Path, increments: list[dict]) -> list[dict]:
    """
    Derive velocity from completed sprint files — the source of truth.
    No historical data is stored in the manifest; this function reads it
    fresh each run from the sprint files themselves.
    """
    velocity = []
    for inc in increments:
        if inc.get("status") != "complete":
            continue
        sprint_file = repo_root / inc.get("file", "")
        sprint = _load_json(sprint_file) if sprint_file.exists() else None
        if not sprint:
            continue
        stories = sprint.get("stories", [])
        accepted = [s for s in stories if s.get("passes", False) and s.get("reviewed", False)]
        pts = sum(s.get("points", 0) for s in accepted)
        total = len(stories)
        rate = (len(accepted) / total * 100) if total > 0 else 0.0
        velocity.append({
            "increment": inc["id"],
            "pointsCompleted": pts,
            "storiesAccepted": len(accepted),
            "reviewPassRate": rate,
        })
    return velocity


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


def _compute_velocity(repo_root: Path, increments: list[dict]) -> list[dict]:
    """
    Compute velocity on the fly from completed sprint files.
    The manifest is the authoritative list of increments; the sprint files
    are the authoritative source of what was accepted. No historical data
    is stored in the manifest — this function derives it fresh each run.
    """
    velocity = []
    for inc in increments:
        if inc.get("status") != "complete":
            continue
        sprint_file = repo_root / inc.get("file", "")
        sprint = _load_json(sprint_file) if sprint_file.exists() else None
        if not sprint:
            continue
        stories = sprint.get("stories", [])
        accepted = [s for s in stories if s.get("passes", False) and s.get("reviewed", False)]
        points_done = sum(s.get("points", 0) for s in accepted)
        total = len(stories)
        review_pass_rate = (len(accepted) / total * 100) if total > 0 else 0.0
        velocity.append({
            "increment": inc["id"],
            "pointsCompleted": points_done,
            "storiesAccepted": len(accepted),
            "reviewPassRate": review_pass_rate,
        })
    return velocity


def _retro_patch_ages(repo_root: Path, velocity: list[dict]) -> list[int]:
    """
    Return ages (in sprints) of retro patches that appear unresolved.
    A patch file retro-patch-increment<N>.md is 'unresolved' if it still
    exists on disk. Age = number of completed increments since increment N.
    """
    patches = list((repo_root / "prd").glob("retro-patch-increment*.md"))
    completed_ids = [str(v.get("increment", "")) for v in velocity]
    ages = []
    for p in patches:
        stem = p.stem  # e.g. retro-patch-increment6
        try:
            inc_str = stem.split("increment")[-1]
            if inc_str in completed_ids:
                idx = completed_ids.index(inc_str)
                age = len(completed_ids) - idx
                ages.append(age)
        except (ValueError, IndexError):
            pass
    return ages


# ---------------------------------------------------------------------------
# Shi (勢) — propensity / momentum
# ---------------------------------------------------------------------------
def _compute_shi(
    repo_root: Path,
    increments: list[dict],
    themes: list[dict],
    epics: list[dict],
    all_stories: list[dict],
) -> list[dict]:
    """
    Measure the natural propensity of each theme by reading completed sprint
    files. Flow rate = accepted_points / total_points_attempted. This is not
    a judgment — it is a reading of the configuration of forces. Work with
    the grain, not against it.
    """
    theme_names = {t["id"]: t.get("title", t.get("name", t["id"])) for t in themes}
    epic_theme = {e["id"]: e.get("themeId", "") for e in epics}
    story_theme = {s["id"]: s.get("themeId") or epic_theme.get(s.get("epicId", ""), "") for s in all_stories}

    accepted: defaultdict[str, int] = defaultdict(int)
    returned: defaultdict[str, int] = defaultdict(int)
    total: defaultdict[str, int] = defaultdict(int)

    for inc in increments:
        if inc.get("status") != "complete":
            continue
        sprint_file = repo_root / inc.get("file", "")
        sprint = _load_json(sprint_file) if sprint_file.exists() else None
        if not sprint:
            continue
        for s in sprint.get("stories", []):
            tid = s.get("themeId") or epic_theme.get(s.get("epicId", ""), "") or story_theme.get(s["id"], "")
            if not tid:
                continue
            pts = s.get("points", 1)
            total[tid] += pts
            if s.get("passes", False) and s.get("reviewed", False):
                accepted[tid] += pts
            elif s.get("returnedToBacklog", False):
                returned[tid] += pts

    results = []
    for tid in set(list(accepted.keys()) + list(returned.keys()) + list(total.keys())):
        t = total[tid]
        if t == 0:
            continue
        a, r = accepted[tid], returned[tid]
        flow = a / t
        momentum = "flowing" if flow >= 0.70 else ("neutral" if flow >= 0.40 else "blocked")
        results.append({
            "themeId": tid,
            "themeName": theme_names.get(tid, tid),
            "momentum": momentum,
            "flowRate": flow,
            "acceptedPts": a,
            "returnedPts": r,
            "detail": f"{flow*100:.0f}% flow — {a}pts accepted, {r}pts returned",
        })

    order = {"blocked": 0, "neutral": 1, "flowing": 2}
    results.sort(key=lambda x: order[x["momentum"]])
    return results


# ---------------------------------------------------------------------------
# Niti (नीति) — right questions / prudent conduct
# ---------------------------------------------------------------------------
def _check_niti(
    manifest: dict,
    themes: list[dict],
    epics: list[dict],
    all_stories: list[dict],
    shi: list[dict],
    active_sprint: Optional[dict],
) -> list[str]:
    """
    Niti does not prescribe. It surfaces the questions worth asking before
    committing to a course of action. Is this the right work? Is the framing
    correct? Are we solving the actual problem?
    """
    questions: list[str] = []
    epic_map = {e["id"]: e for e in epics}
    theme_map = {t["id"]: t for t in themes}

    # Q1: Sprint-to-increment alignment
    current_inc_id = manifest.get("currentIncrement")
    increments = manifest.get("increments", [])
    current_inc = next((i for i in increments if str(i["id"]) == str(current_inc_id)), None)
    if current_inc and active_sprint:
        sprint_stories = active_sprint.get("stories", [])
        sprint_themes = {
            s.get("themeId") or epic_map.get(s.get("epicId", ""), {}).get("themeId", "")
            for s in sprint_stories
        } - {""}
        goal = current_inc.get("themeGoal", "")
        if sprint_themes and goal:
            theme_names = [theme_map.get(tid, {}).get("title", tid) for tid in sorted(sprint_themes)]
            questions.append(
                f"Sprint themes ({', '.join(theme_names)}) — increment goal: \"{goal[:55]}\". Aligned?"
            )

    # Q2: Blocked themes — is the friction understood?
    for b in [s for s in shi if s["momentum"] == "blocked"]:
        questions.append(
            f"Theme {b['themeId']} is blocked ({b['detail']}). Root cause understood?"
        )

    # Q3: Stories stuck across multiple attempts — is the problem correctly framed?
    stuck = [s for s in all_stories if s.get("attempts", 0) >= 3 and not s.get("passes", False)]
    for s in stuck[:3]:
        epic_title = epic_map.get(s.get("epicId", ""), {}).get("title", "")
        questions.append(
            f"Story {s['id']} ({s.get('title','')[:35]}) has {s['attempts']} failed attempts "
            f"— is the problem correctly framed, or does the epic need redefining?"
        )

    # Q4: Next pending increment — does it head toward flowing or blocked themes?
    next_pending = next((i for i in increments if i.get("status") == "pending"), None)
    if next_pending:
        flowing = {s["themeId"] for s in shi if s["momentum"] == "flowing"}
        blocked = {s["themeId"] for s in shi if s["momentum"] == "blocked"}
        goal = next_pending.get("themeGoal", "")
        if goal:
            questions.append(
                f"Next increment \"{next_pending.get('name', next_pending['id'])}\": "
                f"\"{goal[:50]}\" — "
                + (f"flowing themes available: {', '.join(sorted(flowing))}." if flowing else "no flowing themes yet.")
            )

    # Q5: Are we building in the right order? (dependency check across themes)
    # If a blocked theme is a dependency of a flowing theme's stories, flag it
    theme_dep_issues = []
    for s in all_stories:
        if s.get("passes", False):
            continue
        for dep_id in s.get("dependencies", []):
            dep = next((x for x in all_stories if x["id"] == dep_id), None)
            if dep and not dep.get("passes", False):
                dep_tid = dep.get("themeId", "")
                s_tid = s.get("themeId", "")
                if dep_tid != s_tid:
                    dep_shi = next((x for x in shi if x["themeId"] == dep_tid), None)
                    if dep_shi and dep_shi["momentum"] == "blocked":
                        theme_dep_issues.append(
                            f"Story {s['id']} (theme {s_tid}) blocked by {dep_id} (theme {dep_tid}, {dep_shi['momentum']})"
                        )
    for issue in theme_dep_issues[:2]:
        questions.append(issue)

    return questions if questions else ["No alignment concerns detected."]


# ---------------------------------------------------------------------------
# Agent state — synthesized context from last sync
# ---------------------------------------------------------------------------
def _read_agent_state(repo_root: Path) -> str:
    """
    Read docs/state/agent.md — written by the sync ceremony after each sprint.
    This closes the OODA loop: the machine's synthesized understanding of where
    it is feeds directly into the next orientation.
    """
    agent_md = repo_root / "docs" / "state" / "agent.md"
    if not agent_md.exists():
        return ""
    text = agent_md.read_text()
    lines = text.splitlines()
    # Extract the first substantive section (skip title/blank lines)
    summary: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("# "):
            if summary:
                break  # end of first section
            continue
        summary.append(stripped)
        if len(summary) >= 8:
            break
    return "\n".join(summary)


# ---------------------------------------------------------------------------
# Core assessment function
# ---------------------------------------------------------------------------
def assess(repo_root: Path) -> Assessment:
    prd = repo_root / "prd"
    manifest = _load_json(prd / "manifest.json") or {}
    constitution = _load_json(prd / "constitution.json") or {}
    epics_data = _load_json(prd / "epics.json") or {}
    backlog_data = _load_json(prd / "backlog.json") or {}

    themes = constitution.get("themes", [])
    epics = epics_data.get("epics", [])
    all_stories = backlog_data.get("stories", [])
    active_sprint_file = manifest.get("activeSprint")
    current_phase = manifest.get("currentIncrement")
    phases = manifest.get("increments", [])
    velocity = _compute_velocity(repo_root, phases)

    # ── OODA: Observe — gather all field readings before any KPI logic ───────
    velocity = _compute_velocity(repo_root, phases)
    active_sprint_data = _load_json(repo_root / active_sprint_file) if active_sprint_file else None
    shi = _compute_shi(repo_root, phases, themes, epics, all_stories)
    niti = _check_niti(manifest, themes, epics, all_stories, shi, active_sprint_data)
    agent_context = _read_agent_state(repo_root)

    kpis: list[KPI] = []
    eggs = constitution.get("gates", [])

    # ── KPI 1: EMPTY check ──────────────────────────────────────────────────
    if not themes and not epics and not all_stories:
        kpis.append(KPI("Platform state", "empty", "FAIL", "no themes, epics, or stories"))
        return Assessment(
            state=PlatformState.EMPTY,
            action=NextAction.THEME_REVIEW,
            reason="Platform has no themes yet. Run constitution-review to establish strategic direction.",
            kpis=kpis,
            shi=shi,
            niti=niti,
            agent_context=agent_context,
        )

    # ── KPI 2: Golden Goose Eggs ────────────────────────────────────────────
    # GGE count gate: must have 3-5 eggs or constitution-review is required
    egg_count = len(eggs)
    if egg_count < GGE_MIN or egg_count > GGE_MAX:
        kpis.append(KPI(
            "GGE count",
            f"{egg_count} eggs",
            "FAIL",
            f"must have {GGE_MIN}–{GGE_MAX} gates (prd/constitution.json)"
        ))
        return Assessment(
            state=PlatformState.EMPTY,
            action=NextAction.THEME_REVIEW,
            reason=(
                f"Constitutional gates count is {egg_count}, must be {GGE_MIN}–{GGE_MAX}. "
                "Run constitution-review to define or trim the gates."
            ),
            kpis=kpis,
            shi=shi,
            niti=niti,
            agent_context=agent_context,
        )

    # GGE health: check each egg's indicator
    broken_eggs = [e for e in eggs if not _check_gge_indicator(repo_root, e.get("indicator", {}), all_stories)]
    if broken_eggs:
        kpis.append(KPI(
            "GGEs healthy",
            f"{len(broken_eggs)}/{egg_count} broken",
            "FAIL",
            f"{', '.join(e['id'] for e in broken_eggs)} — Andon cord pulled"
        ))
        # Andon cord: create a priority-0 backlog story for the first broken egg,
        # then return PLAN immediately. A broken GGE stops the line — no other
        # KPI is allowed to override it, including "platform complete".
        first_broken = broken_eggs[0]
        backlog_path = prd / "backlog.json"
        andon_story = None
        if backlog_path.exists():
            with open(backlog_path) as f:
                backlog = json.load(f)
            andon_id = f"GGE-{first_broken['id']}-andon"
            existing = next((s for s in backlog.get("stories", []) if s["id"] == andon_id), None)

            # If the andon was killed but GGE is still broken, revive it.
            # Only a passing GGE indicator justifies closing an andon story.
            if existing and existing.get("status") == "killed":
                existing.pop("status", None)
                existing["passes"] = False
                existing["reviewed"] = False
                with open(backlog_path, "w") as f:
                    json.dump(backlog, f, indent=2)
                all_stories_entry = next((s for s in all_stories if s["id"] == andon_id), None)
                if all_stories_entry:
                    all_stories_entry.pop("status", None)
                    all_stories_entry["passes"] = False
                print(f"  ⚑  ANDON: revived killed story '{andon_id}' — GGE still broken")

            if not existing:
                andon_story = {
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
                    "branchName": f"fix/gge-{first_broken['id'].lower()}-andon-inc{current_phase}",
                    "dependencies": [],
                    "attempts": 0,
                    "smart": {"specific": 0, "measurable": 0, "achievable": 0,
                              "relevant": 0, "timeBound": 0, "notes": ""},
                }
                backlog["stories"].insert(0, andon_story)
                with open(backlog_path, "w") as f:
                    json.dump(backlog, f, indent=2)
                # Keep all_stories in sync so downstream checks see it
                all_stories.insert(0, andon_story)
                print(f"  ⚑  ANDON: created priority-0 story '{andon_id}' for broken GGE {first_broken['id']}")
            else:
                print(f"  ⚑  ANDON: priority-0 story '{andon_id}' already exists")

        return Assessment(
            state=PlatformState.SPRINT_READY,
            action=NextAction.THEME_REVIEW,
            reason=(
                f"GGE {first_broken['id']} is broken — Andon cord pulled. "
                f"Indicator: {first_broken.get('indicator', {}).get('type')}. "
                "Priority-0 story created. Starting at constitution-review so the "
                "team can evaluate whether this gate still reflects core values "
                "before planning a fix."
            ),
            kpis=kpis,
            shi=shi,
            niti=niti,
            agent_context=agent_context,
        )
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
            action=NextAction.THEME_REVIEW,
            reason=(
                f"{len(urgent)} priority-0 story/stories need attention: "
                f"{', '.join(s['id'] + ' (' + s['title'] + ')' for s in urgent)}. "
                "Starting at constitution-review to align on values before planning."
            ),
            kpis=kpis,
            shi=shi,
            niti=niti,
            agent_context=agent_context,
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
            shi=shi,
            niti=niti,
            agent_context=agent_context,
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
                shi=shi,
                niti=niti,
                agent_context=agent_context,
            )
        elif stories:
            # Sprint file exists and has stories, but all are reviewed or returnedToBacklog.
            # Only route to retro if the increment is NOT already marked complete —
            # if it is, advance already ran and the machine is in a done state.
            current_inc_entry = next(
                (p for p in phases if str(p.get("id")) == str(current_phase)), None
            )
            if current_inc_entry and current_inc_entry.get("status") == "complete":
                # Advance already closed this sprint. Fall through to COMPLETE check.
                pass
            else:
                accepted = [s for s in stories if s.get("passes", False) and s.get("reviewed", False)]
                returned = [s for s in stories if s.get("returnedToBacklog", False)]
                kpis.append(KPI(
                    "Sprint active",
                    "ready to close",
                    "OK",
                    f"{len(accepted)} accepted, {len(returned)} returned to backlog"
                ))
                return Assessment(
                    state=PlatformState.SPRINT_ACTIVE,
                    action=NextAction.RESUME_SPRINT,
                    reason=(
                        f"Sprint '{active_sprint_file}' is complete: {len(accepted)} accepted, "
                        f"{len(returned)} returned to backlog. Running retro to close the sprint."
                    ),
                    kpis=kpis,
                    resume_step="retro",
                    shi=shi,
                    niti=niti,
                    agent_context=agent_context,
                )

    # ── KPI 6: Epic coverage ────────────────────────────────────────────────
    story_epic_ids = {s.get("epicId") for s in all_stories if s.get("epicId")}
    # Only flag epics that still need work: not complete/killed, and whose
    # targetIncrement has not already shipped. Complete epics have no backlog
    # stories by design; epics targeting finished increments are closed work.
    complete_inc_ids = {str(p.get("id")) for p in phases if p.get("status") == "complete"}
    actionable_epics = [
        e for e in epics
        if e.get("status") not in ("complete", "killed")
        and str(e.get("targetIncrement", "")) not in complete_inc_ids
    ]
    empty_epics = [e for e in actionable_epics if e.get("id") not in story_epic_ids]
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
            shi=shi,
            niti=niti,
            agent_context=agent_context,
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
    remaining = [p for p in phases if p.get("status") not in ("complete",)]
    all_increments_done = not remaining

    if depth < BACKLOG_DEPTH_MIN:
        # PI Planning trigger: when all planned increments are delivered and the
        # backlog is thin, grooming alone won't help — we need to rethink what
        # we're building next. Escalate to constitution-review (top of the funnel).
        if all_increments_done:
            return Assessment(
                state=PlatformState.THIN_BACKLOG,
                action=NextAction.THEME_REVIEW,
                reason=(
                    f"All planned increments delivered and backlog depth is {depth:.1f} "
                    f"({len(ready_stories)} ready stories). "
                    "PI planning needed — run constitution-review → epic-breakdown → groom "
                    "to define the next wave of work before planning."
                ),
                kpis=kpis,
                shi=shi,
                niti=niti,
                agent_context=agent_context,
            )
        return Assessment(
            state=PlatformState.THIN_BACKLOG,
            action=NextAction.BACKLOG_GROOM,
            reason=(
                f"Backlog depth {depth:.1f} is below {BACKLOG_DEPTH_MIN} sprint threshold. "
                f"Only {len(ready_stories)} sprint-ready stories available. "
                "Run backlog-groom to score and refine stories before planning."
            ),
            kpis=kpis,
            shi=shi,
            niti=niti,
            agent_context=agent_context,
        )

    # ── Platform complete? ──────────────────────────────────────────────────
    # "Complete" only means no more *planned* increments — it does not mean
    # there is nothing left to do. Check whether the backlog has forward work
    # before declaring done.
    if all_increments_done:
        kpis.append(KPI("Platform", "kaizen", "OK", "all planned increments delivered — continuous improvement"))

        # PI Planning trigger: backlog is thin — the machine needs to ask
        # "what are we building next?" before it can call itself done.
        if depth < BACKLOG_DEPTH_MIN:
            return Assessment(
                state=PlatformState.THIN_BACKLOG,
                action=NextAction.THEME_REVIEW,
                reason=(
                    f"All planned increments delivered but backlog depth is {depth:.1f} "
                    f"({len(ready_stories)} ready stories). "
                    "PI planning needed: run constitution-review → epic-breakdown → groom "
                    "to define the next wave of work."
                ),
                kpis=kpis,
                shi=shi,
                niti=niti,
                agent_context=agent_context,
            )

        # Backlog has forward work but no planned increment to put it in —
        # plan a new increment.
        if ready_stories:
            return Assessment(
                state=PlatformState.SPRINT_READY,
                action=NextAction.PLAN,
                reason=(
                    f"All planned increments delivered. "
                    f"{len(ready_stories)} sprint-ready stories available "
                    f"({depth:.1f} sprints). Plan a new increment to continue."
                ),
                kpis=kpis,
                shi=shi,
                niti=niti,
                agent_context=agent_context,
            )

        # All planned work delivered and no ready stories — but we never stop.
        # Kaizen: look for drift, deprecation, hardening, refinement opportunities.
        return Assessment(
            state=PlatformState.KAIZEN,
            action=NextAction.THEME_REVIEW,
            reason=(
                "All planned increments delivered. Entering Kaizen cycle — "
                "review themes for drift, deprecated dependencies, hardening "
                "opportunities, and refinements. There is always something to improve."
            ),
            kpis=kpis,
            shi=shi,
            niti=niti,
            agent_context=agent_context,
        )

    return Assessment(
        state=PlatformState.SPRINT_READY,
        action=NextAction.PLAN,
        reason=(
            f"All KPIs green. {len(ready_stories)} sprint-ready stories available "
            f"({depth:.1f} sprints deep). Ready to plan next sprint."
        ),
        kpis=kpis,
        shi=shi,
        niti=niti,
        agent_context=agent_context,
    )
