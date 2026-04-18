#!/usr/bin/env python3
"""
Tests for platform/vendor/recipes/vscode-extensions/fetch-vsix.sh

Covers:
  1. Script passes shellcheck -S error (no shell safety violations)
  2. --dry-run mode prints expected lines without writing any files
  3. Dry-run produces one DRY-RUN line per extension (reads values.yaml)
  4. Script exits 0 in dry-run mode
  5. Output directory is not created in dry-run mode

Plain Python — no pytest. Runs with: python3 test_fetch_vsix.py
Output format: PASS: <description> lines, ending with "All tests passed."
"""
import os
import shutil
import subprocess
import sys
import tempfile

import yaml

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SCRIPT = os.path.join(
    REPO_ROOT, "platform", "vendor", "recipes", "vscode-extensions", "fetch-vsix.sh"
)
VALUES_FILE = os.path.join(
    REPO_ROOT, "platform", "charts", "code-server", "values.yaml"
)


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


# ── Test 1: shellcheck ────────────────────────────────────────────────────────

result = run(["shellcheck", "-S", "error", SCRIPT])
assert result.returncode == 0, (
    f"shellcheck failed:\n{result.stdout}\n{result.stderr}"
)
print("PASS: fetch-vsix.sh passes shellcheck -S error")

# ── Test 2: script is executable ──────────────────────────────────────────────

assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"
print("PASS: fetch-vsix.sh is executable")

# ── Helpers ───────────────────────────────────────────────────────────────────

def extensions_from_values():
    with open(VALUES_FILE) as f:
        vals = yaml.safe_load(f)
    return vals.get("extensions", [])


# ── Test 3: dry-run exits 0 ───────────────────────────────────────────────────

with tempfile.TemporaryDirectory() as tmpdir:
    out_dir = os.path.join(tmpdir, "vsix-cache")
    result = run([SCRIPT, "--dry-run", "--output-dir", out_dir])

assert result.returncode == 0, (
    f"--dry-run exited {result.returncode}:\n{result.stderr}"
)
print("PASS: --dry-run exits 0")

# ── Test 4: dry-run prints one DRY-RUN line per extension ─────────────────────

with tempfile.TemporaryDirectory() as tmpdir:
    out_dir = os.path.join(tmpdir, "vsix-cache")
    result = run([SCRIPT, "--dry-run", "--output-dir", out_dir])

exts = extensions_from_values()
dry_run_lines = [l for l in result.stdout.splitlines() if "DRY-RUN: write" in l]
assert len(dry_run_lines) == len(exts), (
    f"Expected {len(exts)} DRY-RUN: write lines, got {len(dry_run_lines)}:\n{result.stdout}"
)
print(f"PASS: --dry-run prints {len(exts)} DRY-RUN: write line(s) (one per extension)")

# ── Test 5: dry-run creates no files ─────────────────────────────────────────

with tempfile.TemporaryDirectory() as tmpdir:
    out_dir = os.path.join(tmpdir, "vsix-cache")
    run([SCRIPT, "--dry-run", "--output-dir", out_dir])
    assert not os.path.exists(out_dir), (
        f"--dry-run must not create output directory, but found: {out_dir}"
    )
print("PASS: --dry-run creates no files or directories")

# ── Test 6: dry-run URL path matches initContainer expectation ────────────────
# Each DRY-RUN: write line must end with /vsix/<publisher>/<name>/latest.vsix

with tempfile.TemporaryDirectory() as tmpdir:
    out_dir = os.path.join(tmpdir, "vsix-cache")
    result = run([SCRIPT, "--dry-run", "--output-dir", out_dir])

write_lines = [l for l in result.stdout.splitlines() if "DRY-RUN: write" in l]
for ext in exts:
    publisher, name = ext.split(".", 1)
    expected_suffix = f"/vsix/{publisher}/{name}/latest.vsix"
    matched = any(expected_suffix in line for line in write_lines)
    assert matched, (
        f"No DRY-RUN write line found for {ext} with path suffix {expected_suffix}\n"
        f"Output:\n{result.stdout}"
    )
print("PASS: dry-run write paths match /vsix/<publisher>/<name>/latest.vsix pattern")

# ── Test 7: reads extension list from code-server values.yaml ────────────────
# Confirm the script mentions the first extension by publisher name in its output

with tempfile.TemporaryDirectory() as tmpdir:
    out_dir = os.path.join(tmpdir, "vsix-cache")
    result = run([SCRIPT, "--dry-run", "--output-dir", out_dir])

first_ext = exts[0] if exts else None
if first_ext:
    assert first_ext in result.stdout, (
        f"Expected to see '{first_ext}' in dry-run output:\n{result.stdout}"
    )
    print(f"PASS: dry-run output names extensions from values.yaml (confirmed: {first_ext})")
else:
    print("PASS: no extensions in values.yaml (vacuously true)")

print("")
print("All tests passed.")
