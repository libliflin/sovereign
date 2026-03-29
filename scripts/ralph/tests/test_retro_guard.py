#!/usr/bin/env python3
"""Unit test for the pre-retro guard logic in ceremonies.py.

Verifies that find_limbo_stories() correctly identifies stories that are
passes:true but reviewed:false — the condition the pre-retro guard checks
before running the retro ceremony.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from ceremonies import find_limbo_stories


def test_detects_limbo_story():
    sprint = {
        "stories": [
            {"id": "S-001", "title": "Done and reviewed", "passes": True, "reviewed": True},
            {"id": "S-002", "title": "Limbo: passes but not reviewed", "passes": True, "reviewed": False},
            {"id": "S-003", "title": "Not started", "passes": False, "reviewed": False},
        ]
    }
    limbo = find_limbo_stories(sprint)
    assert len(limbo) == 1, f"Expected 1 limbo story, got {len(limbo)}: {limbo}"
    assert limbo[0]["id"] == "S-002", f"Expected S-002 in limbo, got {limbo[0]['id']}"
    print("PASS: guard correctly detects 1 limbo story (passes:true reviewed:false)")


def test_no_limbo_when_all_reviewed():
    sprint = {
        "stories": [
            {"id": "S-001", "passes": True, "reviewed": True},
            {"id": "S-002", "passes": False, "reviewed": False},
        ]
    }
    limbo = find_limbo_stories(sprint)
    assert len(limbo) == 0, f"Expected 0 limbo stories, got {len(limbo)}: {limbo}"
    print("PASS: guard correctly returns empty when no limbo stories exist")


def test_empty_sprint():
    sprint = {"stories": []}
    limbo = find_limbo_stories(sprint)
    assert len(limbo) == 0, f"Expected 0 limbo stories, got {len(limbo)}"
    print("PASS: guard correctly handles empty sprint")


if __name__ == "__main__":
    test_detects_limbo_story()
    test_no_limbo_when_all_reviewed()
    test_empty_sprint()
    print("\nAll tests passed.")
