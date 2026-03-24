"""
sprint.py — Load and save sprint files. Build failure context for agent prompt.
"""
from __future__ import annotations
import json
import subprocess
from pathlib import Path
from typing import Any


def load(path: Path) -> dict:
    with open(path) as f:
        return json.load(f)


def save(path: Path, data: dict) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def stories_needing_work(sprint: dict) -> list[dict]:
    return [s for s in sprint.get("stories", []) if not s.get("passes", False)]


def stories_passing(sprint: dict) -> list[dict]:
    return [s for s in sprint.get("stories", []) if s.get("passes", False)]


def reset_passing_to_false(path: Path, reason: str) -> int:
    sprint = load(path)
    count = 0
    for s in sprint["stories"]:
        if s.get("passes", False):
            s["passes"] = False
            notes = s.get("reviewNotes", [])
            notes.append(reason)
            s["reviewNotes"] = notes
            count += 1
    save(path, sprint)
    return count


def write_failures(path: Path, field: str, failures: list[dict]) -> None:
    sprint = load(path)
    sprint[field] = failures
    save(path, sprint)
    print(f"  {field}: {len(failures)} entry/entries written to sprint file.")


def clear_failures(path: Path) -> None:
    sprint = load(path)
    sprint.pop("_lastSmokeTestFailures", None)
    sprint.pop("_lastProofOfWorkFailures", None)
    save(path, sprint)


def build_failure_context(path: Path) -> str:
    """Build a markdown failure context section to inject into the agent prompt."""
    if not path.exists():
        return ""
    sprint = load(path)

    smoke = sprint.get("_lastSmokeTestFailures", [])
    proof = sprint.get("_lastProofOfWorkFailures", [])
    review_stories = [
        s for s in sprint.get("stories", [])
        if not s.get("passes", False) and any(
            n.startswith(("[REVIEW", "[SMOKE", "[PROOF", "[BLOCKED]"))
            for n in s.get("reviewNotes", [])
        )
    ]

    if not smoke and not proof and not review_stories:
        return ""

    lines = [
        "",
        "---",
        "## WARNING: FAILURE CONTEXT — READ THIS BEFORE TOUCHING ANY FILES",
        "",
        "The previous attempt was stopped by a gate check. Fix these specific issues.",
        "Gates re-run the same commands — do not mark passes:true until resolved.",
        "",
    ]

    if smoke:
        lines.append(f"### Smoke Test Failures ({len(smoke)} failing checks)")
        lines.append("")
        for f in smoke:
            lines.append(f"**{f.get('type')}** on `{f.get('target')}`")
            lines.append("```")
            lines.append(f.get("output", "(no output captured)"))
            lines.append("```")
            lines.append("")

    if proof:
        lines.append("### Proof-of-Work Failures")
        lines.append("")
        for f in proof:
            lines.append(f"- **{f.get('type')}**: {f.get('detail')}")
        lines.append("")

    if review_stories:
        lines.append("### Stories Re-opened by Review")
        lines.append("")
        for s in review_stories:
            lines.append(f"**{s['id']}: {s['title']}**")
            for note in s.get("reviewNotes", []):
                if note.startswith(("[REVIEW", "[SMOKE", "[PROOF", "[BLOCKED]")):
                    lines.append(f"  - {note}")
            lines.append("")

    lines += ["---", ""]
    return "\n".join(lines)
