#!/usr/bin/env bash
# vendor/audit.sh — License and distroless audit for VENDORS.yaml
# Reads vendor/VENDORS.yaml and prints a report:
#   - License violations (license_allows_vendor: false without alternative)
#   - Distroless-incompatible services
#   - Deprecated entries with alternatives
# Exits non-zero if any entry has license_allows_vendor: false without an alternative.
#
# Usage: vendor/audit.sh [--dry-run]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDORS_FILE="$REPO_ROOT/vendor/VENDORS.yaml"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] Would audit: $VENDORS_FILE"
  echo "[DRY RUN] Would exit non-zero if any entry has license_allows_vendor: false without an alternative."
  exit 0
fi

if [[ ! -f "$VENDORS_FILE" ]]; then
  echo "ERROR: $VENDORS_FILE not found" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required" >&2
  exit 1
fi

VENDORS_FILE_PATH="$VENDORS_FILE"
python3 - "$VENDORS_FILE_PATH" << 'PYEOF'
import sys
import os

vendors_file = sys.argv[1]

# Parse VENDORS.yaml using a minimal YAML parser (avoid PyYAML dependency)
# The file is structured enough that we can parse it manually
vendors = []
current = {}

with open(vendors_file) as f:
    lines = f.readlines()

in_vendors = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("vendors:"):
        in_vendors = True
        continue
    if not in_vendors:
        continue
    if stripped.startswith("# ") or stripped == "" or stripped.startswith("#"):
        continue
    if stripped.startswith("- name:"):
        if current:
            vendors.append(current)
        current = {"name": stripped.split(":", 1)[1].strip()}
    elif ":" in stripped and not stripped.startswith("-"):
        key, _, val = stripped.partition(":")
        key = key.strip()
        val = val.strip()
        # Remove inline comments
        if " #" in val:
            val = val[:val.index(" #")].strip()
        # Parse bool
        if val == "true":
            val = True
        elif val == "false":
            val = False
        # Remove surrounding quotes
        elif val.startswith('"') and val.endswith('"'):
            val = val[1:-1]
        current[key] = val

if current:
    vendors.append(current)

# Audit
license_violations = []
license_ok_deprecated = []
distroless_incompatible = []
distroless_partial = []
deprecated_entries = []
exit_code = 0

for v in vendors:
    name = v.get("name", "?")
    allows = v.get("license_allows_vendor", True)
    alternative = v.get("alternative", "")
    deprecated = v.get("deprecated", False)
    distroless = v.get("distroless_compatible", "?")
    reason = v.get("deprecated_reason", "")
    license_spdx = v.get("license_spdx", "?")

    # License check
    if allows is False or allows == "false":
        if not alternative or alternative == "":
            license_violations.append({
                "name": name,
                "license": license_spdx,
                "reason": "license_allows_vendor: false but no alternative specified — BLOCKED"
            })
            exit_code = 1
        else:
            license_ok_deprecated.append({
                "name": name,
                "license": license_spdx,
                "alternative": alternative,
                "reason": reason
            })

    # Deprecated check (separate from license)
    if deprecated is True or deprecated == "true":
        if {"name": name, "license": license_spdx, "alternative": alternative, "reason": reason} not in license_ok_deprecated:
            deprecated_entries.append({
                "name": name,
                "reason": reason,
                "alternative": alternative
            })

    # Distroless check
    if distroless == "no":
        distroless_incompatible.append({"name": name, "note": "incompatible — requires shell or privileged runtime"})
    elif distroless == "partial":
        distroless_partial.append({"name": name, "base": v.get("distroless_base", "none")})

# Print report
total = len(vendors)
print(f"=== Sovereign Vendor Audit — {total} packages ===")
print()

# License violations (BLOCKING)
print(f"── License Issues ──────────────────────────────────────────────────")
if not license_violations and not license_ok_deprecated:
    print("  ✓ No license violations")
else:
    if license_violations:
        print(f"  BLOCKED ({len(license_violations)} — exit non-zero):")
        for v in license_violations:
            print(f"    ✗ {v['name']} ({v['license']}): {v['reason']}")
    if license_ok_deprecated:
        print(f"  Non-vendorable (has alternative, not blocked):")
        for v in license_ok_deprecated:
            print(f"    ⚠ {v['name']} ({v['license']}) → use {v['alternative']}")
            if v['reason']:
                print(f"      reason: {v['reason'][:80]}")
print()

# Distroless status
print(f"── Distroless Status ───────────────────────────────────────────────")
compatible_count = total - len(distroless_incompatible) - len(distroless_partial)
print(f"  ✓ Compatible: {compatible_count}/{total}")
if distroless_partial:
    print(f"  ~ Partial ({len(distroless_partial)}) — review base image:")
    for v in distroless_partial:
        print(f"    ~ {v['name']} → {v['base']}")
if distroless_incompatible:
    print(f"  ✗ Incompatible ({len(distroless_incompatible)}) — must add deprecated entry with migration plan:")
    for v in distroless_incompatible:
        print(f"    ✗ {v['name']}: {v['note']}")
print()

# Deprecated entries
print(f"── Deprecated Entries ──────────────────────────────────────────────")
if not deprecated_entries and not license_ok_deprecated:
    print("  ✓ No deprecated entries")
else:
    all_deprecated = list(license_ok_deprecated) + [
        {"name": v["name"], "reason": v["reason"], "alternative": v["alternative"]}
        for v in deprecated_entries
    ]
    for v in all_deprecated:
        alt = v.get("alternative", "")
        reason_short = v.get("reason", "")[:80]
        print(f"  ⚠ {v['name']} → {alt if alt else 'NO ALTERNATIVE SPECIFIED'}")
        if reason_short:
            print(f"    {reason_short}")
print()

# Summary
if exit_code == 0:
    print("✓ Audit passed — no blocking violations")
else:
    print(f"✗ Audit FAILED — {len(license_violations)} blocking license violation(s)")
    sys.exit(1)
PYEOF