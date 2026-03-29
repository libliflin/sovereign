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

    # kind/docker: always checked — the whole stack runs on kind
    if check_tool("kind"):
        print(f"  ok kind ({shutil.which('kind')})")
        rc, _ = _run("docker info", cwd=repo_root)
        if rc == 0:
            print("  ok Docker running")
        else:
            print("  Docker not running  -> Fix: start Docker Desktop")
            missing.append("docker")
    else:
        print("  MISSING: kind  -> Fix: brew install kind")
        missing.append("kind")

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


def _git_tracked(repo_root: Path, pattern: str = "") -> list[Path]:
    """Return tracked files matching pattern using git ls-files (respects .gitignore)."""
    cmd = f"git ls-files {pattern}" if pattern else "git ls-files"
    rc, out = _run(cmd, cwd=repo_root)
    if rc != 0 or not out.strip():
        return []
    return [repo_root / f for f in out.splitlines() if f.strip()]


def smoke_test(repo_root: Path) -> tuple[bool, list[dict]]:
    """Run helm lint, shellcheck, JSON validation, yq on argocd-apps, contract validation,
    and G6 autarky gate. Returns (passed, failures).
    All file discovery uses git ls-files — only tracked files, .gitignore respected."""
    failures = []

    # 1. helm lint all charts — platform/charts/ and cluster/kind/charts/
    print("  helm lint:")
    chart_dirs = [
        repo_root / "platform" / "charts",
        repo_root / "cluster" / "kind" / "charts",
    ]
    helm_fail = False
    for charts_root in chart_dirs:
        for chart_yaml in sorted(charts_root.glob("*/Chart.yaml")):
            chart_dir = chart_yaml.parent
            rel = str(chart_dir.relative_to(repo_root))
            rc, out = _run(f"helm lint {chart_dir}")
            print(out)
            if rc == 0:
                print(f"    ok {rel}")
            else:
                print(f"    FAIL: {rel}")
                failures.append({
                    "type": "helm-lint",
                    "target": rel,
                    "output": out[:1500]
                })
                helm_fail = True
    if not helm_fail:
        print("    all charts passed")

    # 2. bash -n + shellcheck — only git-tracked .sh files (respects .gitignore)
    print("  bash syntax + shellcheck:")
    sh_fail = False
    scripts = sorted(_git_tracked(repo_root, "'*.sh'"))
    for script in scripts:
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

    # 3. JSON validation — only git-tracked .json files under prd/
    print("  JSON validation (prd/):")
    json_fail = False
    json_files = sorted(_git_tracked(repo_root, "'prd/*.json' 'prd/**/*.json'"))
    for jf in json_files:
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

    # 4. yq YAML syntax check — only git-tracked .yaml files under platform/argocd-apps/
    print("  YAML syntax check (platform/argocd-apps/):")
    yaml_fail = False
    yaml_files = sorted(_git_tracked(
        repo_root,
        "'platform/argocd-apps/**/*.yaml' 'platform/argocd-apps/*.yaml'"
    ))
    if yaml_files:
        for yf in yaml_files:
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
        print("    (no tracked platform/argocd-apps/ YAML found, skipping)")

    # 5. Contract validation — validate test fixtures to prove the validator works
    print("  contract validation:")
    validate_py = repo_root / "contract" / "validate.py"
    valid_yaml = repo_root / "contract" / "v1" / "tests" / "valid.yaml"
    invalid_yaml = repo_root / "contract" / "v1" / "tests" / "invalid-egress-not-blocked.yaml"
    if validate_py.exists() and valid_yaml.exists() and invalid_yaml.exists():
        # valid.yaml must exit 0
        rc, out = _run(f"python3 {validate_py} {valid_yaml}")
        if rc == 0:
            print(f"    ok valid.yaml accepted")
        else:
            print(f"    FAIL: valid.yaml rejected (should pass)")
            failures.append({"type": "contract-validator", "target": "contract/v1/tests/valid.yaml", "output": out[:500]})
        # invalid-egress-not-blocked.yaml must exit 1 with AUTARKY VIOLATION
        rc2, out2 = _run(f"python3 {validate_py} {invalid_yaml}")
        if rc2 != 0 and "AUTARKY VIOLATION" in out2:
            print(f"    ok invalid-egress-not-blocked.yaml rejected with AUTARKY VIOLATION")
        else:
            print(f"    FAIL: invalid-egress-not-blocked.yaml should fail with AUTARKY VIOLATION")
            failures.append({"type": "contract-validator", "target": "contract/v1/tests/invalid-egress-not-blocked.yaml", "output": out2[:500]})
    else:
        print("    (contract/validate.py or test fixtures not found, skipping)")

    # 6. G6 autarky gate — no hard-coded external registry refs in chart templates
    print("  G6 autarky gate (no external registries in templates):")
    external_registries = r"docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io"
    template_dirs = [
        repo_root / "platform" / "charts",
        repo_root / "cluster" / "kind" / "charts",
    ]
    autarky_fail = False
    for tdir in template_dirs:
        if not tdir.exists():
            continue
        rc, out = _run(
            f"grep -rn '{external_registries}' {tdir}/*/templates/ 2>/dev/null || true"
        )
        if out.strip():
            print(f"    FAIL: external registry reference found:\n{out[:800]}")
            failures.append({
                "type": "autarky-violation",
                "target": str(tdir.relative_to(repo_root)),
                "output": out[:800]
            })
            autarky_fail = True
    if not autarky_fail:
        print("    PASS: no external registry references in templates")

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
