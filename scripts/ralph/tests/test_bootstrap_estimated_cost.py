#!/usr/bin/env python3
"""
Tests for bootstrap/bootstrap.sh --estimated-cost

Runs the actual shell script via subprocess so the tests exercise the real
implementation rather than a re-implementation. Plain Python, no pytest.
"""
import os
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BOOTSTRAP_SCRIPT = os.path.join(REPO_ROOT, "bootstrap", "bootstrap.sh")
EXAMPLE_CONFIG = os.path.join(REPO_ROOT, "bootstrap", "config.yaml.example")


def run_bootstrap(*args, config_content=None, use_real_config=False):
    """Run bootstrap.sh with a temp config and return (stdout, stderr, returncode)."""
    with tempfile.TemporaryDirectory() as tmpdir:
        if config_content is not None:
            config_path = os.path.join(tmpdir, "config.yaml")
            with open(config_path, "w") as f:
                f.write(config_content)
            # Symlink so the script finds it relative to SCRIPT_DIR
            script_dir = os.path.dirname(BOOTSTRAP_SCRIPT)
            # We patch the CONFIG_FILE by symlinking/copying into place temporarily.
            # Easier: point CONFIG_FILE via environment is not possible since it's hardcoded.
            # Instead, copy the temp config over the real location temporarily.
            real_config = os.path.join(script_dir, "config.yaml")
            backup = None
            if os.path.exists(real_config):
                backup = real_config + ".bak"
                os.rename(real_config, backup)
            try:
                import shutil
                shutil.copy(config_path, real_config)
                result = subprocess.run(
                    ["bash", BOOTSTRAP_SCRIPT] + list(args),
                    capture_output=True, text=True, cwd=REPO_ROOT
                )
                return result.stdout, result.stderr, result.returncode
            finally:
                os.remove(real_config)
                if backup:
                    os.rename(backup, real_config)
        elif use_real_config:
            result = subprocess.run(
                ["bash", BOOTSTRAP_SCRIPT] + list(args),
                capture_output=True, text=True, cwd=REPO_ROOT
            )
            return result.stdout, result.stderr, result.returncode
        else:
            # No config: remove any existing one temporarily
            real_config = os.path.join(os.path.dirname(BOOTSTRAP_SCRIPT), "config.yaml")
            backup = None
            if os.path.exists(real_config):
                backup = real_config + ".bak"
                os.rename(real_config, backup)
            try:
                result = subprocess.run(
                    ["bash", BOOTSTRAP_SCRIPT] + list(args),
                    capture_output=True, text=True, cwd=REPO_ROOT
                )
                return result.stdout, result.stderr, result.returncode
            finally:
                if backup:
                    os.rename(backup, real_config)


def test_no_args():
    """No arguments prints usage and exits 1."""
    stdout, stderr, rc = run_bootstrap(use_real_config=True)
    assert rc == 1, f"Expected exit 1, got {rc}"
    assert "Usage:" in stdout, f"Expected usage in stdout, got: {stdout!r}"
    print("PASS: no-args exits 1 with usage")


def test_unknown_flag():
    """Unknown flag prints UNKNOWN FLAG and usage, exits 1."""
    stdout, stderr, rc = run_bootstrap("--banana", use_real_config=True)
    assert rc == 1, f"Expected exit 1, got {rc}"
    assert "UNKNOWN FLAG" in stdout, f"Expected UNKNOWN FLAG, got: {stdout!r}"
    print("PASS: unknown flag exits 1 with UNKNOWN FLAG")


def test_confirm_charges_stubbed():
    """--confirm-charges exits 1 with BOOTSTRAP NOT IMPLEMENTED."""
    stdout, stderr, rc = run_bootstrap("--confirm-charges", use_real_config=True)
    assert rc == 1, f"Expected exit 1, got {rc}"
    assert "BOOTSTRAP NOT IMPLEMENTED" in stdout, f"Expected NOT IMPLEMENTED, got: {stdout!r}"
    print("PASS: --confirm-charges exits 1 with BOOTSTRAP NOT IMPLEMENTED")


def test_dry_run_stubbed():
    """--dry-run exits 1 with BOOTSTRAP NOT IMPLEMENTED."""
    stdout, stderr, rc = run_bootstrap("--dry-run", use_real_config=True)
    assert rc == 1, f"Expected exit 1, got {rc}"
    assert "BOOTSTRAP NOT IMPLEMENTED" in stdout, f"Expected NOT IMPLEMENTED, got: {stdout!r}"
    print("PASS: --dry-run exits 1 with BOOTSTRAP NOT IMPLEMENTED")


def test_missing_config():
    """--estimated-cost without config.yaml exits 1 with CONFIG NOT FOUND."""
    stdout, stderr, rc = run_bootstrap("--estimated-cost")
    assert rc == 1, f"Expected exit 1, got {rc}"
    assert "CONFIG NOT FOUND" in stdout, f"Expected CONFIG NOT FOUND, got: {stdout!r}"
    print("PASS: missing config.yaml exits 1 with CONFIG NOT FOUND")


def test_hetzner_cx32_default():
    """--estimated-cost with hetzner/cx32/3 nodes prints expected table, exits 0."""
    config = """
provider: "hetzner"
nodes:
  count: 3
  serverType: "cx32"
"""
    stdout, stderr, rc = run_bootstrap("--estimated-cost", config_content=config)
    assert rc == 0, f"Expected exit 0, got {rc}\nstdout: {stdout}\nstderr: {stderr}"
    assert "hetzner" in stdout, f"Expected provider in output: {stdout!r}"
    assert "cx32" in stdout, f"Expected server type in output: {stdout!r}"
    assert "8.21" in stdout, f"Expected unit price in output: {stdout!r}"
    assert "24.63" in stdout, f"Expected total in output: {stdout!r}"
    assert "--confirm-charges" in stdout, f"Expected confirm-charges hint in output: {stdout!r}"
    print("PASS: hetzner/cx32/3 nodes prints correct cost table")


