"""
prd_model.py — Load and save themes, epics, backlog, manifest.
"""
from __future__ import annotations
import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _load(path: Path) -> Any:
    with open(path) as f:
        return json.load(f)


def _save(path: Path, data: Any) -> None:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  wrote {path}")


class Manifest:
    def __init__(self, repo_root: Path):
        self.path = repo_root / "prd" / "manifest.json"
        self._data = _load(self.path)

    @property
    def active_sprint(self) -> str | None:
        return self._data.get("activeSprint")

    @property
    def current_phase(self) -> Any:
        return self._data.get("currentPhase")

    def phase(self, phase_id: Any) -> dict | None:
        for p in self._data.get("phases", []):
            if str(p["id"]) == str(phase_id):
                return p
        return None

    def next_pending_phase(self) -> dict | None:
        for p in self._data.get("phases", []):
            if p.get("status") == "pending":
                return p
        return None

    def set_phase_active(self, phase_id: Any, sprint_file: str, points: int, stories: int) -> None:
        for p in self._data["phases"]:
            if str(p["id"]) == str(phase_id):
                p["status"] = "active"
                p["startDate"] = datetime.now(timezone.utc).isoformat()
                p["pointsTotal"] = points
                p["storiesTotal"] = stories
        self._data["activeSprint"] = sprint_file
        self._data["currentPhase"] = phase_id
        _save(self.path, self._data)

    def close_phase(self, phase_id: Any, points_completed: int, stories_accepted: int) -> None:
        for p in self._data["phases"]:
            if str(p["id"]) == str(phase_id):
                p["status"] = "complete"
                p["endDate"] = datetime.now(timezone.utc).isoformat()
                p["pointsCompleted"] = points_completed
                p["storiesAccepted"] = stories_accepted
        _save(self.path, self._data)

    def raw(self) -> dict:
        return self._data


class Backlog:
    def __init__(self, repo_root: Path):
        self.path = repo_root / "prd" / "backlog.json"
        self._data = _load(self.path)

    @property
    def stories(self) -> list[dict]:
        return self._data.get("stories", [])

    def stories_for_phase(self, phase_id: Any) -> list[dict]:
        return [s for s in self.stories if str(s.get("phase", "")) == str(phase_id)]

    def update_story(self, story_id: str, updates: dict) -> None:
        for s in self._data["stories"]:
            if s["id"] == story_id:
                s.update(updates)
        _save(self.path, self._data)

    def add_stories(self, stories: list[dict]) -> None:
        existing_ids = {s["id"] for s in self._data["stories"]}
        for s in stories:
            if s["id"] not in existing_ids:
                self._data["stories"].append(s)
        _save(self.path, self._data)


class Themes:
    def __init__(self, repo_root: Path):
        self.path = repo_root / "prd" / "themes.json"
        self._data = _load(self.path) if self.path.exists() else {"themes": []}

    @property
    def themes(self) -> list[dict]:
        return self._data.get("themes", [])

    def by_id(self, theme_id: str) -> dict | None:
        return next((t for t in self.themes if t["id"] == theme_id), None)


class Epics:
    def __init__(self, repo_root: Path):
        self.path = repo_root / "prd" / "epics.json"
        self._data = _load(self.path) if self.path.exists() else {"epics": []}

    @property
    def epics(self) -> list[dict]:
        return self._data.get("epics", [])

    def by_id(self, epic_id: str) -> dict | None:
        return next((e for e in self.epics if e["id"] == epic_id), None)

    def for_increment(self, phase_id: Any) -> list[dict]:
        return [e for e in self.epics if str(e.get("targetIncrement", "")) == str(phase_id)]

    def add_stories(self, epic_id: str, story_ids: list[str]) -> None:
        for e in self._data["epics"]:
            if e["id"] == epic_id:
                existing = set(e.get("storyIds", []))
                e["storyIds"] = list(existing | set(story_ids))
        _save(self.path, self._data)
