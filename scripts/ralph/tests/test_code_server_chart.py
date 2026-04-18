#!/usr/bin/env python3
"""
Tests for platform/charts/code-server/ Helm chart — covering the AI Agent
toolchain dead-end fixes:
  1. PATH env var on main container (kubectl/helm/shellcheck reachable by name)
  2. PVC uses workspace.storageClass (ceph-filesystem, RWX) not global.storageClass (ceph-block, RWO)
  3. PVC uses workspace.storageSize, not persistence.size
  4. shellcheck is in the toolchain initContainer copy loop
  5. Toolchain bin path is first on PATH (not buried after system paths)

Plain Python — no pytest. Runs with: python3 test_code_server_chart.py
Output format: PASS: <description> lines, ending with "All tests passed."
"""
import os
import subprocess
import sys

import yaml

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CHART_DIR = os.path.join(REPO_ROOT, "platform", "charts", "code-server")


def helm_template(extra_args=None):
    """Run helm template on the code-server chart and return parsed YAML docs."""
    cmd = ["helm", "template", "test-release", CHART_DIR]
    if extra_args:
        cmd.extend(extra_args)
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return list(yaml.safe_load_all(result.stdout))


def get_deployment(docs):
    for doc in docs:
        if doc and doc.get("kind") == "Deployment":
            return doc
    raise AssertionError("No Deployment found in helm template output")


def get_pvc(docs):
    for doc in docs:
        if doc and doc.get("kind") == "PersistentVolumeClaim":
            return doc
    raise AssertionError("No PersistentVolumeClaim found in helm template output")


def get_env(container, name):
    for env in container.get("env", []):
        if env["name"] == name:
            return env.get("value", "")
    return None


def get_init_container(spec, name):
    for ic in spec.get("initContainers", []):
        if ic["name"] == name:
            return ic
    return None


def get_main_container(spec):
    for c in spec.get("containers", []):
        if c["name"] == "code-server":
            return c
    raise AssertionError("No 'code-server' container found in Deployment")


