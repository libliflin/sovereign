#!/usr/bin/env python3
"""
test_contract_validator.py
Tests for contract/validate.py — run with: python3 test_contract_validator.py
Format: PASS: <description> lines, ending with "All tests passed."
"""
import subprocess
import sys
import os

# Locate repo root relative to this test file
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
VALIDATOR = os.path.join(REPO_ROOT, "contract", "validate.py")
FIXTURES = os.path.join(REPO_ROOT, "contract", "v1", "tests")


def run_validator(fixture_name):
    path = os.path.join(FIXTURES, fixture_name)
    result = subprocess.run(
        [sys.executable, VALIDATOR, path],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def test_valid_fixture_passes():
    code, out = run_validator("valid.yaml")
    assert code == 0, f"valid.yaml should exit 0, got {code}. Output:\n{out}"
    assert "CONTRACT VALID" in out
    print("PASS: valid fixture exits 0")


def test_egress_not_blocked_fails():
    code, out = run_validator("invalid-egress-not-blocked.yaml")
    assert code == 1, f"invalid-egress-not-blocked.yaml should exit 1, got {code}"
    assert "AUTARKY VIOLATION" in out
    print("PASS: egress-not-blocked fixture exits 1 with AUTARKY VIOLATION")


def test_duplicate_key_bypass_rejected():
    """
    Adversarial: a contract with externalEgressBlocked: false followed by
    externalEgressBlocked: true must be rejected, not passed via last-value-wins.
    A last-value-wins parser would return true and issue CONTRACT VALID — that
    is the bypass this test guards against.
    """
    code, out = run_validator("invalid-duplicate-key-bypass.yaml")
    assert code == 1, (
        f"Duplicate key bypass fixture should exit 1, got {code}.\n"
        f"Output:\n{out}\n"
        f"This means the validator accepted a contract with duplicate keys — "
        f"the bypass is open. Fix parse_yaml_flat to reject duplicate keys."
    )
    assert "DUPLICATE KEY" in out, (
        f"Expected DUPLICATE KEY in output, got:\n{out}"
    )
    print("PASS: duplicate key bypass rejected with DUPLICATE KEY error")


def test_missing_storage_fails():
    code, out = run_validator("invalid-missing-storage.yaml")
    assert code == 1, f"invalid-missing-storage.yaml should exit 1, got {code}"
    assert "MISSING" in out
    print("PASS: missing storage fields exit 1 with MISSING error")


def test_no_imageregistry_fails():
    code, out = run_validator("invalid-no-imageregistry.yaml")
    assert code == 1, f"invalid-no-imageregistry.yaml should exit 1, got {code}"
    print("PASS: missing imageRegistry exits 1")


def test_no_storageclass_fails():
    code, out = run_validator("invalid-no-storageclass.yaml")
    assert code == 1, f"invalid-no-storageclass.yaml should exit 1, got {code}"
    print("PASS: missing storageClass exits 1")


if __name__ == "__main__":
    test_valid_fixture_passes()
    test_egress_not_blocked_fails()
    test_duplicate_key_bypass_rejected()
    test_missing_storage_fails()
    test_no_imageregistry_fails()
    test_no_storageclass_fails()
    print("All tests passed.")
