#!/usr/bin/env python3
"""Tests for backstage Keycloak OIDC chart changes.

Verifies:
  - Guest block is absent from rendered configmap
  - OIDC provider is rendered with correct metadataUrl / clientId
  - clientSecret in configmap uses ${BACKSTAGE_KEYCLOAK_CLIENT_SECRET} substitution
  - BACKSTAGE_KEYCLOAK_CLIENT_SECRET env var is wired via secretKeyRef
  - required guard fires when keycloak.clientSecret is empty
  - ci/ci-values.yaml satisfies the required guard (helm template succeeds)
"""

import os
import subprocess
import sys
import yaml

REPO_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..")
)
CHART_DIR = os.path.join(REPO_ROOT, "platform", "charts", "backstage")
CI_VALUES = os.path.join(CHART_DIR, "ci", "ci-values.yaml")


def helm_template(*extra_args):
    """Run helm template on the backstage chart; return stdout, raise on error."""
    cmd = ["helm", "template", CHART_DIR] + list(extra_args)
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def test_guest_block_absent():
    """OIDC replaces guest auth: dangerouslyAllowOutsideDevelopment must not appear."""
    rc, out, err = helm_template("-f", CI_VALUES)
    assert rc == 0, f"helm template failed: {err}"
    assert "dangerouslyAllowOutsideDevelopment" not in out, (
        "guest auth block still present — OIDC migration incomplete"
    )
    assert "guest:" not in out, "guest provider block still present"
    print("PASS: guest block absent from rendered output")


def test_oidc_provider_rendered():
    """OIDC provider block must be rendered with metadataUrl and clientId."""
    rc, out, err = helm_template("-f", CI_VALUES)
    assert rc == 0, f"helm template failed: {err}"
    assert "oidc:" in out, "oidc provider block not found in rendered output"
    assert "metadataUrl:" in out, "metadataUrl not rendered in OIDC block"
    assert "clientId:" in out, "clientId not rendered in OIDC block"
    assert "emailMatchingUserEntityProfileEmail" in out, (
        "signIn resolver not rendered"
    )
    print("PASS: OIDC provider block rendered correctly")


def test_oidc_metadata_url_format():
    """metadataUrl must follow Keycloak well-known discovery format."""
    rc, out, _ = helm_template("-f", CI_VALUES)
    assert rc == 0
    # Parse all YAML docs to find the ConfigMap
    docs = [d for d in yaml.safe_load_all(out) if d]
    configmap = next(
        (d for d in docs if d.get("kind") == "ConfigMap"),
        None,
    )
    assert configmap is not None, "ConfigMap not found in rendered output"
    app_config_raw = configmap["data"].get("app-config.production.yaml", "")
    app_config = yaml.safe_load(app_config_raw)
    metadata_url = (
        app_config["auth"]["providers"]["oidc"]["production"]["metadataUrl"]
    )
    assert "/.well-known/openid-configuration" in metadata_url, (
        f"metadataUrl missing well-known path: {metadata_url}"
    )
    assert "/realms/" in metadata_url, (
        f"metadataUrl missing /realms/ path: {metadata_url}"
    )
    print(f"PASS: metadataUrl format correct: {metadata_url}")


def test_client_secret_env_var_wired():
    """Deployment must inject BACKSTAGE_KEYCLOAK_CLIENT_SECRET from secretKeyRef."""
    rc, out, _ = helm_template("-f", CI_VALUES)
    assert rc == 0
    docs = [d for d in yaml.safe_load_all(out) if d]
    deployment = next(
        (d for d in docs if d.get("kind") == "Deployment"),
        None,
    )
    assert deployment is not None, "Deployment not found in rendered output"
    containers = (
        deployment["spec"]["template"]["spec"].get("containers", [])
    )
    env_vars = {}
    for c in containers:
        for e in c.get("env", []):
            env_vars[e["name"]] = e
    assert "BACKSTAGE_KEYCLOAK_CLIENT_SECRET" in env_vars, (
        "BACKSTAGE_KEYCLOAK_CLIENT_SECRET env var missing from Deployment"
    )
    secret_ref = env_vars["BACKSTAGE_KEYCLOAK_CLIENT_SECRET"].get("valueFrom", {}).get(
        "secretKeyRef", {}
    )
    assert secret_ref.get("key") == "clientSecret", (
        f"secretKeyRef.key must be 'clientSecret', got: {secret_ref.get('key')}"
    )
    print("PASS: BACKSTAGE_KEYCLOAK_CLIENT_SECRET wired via secretKeyRef")


def test_client_secret_uses_env_substitution():
    """ConfigMap clientSecret must use ${BACKSTAGE_KEYCLOAK_CLIENT_SECRET} not a literal value."""
    rc, out, _ = helm_template("-f", CI_VALUES)
    assert rc == 0
    docs = [d for d in yaml.safe_load_all(out) if d]
    configmap = next(
        (d for d in docs if d.get("kind") == "ConfigMap"),
        None,
    )
    assert configmap is not None
    app_config_raw = configmap["data"]["app-config.production.yaml"]
    assert "${BACKSTAGE_KEYCLOAK_CLIENT_SECRET}" in app_config_raw, (
        "ConfigMap clientSecret must use ${BACKSTAGE_KEYCLOAK_CLIENT_SECRET} substitution, "
        "not a literal value — literal secrets in ConfigMaps are plaintext in etcd"
    )
    print("PASS: clientSecret uses ${BACKSTAGE_KEYCLOAK_CLIENT_SECRET} env substitution")


def test_required_guard_fires_on_empty_client_secret():
    """helm template must fail when keycloak.clientSecret is empty (the default)."""
    rc, out, err = helm_template()  # no ci-values — uses default clientSecret: ""
    assert rc != 0, (
        "helm template succeeded with empty clientSecret — required guard is not enforcing. "
        "An operator who deploys with defaults will get broken OIDC auth silently."
    )
    assert "keycloak.clientSecret must be set" in err, (
        f"required guard message not in stderr: {err}"
    )
    print("PASS: required guard fires with empty clientSecret")


def test_ci_values_satisfy_required_guard():
    """ci/ci-values.yaml must provide a clientSecret that satisfies the required guard."""
    assert os.path.exists(CI_VALUES), (
        f"ci/ci-values.yaml missing at {CI_VALUES} — helm lint and ha-gate.sh will fail"
    )
    rc, out, err = helm_template("-f", CI_VALUES)
    assert rc == 0, (
        f"helm template failed even with ci-values: {err}"
    )
    print("PASS: ci/ci-values.yaml satisfies required guard")


if __name__ == "__main__":
    tests = [
        test_guest_block_absent,
        test_oidc_provider_rendered,
        test_oidc_metadata_url_format,
        test_client_secret_env_var_wired,
        test_client_secret_uses_env_substitution,
        test_required_guard_fires_on_empty_client_secret,
        test_ci_values_satisfy_required_guard,
    ]
    failed = []
    for t in tests:
        try:
            t()
        except Exception as e:
            print(f"FAIL: {t.__name__}: {e}")
            failed.append(t.__name__)
    if failed:
        print(f"\n{len(failed)} test(s) failed: {', '.join(failed)}")
        sys.exit(1)
    print("\nAll tests passed.")
