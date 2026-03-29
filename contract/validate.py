#!/usr/bin/env python3
"""
contract/validate.py
Validates a cluster-values.yaml against the sovereign cluster contract v1.
Exits 0 if valid. Exits 1 with clear error messages if invalid.

Uses stdlib only — no external dependencies.

Usage:
  python3 contract/validate.py <cluster-values.yaml>
"""
import re
import sys

REQUIRED_FIELDS = [
    "runtime.domain",
    "runtime.imageRegistry.internal",
    "storage.block.storageClassName",
    "storage.file.storageClassName",
    "storage.object.endpoint",
    "storage.object.credentialsSecret",
    "network.ingressClass",
    "pki.clusterIssuer",
]

CONST_TRUE_FIELDS = [
    "network.networkPolicyEnforced",
    "autarky.externalEgressBlocked",
    "autarky.imagesFromInternalRegistryOnly",
]

EXPECTED_API_VERSION = "sovereign.dev/cluster/v1"


def parse_yaml_flat(text: str) -> dict:
    """
    Minimal YAML parser for the narrow cluster-values.yaml format.
    Handles: nested key: value pairs via indentation.
    Does not handle: lists, multiline strings, anchors, tags.
    Returns a flat dict of dot-separated paths → string values.
    """
    result = {}
    path_stack = []   # (indent_level, key)

    for raw_line in text.splitlines():
        # Strip comments and skip blank lines
        line = raw_line.split("#")[0].rstrip()
        if not line.strip():
            continue

        indent = len(line) - len(line.lstrip())
        stripped = line.strip()

        if ":" not in stripped:
            continue

        colon_pos = stripped.index(":")
        key = stripped[:colon_pos].strip()
        value = stripped[colon_pos + 1:].strip()

        # Pop stack until we're at the right indent level
        while path_stack and path_stack[-1][0] >= indent:
            path_stack.pop()

        path_stack.append((indent, key))
        dotpath = ".".join(k for _, k in path_stack)

        if value:
            result[dotpath] = value

    return result


def validate(values_path: str) -> list:
    errors = []

    with open(values_path) as f:
        text = f.read()

    flat = parse_yaml_flat(text)

    # Check apiVersion
    api_version = flat.get("apiVersion", "")
    if api_version != EXPECTED_API_VERSION:
        errors.append(
            f"apiVersion must be '{EXPECTED_API_VERSION}', got '{api_version!r}'"
        )

    # Check required fields are present and non-empty
    for field in REQUIRED_FIELDS:
        value = flat.get(field)
        # imageRegistry.internal may be empty string during bootstrap — that's OK
        if value is None and field != "runtime.imageRegistry.internal":
            errors.append(f"MISSING required field: {field}")

    # Check const: true fields
    for field in CONST_TRUE_FIELDS:
        value = flat.get(field)
        if value is None:
            errors.append(f"MISSING required invariant field: {field}")
        elif value.lower() != "true":
            errors.append(
                f"AUTARKY VIOLATION: {field} must be true (got {value!r}). "
                f"This is not configurable — it is an invariant of the sovereign contract."
            )

    return errors


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 contract/validate.py <cluster-values.yaml>")
        sys.exit(1)

    values_path = sys.argv[1]
    errors = validate(values_path)

    if errors:
        print(f"CONTRACT VALIDATION FAILED: {values_path}")
        print()
        for error in errors:
            print(f"  x {error}")
        print()
        print("This cluster does not satisfy the sovereign contract.")
        sys.exit(1)
    else:
        print(f"CONTRACT VALID: {values_path}")
        sys.exit(0)


if __name__ == "__main__":
    main()
