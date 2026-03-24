"""
gates.py — Bash-enforced quality gates: preflight, smoke_test, proof_of_work.
All gates return (passed: bool, failures: list[dict]).
"""
from __future__ import annotations
import subprocess
import shutil
from pathlib import Path


def _run(cmd: str, cwd: Path | None = None) -> tuple[int, str]:
    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, cwd=cwd
    )
    return result.returncode, (result.stdout + result.stderr).strip()


def check_tool(name: str) -> bool:
    return shutil.which(name) is not None


def preflight(repo_root: Path, sprint: dict) -> tuple[bool, list[str]]:
    """Check required tools and credentials. Returns (passed, missing_items)."""
    missing = []
    required = ["jq", "git", "helm", "kubectl", "gh", "shellcheck", "yq"]
    for tool in required:
        if check_tool(tool):
            print(f"  ok {tool} ({shutil.which(tool)})")
        else:
            print(f"  MISSING (required): {tool}")
            missing.append(tool)

    # kind/docker: only if any story requires it
    needs_kind = any(
        "kind" in s.get("requiredCapabilities", [])
        for s in sprint.get("stories", [])
    )
    if needs_kind:
        if check_tool("kind"):
            print(f"  ok kind ({shutil.which('kind')})")
            rc, _ = _run("docker info", cwd=repo_root)
            if rc == 0:
                print("  ok Docker running")
            else:
                print("  Docker not running")
                missing.append("docker")
        else:
            print("  MISSING: kind  -> Fix: brew install kind")
            missing.append("kind")
    else:
        print("  ~ kind/Docker not required by any story in this sprint")

    # git remote
    rc, _ = _run("git ls-remote origin HEAD", cwd=repo_root)
    if rc == 0:
        rc2, url = _run("git remote get-url origin", cwd=repo_root)
        print(f"  ok origin reachable ({url})")
    else:
        print("  origin not reachable")
        missing.append("git-remote")

    # gh auth
    rc, user = _run("gh api user --jq .login", cwd=repo_root)
    if rc == 0:
        print(f"  ok gh authenticated as: {user.strip()}")
    else:
        print("  gh not authenticated  -> Fix: gh auth login --web")
        missing.append("gh-auth")

    return len(missing) == 0, missing


def smoke_test(repo_root: Path) -> tuple[bool, list[dict]]:
    """Run helm lint, shellcheck, JSON validation, yq on argocd-apps. Returns (passed, failures)."""
    failures = []

    # 1. helm lint all charts
    print("  helm lint:")
    for chart_yaml in sorted((repo_root / "charts").glob("*/Chart.yaml")):
        chart_dir = chart_yaml.parent
        name = chart_dir.name
        rc, out = _run(f"helm lint {chart_dir}")
        print(out)
        if rc == 0:
            print(f"    ok {name}")
        else:
            print(f"    FAIL: {name}")
            failures.append({
                "type": "helm-lint",
                "target": f"charts/{name}",
                "output": out[:1500]
            })
    if not failures:
        print("    all charts passed")

    # 2. bash -n + shellcheck on all .sh files
    print("  bash syntax + shellcheck:")
    sh_fail = False
    for script in sorted(repo_root.rglob("*.sh")):
        if ".git" in str(script):
            continue
        rel = str(script.relative_to(repo_root))
        rc1, out1 = _run(f"bash -n {script}")
        rc2, out2 = _run(f"shellcheck {script}")
        if rc1 == 0 and rc2 == 0:
            print(f"    ok {rel}")
        else:
            print(f"    FAIL: {rel}")
            combined = f"bash -n: {out1}\nshellcheck: {out2}"
            failures.append({
                "type": "shellcheck",
                "target": rel,
                "output": combined[:1500]
            })
            sh_fail = True
    if not sh_fail:
        print("    all scripts passed")

    # 3. JSON validation for prd/
    print("  JSON validation (prd/):")
    json_fail = False
    for jf in sorted((repo_root / "prd").rglob("*.json")):
        rel = str(jf.relative_to(repo_root))
        rc, out = _run(f"jq empty {jf}")
        if rc == 0:
            print(f"    ok {rel}")
        else:
            print(f"    FAIL: {rel}")
            failures.append({"type": "json-invalid", "target": rel, "output": out[:500]})
            json_fail = True
    if not json_fail:
        print("    all JSON files valid")

    # 4. yq YAML syntax check on argocd-apps/
    print("  YAML syntax check (argocd-apps/):")
    yaml_fail = False
    argocd_dir = repo_root / "argocd-apps"
    if argocd_dir.exists():
        for yf in sorted(argocd_dir.rglob("*.yaml")):
            rel = str(yf.relative_to(repo_root))
            rc, out = _run(f"yq e '.' {yf}")
            if rc == 0:
                print(f"    ok {rel}")
            else:
                print(f"    FAIL: {rel}")
                failures.append({"type": "yaml-invalid", "target": rel, "output": out[:500]})
                yaml_fail = True
        if not yaml_fail:
            print("    all ArgoCD manifests valid")
    else:
        print("    (argocd-apps/ not found, skipping)")

    return len(failures) == 0, failures


def proof_of_work(repo_root: Path, sprint: dict) -> tuple[bool, list[dict]]:
    """Verify branches pushed and PRs exist. Returns (passed, failures)."""
    failures = []

    sprint_branch = sprint.get("branchName", "")
    story_branches = []
    if sprint_branch:
        story_branches = [sprint_branch]
    else:
        story_branches = [
            s["branchName"]
            for s in sprint.get("stories", [])
            if s.get("passes", False) and s.get("branchName")
        ]

    if not story_branches:
        print("  No branches to check (no passing stories with branchName)")
        return True, []

    for branch in story_branches:
        # Check if branch is on remote
        result = subprocess.run(
            f"git ls-remote --heads origin {branch}",
            shell=True, capture_output=True, text=True, cwd=repo_root
        )
        branch_on_remote = result.returncode == 0 and bool(result.stdout.strip())

        if branch_on_remote:
            print(f"  ok pushed: origin/{branch}")
        else:
            # Check if merged PR exists
            rc2, merged = _run(
                f"gh pr list --state merged --head {branch} --json number --jq '.[0].number'",
                cwd=repo_root
            )
            if rc2 == 0 and merged.strip() and merged.strip() != "null":
                print(f"  ok pushed: origin/{branch} (merged as PR #{merged.strip()})")
            else:
                print(f"  NOT pushed: {branch}")
                print(f"    -> Fix: git push origin {branch}")
                failures.append({
                    "type": "branch-not-pushed",
                    "detail": f"Branch '{branch}' not found on origin. Run: git push origin {branch}"
                })

        # Check PR exists (any state)
        rc3, pr_num = _run(
            f"gh pr list --state all --head {branch} --json number --jq '.[0].number'",
            cwd=repo_root
        )
        if rc3 == 0 and pr_num.strip() and pr_num.strip() != "null":
            print(f"  ok PR #{pr_num.strip()} exists for {branch}")
        else:
            print(f"  No PR found for: {branch}")
            print(f"    -> Fix: gh pr create --head {branch} --base main --title '...'")
            failures.append({
                "type": "no-pr",
                "detail": f"No PR found for '{branch}'. Run: gh pr create --head {branch} --base main"
            })

    return len(failures) == 0, failures