def test_generic_provider():
    """--estimated-cost with generic provider prints $0, exits 0."""
    config = """
provider: "generic"
nodes:
  count: 5
  serverType: "custom"
"""
    stdout, stderr, rc = run_bootstrap("--estimated-cost", config_content=config)
    assert rc == 0, f"Expected exit 0, got {rc}\nstdout: {stdout}\nstderr: {stderr}"
    assert "generic" in stdout, f"Expected generic in output: {stdout!r}"
    assert "$0.00" in stdout, f"Expected $0 in output: {stdout!r}"
    print("PASS: generic provider prints $0.00 cost")


def test_unknown_provider():
    """--estimated-cost with unknown provider exits 1 with UNKNOWN PROVIDER."""
    config = """
provider: "linode"
nodes:
  count: 3
  serverType: "g6-standard-2"
"""
    stdout, stderr, rc = run_bootstrap("--estimated-cost", config_content=config)
    assert rc == 1, f"Expected exit 1, got {rc}"
    assert "UNKNOWN PROVIDER" in stdout, f"Expected UNKNOWN PROVIDER, got: {stdout!r}"
    assert "linode" in stdout, f"Expected provider name in error: {stdout!r}"
    print("PASS: unknown provider exits 1 with UNKNOWN PROVIDER")


def test_unknown_server_type():
    """--estimated-cost with unknown serverType exits 1 with UNKNOWN SERVER TYPE."""
    config = """
provider: "hetzner"
nodes:
  count: 3
  serverType: "cx99"
"""
    stdout, stderr, rc = run_bootstrap("--estimated-cost", config_content=config)
    assert rc == 1, f"Expected exit 1, got {rc}"
    assert "UNKNOWN SERVER TYPE" in stdout, f"Expected UNKNOWN SERVER TYPE, got: {stdout!r}"
    assert "cx99" in stdout, f"Expected bad server type in error: {stdout!r}"
    print("PASS: unknown serverType exits 1 with UNKNOWN SERVER TYPE")


def test_digitalocean():
    """--estimated-cost with digitalocean/s-4vcpu-8gb prints correct price, exits 0."""
    config = """
provider: "digitalocean"
nodes:
  count: 3
  serverType: "s-4vcpu-8gb"
"""
    stdout, stderr, rc = run_bootstrap("--estimated-cost", config_content=config)
    assert rc == 0, f"Expected exit 0, got {rc}\nstdout: {stdout}\nstderr: {stderr}"
    assert "digitalocean" in stdout
    assert "48.00" in stdout, f"Expected unit price $48.00: {stdout!r}"
    assert "144.00" in stdout, f"Expected total $144.00: {stdout!r}"
    print("PASS: digitalocean/s-4vcpu-8gb/3 nodes prints correct cost table")


def test_default_server_type_when_omitted():
    """--estimated-cost with no serverType defaults to first known type, exits 0."""
    config = """
provider: "hetzner"
nodes:
  count: 3
"""
    stdout, stderr, rc = run_bootstrap("--estimated-cost", config_content=config)
    assert rc == 0, f"Expected exit 0, got {rc}\nstdout: {stdout}\nstderr: {stderr}"
    # Default should be cx22 (first in the hetzner table)
    assert "cx22" in stdout, f"Expected default cx22 when serverType omitted: {stdout!r}"
    print("PASS: missing serverType defaults to cx22")


def test_node_count_from_config():
    """Node count is read from config.yaml nodes.count."""
    config = """
provider: "hetzner"
nodes:
  count: 5
  serverType: "cx32"
"""
    stdout, stderr, rc = run_bootstrap("--estimated-cost", config_content=config)
    assert rc == 0, f"Expected exit 0, got {rc}"
    assert "5" in stdout, f"Expected count=5 in output: {stdout!r}"
    # 5 * 8.21 = 41.05
    assert "41.05" in stdout, f"Expected total ~41.05 in output: {stdout!r}"
    print("PASS: nodes.count=5 is read and total is correct")


def test_runs_from_any_cwd():
    """bootstrap.sh --estimated-cost works when invoked from inside the bootstrap/ dir."""
    bootstrap_dir = os.path.dirname(BOOTSTRAP_SCRIPT)
    # Ensure config.yaml exists (use example)
    real_config = os.path.join(bootstrap_dir, "config.yaml")
    had_config = os.path.exists(real_config)
    if not had_config:
        import shutil
        shutil.copy(EXAMPLE_CONFIG, real_config)
    try:
        result = subprocess.run(
            ["bash", "bootstrap.sh", "--estimated-cost"],
            capture_output=True, text=True, cwd=bootstrap_dir
        )
        assert result.returncode == 0, (
            f"Expected exit 0 when run from bootstrap/ dir, got {result.returncode}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert "hetzner" in result.stdout, f"Expected provider in output: {result.stdout!r}"
    finally:
        if not had_config and os.path.exists(real_config):
            os.remove(real_config)
    print("PASS: runs correctly when invoked from inside bootstrap/ directory")


if __name__ == "__main__":
    tests = [
        test_no_args,
        test_unknown_flag,
        test_confirm_charges_stubbed,
        test_dry_run_stubbed,
        test_missing_config,
        test_hetzner_cx32_default,
        test_generic_provider,
        test_unknown_provider,
        test_unknown_server_type,
        test_digitalocean,
        test_default_server_type_when_omitted,
        test_node_count_from_config,
        test_runs_from_any_cwd,
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
