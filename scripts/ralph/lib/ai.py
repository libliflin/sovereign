"""
ai.py — Run AI ceremonies (claude/amp) and handle rate limiting.

Signal handling: Every subprocess is wrapped in try/except so that
SIGINT (from supervisord stopasgroup) terminates the child process
before this module re-raises.  Without this, claude processes orphan
because the Claude desktop app's disclaimer wrapper re-parents them
into a different process group — supervisord's group signal never
reaches them.
"""
from __future__ import annotations
import os
import re
import signal
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path


def _terminate_and_wait(proc: subprocess.Popen, timeout: int = 10) -> None:
    """Send SIGTERM, wait, then SIGKILL if still alive."""
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def run_ceremony(tool: str, prompt_file: Path, log_file: Path) -> str:
    """Run a markdown ceremony file through claude or amp. Returns streamed output."""
    with open(prompt_file) as f:
        prompt = f.read()

    if tool == "claude":
        cmd = ["claude", "--dangerously-skip-permissions", "--print"]
    else:
        cmd = ["amp", "--dangerously-allow-all"]

    print(f"  → Calling {tool} with {prompt_file.name} ...", flush=True)

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        proc.stdin.write(prompt)
        proc.stdin.close()

        lines = []
        for line in proc.stdout:
            print(line, end="", flush=True)
            lines.append(line)
        proc.wait()
    except KeyboardInterrupt:
        print("\n  ✕ Interrupted — terminating child process ...", flush=True)
        _terminate_and_wait(proc)
        raise

    output = "".join(lines)

    with open(log_file, "a") as f:
        f.write(output)

    return output


def run_ralph(ralph_sh: Path, prd_file: Path, tool: str, max_iter: int, log_file: Path) -> int:
    """Run ralph.sh and stream output to stdout and log file. Returns exit code."""
    cmd = [str(ralph_sh), "--prd", str(prd_file), "--tool", tool, str(max_iter)]
    with open(log_file, "a") as lf:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )
        try:
            for line in proc.stdout:
                print(line, end="", flush=True)
                lf.write(line)
            proc.wait()
        except KeyboardInterrupt:
            print("\n  ✕ Interrupted — terminating ralph ...", flush=True)
            _terminate_and_wait(proc)
            raise
    return proc.returncode


def is_rate_limited(output: str) -> bool:
    return "You've hit your limit" in output


def sleep_until_reset(output: str) -> None:
    """Parse reset time from output and sleep in 3-minute increments."""
    m = re.search(r"resets (\d{1,2}(?:am|pm)) \(([^)]+)\)", output, re.IGNORECASE)

    if not m:
        print("   Could not parse reset time. Sleeping 1 hour.")
        sleep_secs = 3600
        tz_name = "America/Detroit"
    else:
        reset_str = m.group(1).lower()
        tz_name = m.group(2)
        sleep_secs = _calc_sleep(reset_str, tz_name)

    resume_time = _detroit_time(sleep_secs)
    h, rem = divmod(sleep_secs, 3600)
    mins = rem // 60

    print(f"   +---------------------------------------------+")
    print(f"   |  Resume at: {resume_time}")
    print(f"   |  Waiting {h}h {mins}m — 3-min increments (laptop-sleep safe)")
    print(f"   +---------------------------------------------+")
    print()

    deadline = time.time() + sleep_secs
    while True:
        now = time.time()
        if now >= deadline:
            break
        remaining = int(deadline - now)
        rh, rrem = divmod(remaining, 3600)
        rm = rrem // 60
        print(f"   {rh}h {rm:02d}m remaining ...\r", end="", flush=True)
        time.sleep(180)

    print()
    print("  Resuming after rate limit reset.")


def _calc_sleep(reset_str: str, tz_name: str) -> int:
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo(tz_name)
        now = datetime.now(tz)
    except Exception:
        from datetime import timezone
        now = datetime.now(timezone.utc)

    is_pm = reset_str.endswith("pm")
    hour = int(reset_str[:-2])
    if is_pm and hour != 12:
        hour += 12
    elif not is_pm and hour == 12:
        hour = 0

    target = now.replace(hour=hour, minute=5, second=0, microsecond=0)
    if target <= now:
        target += timedelta(days=1)

    return max(0, int((target - now).total_seconds()))


def _detroit_time(sleep_secs: int) -> str:
    # Do NOT import timedelta inside this function — it would shadow the module-level
    # import and cause UnboundLocalError when the except branch doesn't execute.
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("America/Detroit")
    except Exception:
        from datetime import timezone as _tz
        tz = _tz(timedelta(hours=-5))
    t = datetime.now(tz) + timedelta(seconds=sleep_secs)
    return t.strftime("%I:%M %p %Z  (%a %b %-d)")