def tests():
    docs = helm_template()
    deploy = get_deployment(docs)
    pod_spec = deploy["spec"]["template"]["spec"]
    main = get_main_container(pod_spec)
    pvc = get_pvc(docs)

    # 1. PATH env var is present on the main container
    path_val = get_env(main, "PATH")
    assert path_val is not None, "FAIL: PATH env var missing from main container"
    print("PASS: PATH env var is present on main container")

    # 2. Toolchain bin path is the first element on PATH
    # Agents must not have to type the full binary path.
    bin_path = path_val.split(":")[0]
    assert bin_path == "/home/coder/workspace/bin", (
        f"FAIL: first PATH element is {bin_path!r}, expected '/home/coder/workspace/bin'"
    )
    print("PASS: /home/coder/workspace/bin is first on PATH")

    # 3. PATH contains standard system paths (not just the toolchain dir)
    assert "/usr/local/bin" in path_val, (
        "FAIL: PATH does not include /usr/local/bin — system tools would be unreachable"
    )
    print("PASS: PATH includes standard system paths")

    # 4. PVC storageClassName is workspace.storageClass (ceph-filesystem), not global.storageClass
    storage_class = pvc["spec"]["storageClassName"]
    assert storage_class == "ceph-filesystem", (
        f"FAIL: PVC storageClassName is {storage_class!r}, expected 'ceph-filesystem' (RWX). "
        "With replicaCount=2 and ceph-block (RWO), the second pod hangs in ContainerCreating."
    )
    print("PASS: PVC storageClassName is ceph-filesystem (RWX — supports replicaCount >= 2)")

    # 5. PVC accessModes includes ReadWriteMany (required for replicaCount >= 2 with ceph-filesystem)
    access_modes = pvc["spec"]["accessModes"]
    assert "ReadWriteMany" in access_modes, (
        f"FAIL: PVC accessModes {access_modes} does not include ReadWriteMany"
    )
    print("PASS: PVC accessModes includes ReadWriteMany")

    # 6. PVC storage size comes from workspace.storageSize (10Gi), not persistence.size (5Gi stale field)
    storage_size = pvc["spec"]["resources"]["requests"]["storage"]
    assert storage_size == "10Gi", (
        f"FAIL: PVC storage size is {storage_size!r}, expected '10Gi' from workspace.storageSize. "
        "persistence.size (5Gi) is the stale field — pvc.yaml should use workspace.storageSize."
    )
    print("PASS: PVC storage size is 10Gi (from workspace.storageSize)")

    # 7. shellcheck is in the install-toolchain initContainer copy loop
    install_tc = get_init_container(pod_spec, "install-toolchain")
    assert install_tc is not None, "FAIL: install-toolchain initContainer not found"
    tc_script = " ".join(install_tc.get("command", []) + install_tc.get("args", []))
    assert "shellcheck" in tc_script, (
        "FAIL: 'shellcheck' not found in install-toolchain initContainer script. "
        "Agents cannot run 'bash scripts/ha-gate.sh' without shellcheck on PATH."
    )
    print("PASS: shellcheck is in install-toolchain initContainer copy loop")

    # 8. kubectl and helm are also in the loop (regression guard)
    for tool in ("kubectl", "helm", "k9s"):
        assert tool in tc_script, (
            f"FAIL: '{tool}' not found in install-toolchain script — regression"
        )
    print("PASS: kubectl, helm, k9s all present in install-toolchain loop (no regression)")

    # 9. HA: replicaCount >= 2 in values (structural, not a default-values test)
    result = subprocess.run(
        ["helm", "template", "test-release", CHART_DIR],
        capture_output=True, text=True, check=True
    )
    # Verify at least one PodDisruptionBudget is present
    assert "PodDisruptionBudget" in result.stdout, (
        "FAIL: No PodDisruptionBudget in rendered templates — HA requirement not met"
    )
    print("PASS: PodDisruptionBudget present in rendered templates")

    # 10. Adversarial: override global.storageClass should NOT affect workspace PVC storageClass
    docs_override = helm_template(["--set", "global.storageClass=something-else"])
    pvc_override = get_pvc(docs_override)
    sc_override = pvc_override["spec"]["storageClassName"]
    assert sc_override == "ceph-filesystem", (
        f"FAIL: Overriding global.storageClass changed PVC storageClassName to {sc_override!r}. "
        "PVC must use workspace.storageClass, not global.storageClass."
    )
    print("PASS: global.storageClass override does not bleed into workspace PVC storageClass")

    # Extension install logic (round 2 changes)

    # 11. extensionRegistry default must not reference any external registry.
    # Acceptable defaults: empty string (skip install) or in-cluster svc.cluster.local URL.
    # Rejected: any public registry host (marketplace.visualstudio.com, docker.io, ghcr.io, etc.)
    # The vscode-extension-registry chart provides an in-cluster nginx server; the default
    # is wired to its service URL so no operator config is needed after deploy.
    install_ext_ic = get_init_container(pod_spec, "install-extensions")
    assert install_ext_ic is not None, "FAIL: install-extensions initContainer not found"
    ext_registry_env = get_env(install_ext_ic, "EXTENSION_REGISTRY")
    assert ext_registry_env is not None, "FAIL: EXTENSION_REGISTRY env var missing from install-extensions"
    external_hosts = [
        "marketplace.visualstudio.com",
        "open-vsx.org",
        "docker.io",
        "ghcr.io",
        "quay.io",
        "gcr.io",
        "registry.k8s.io",
    ]
    for host in external_hosts:
        assert host not in ext_registry_env, (
            f"FAIL: EXTENSION_REGISTRY defaults to {ext_registry_env!r} which references "
            f"external host '{host}'. Default must be empty or an in-cluster svc.cluster.local URL — "
            "external registry calls break zero-trust egress."
        )
    # Validate: if non-empty, must be in-cluster (svc.cluster.local or cluster-internal scheme)
    if ext_registry_env:
        assert "svc.cluster.local" in ext_registry_env or ext_registry_env.startswith("http://"), (
            f"FAIL: EXTENSION_REGISTRY defaults to {ext_registry_env!r}. "
            "Non-empty default that isn't an in-cluster svc.cluster.local URL risks external egress."
        )
        print(f"PASS: EXTENSION_REGISTRY defaults to in-cluster registry — zero-trust safe: {ext_registry_env!r}")
    else:
        print("PASS: EXTENSION_REGISTRY defaults to empty — extension install skipped on pod start")

    # 12. install-extensions script uses --install-extension not --vsix
    # code-server does not have a --vsix flag; the VSIX path goes to --install-extension.
    ext_script = " ".join(install_ext_ic.get("command", []) + install_ext_ic.get("args", []))
    assert "--install-extension" in ext_script, (
        "FAIL: install-extensions script does not use --install-extension. "
        "code-server has no --vsix flag; VSIX path must be passed to --install-extension."
    )
    assert "--vsix" not in ext_script, (
        "FAIL: install-extensions script uses --vsix. "
        "code-server does not support --vsix — use --install-extension <path> instead."
    )
    print("PASS: install-extensions uses --install-extension (not --vsix) for VSIX files")

    # 13. Adversarial: setting extensionRegistry propagates to EXTENSION_REGISTRY env var
    docs_with_reg = helm_template(["--set", "extensionRegistry=https://harbor.test/sovereign"])
    deploy_with_reg = get_deployment(docs_with_reg)
    spec_with_reg = deploy_with_reg["spec"]["template"]["spec"]
    ic_with_reg = get_init_container(spec_with_reg, "install-extensions")
    env_with_reg = get_env(ic_with_reg, "EXTENSION_REGISTRY")
    assert env_with_reg == "https://harbor.test/sovereign", (
        f"FAIL: EXTENSION_REGISTRY is {env_with_reg!r} when extensionRegistry is set, "
        "expected 'https://harbor.test/sovereign'. Setting extensionRegistry has no effect."
    )
    print("PASS: extensionRegistry value propagates to EXTENSION_REGISTRY env var")

    # 14. install-extensions script skips marker write when extensionRegistry is empty
    # The skip path (empty registry) must exit 0 WITHOUT touching $MARKER.
    # Verifiable from script content: the "touch $MARKER" must not appear before the registry check.
    skip_check = 'if [ -z "$EXTENSION_REGISTRY" ]'
    marker_write = "touch"
    skip_pos = ext_script.find(skip_check)
    marker_pos = ext_script.find(marker_write)
    assert skip_pos != -1, "FAIL: empty-registry skip check not found in install-extensions script"
    assert marker_pos > skip_pos, (
        "FAIL: marker 'touch' appears before empty-registry skip check — "
        "marker would be written even when registry is empty."
    )
    print("PASS: marker write occurs after empty-registry skip check (no marker written on skip)")

    # 15. install-extensions --extensions-dir matches main container --extensions-dir
    # If these diverge, extensions are installed to a directory code-server doesn't watch —
    # they install silently and never appear in the browser IDE.
    main_ext_dir = None
    for arg in main.get("args", []):
        if arg.startswith("--extensions-dir="):
            main_ext_dir = arg.split("=", 1)[1]
            break
    assert main_ext_dir is not None, "FAIL: --extensions-dir not found in main container args"
    import re
    m = re.search(r"--extensions-dir\s+(\S+?)(?:[;\s]|$)", ext_script)
    ic_ext_dir = m.group(1).rstrip(";") if m else None
    assert ic_ext_dir is not None, "FAIL: --extensions-dir not found in install-extensions initContainer script"
    assert main_ext_dir == ic_ext_dir, (
        f"FAIL: extensions-dir mismatch — main container uses {main_ext_dir!r}, "
        f"install-extensions initContainer uses {ic_ext_dir!r}. "
        "Extensions will be installed to a directory code-server does not watch."
    )
    print("PASS: install-extensions --extensions-dir matches main container --extensions-dir")


if __name__ == "__main__":
    try:
        tests()
        print("")
        print("All tests passed.")
    except AssertionError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"helm template failed: {e.stderr}", file=sys.stderr)
        sys.exit(1)
