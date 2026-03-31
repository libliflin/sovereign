#!/usr/bin/env python3
"""check-limits.py — validates that every container has resource requests and limits.

Reads helm-rendered YAML from stdin (may contain multiple documents).
Exits 0 if all containers in Deployment/StatefulSet/DaemonSet/Job/CronJob specs
have both resources.requests and resources.limits set.
Exits 1 and prints a list of failing containers if any are missing.

Usage:
    helm template platform/charts/<name>/ | python3 scripts/check-limits.py
"""

import sys
import yaml


def check_container(container, doc_kind, doc_name, failures):
    """Check a single container dict for resource requests and limits."""
    name = container.get("name", "<unnamed>")
    resources = container.get("resources") or {}
    requests = resources.get("requests")
    limits = resources.get("limits")
    missing = []
    if not requests:
        missing.append("resources.requests")
    if not limits:
        missing.append("resources.limits")
    if missing:
        failures.append(
            f"{doc_kind}/{doc_name} container={name}: missing {', '.join(missing)}"
        )


def check_pod_spec(pod_spec, doc_kind, doc_name, failures):
    """Walk containers and initContainers in a pod spec."""
    for container in pod_spec.get("containers") or []:
        check_container(container, doc_kind, doc_name, failures)
    for container in pod_spec.get("initContainers") or []:
        check_container(container, doc_kind, doc_name, failures)


WORKLOAD_KINDS = {"Deployment", "StatefulSet", "DaemonSet", "Job"}


def main():
    raw = sys.stdin.read()
    failures = []

    try:
        docs = list(yaml.safe_load_all(raw))
    except yaml.YAMLError as exc:
        print(f"ERROR: failed to parse YAML from stdin: {exc}", file=sys.stderr)
        sys.exit(2)

    for doc in docs:
        if not isinstance(doc, dict):
            continue
        kind = doc.get("kind", "")
        name = (doc.get("metadata") or {}).get("name", "<unnamed>")

        if kind in WORKLOAD_KINDS:
            pod_spec = (
                doc.get("spec", {})
                .get("template", {})
                .get("spec", {})
            )
            check_pod_spec(pod_spec, kind, name, failures)

        elif kind == "CronJob":
            pod_spec = (
                doc.get("spec", {})
                .get("jobTemplate", {})
                .get("spec", {})
                .get("template", {})
                .get("spec", {})
            )
            check_pod_spec(pod_spec, kind, name, failures)

    if failures:
        print("RESOURCE LIMITS CHECK FAILED — containers missing requests/limits:")
        for f in failures:
            print(f"  {f}")
        sys.exit(1)

    print(f"OK: all containers have resource requests and limits")
    sys.exit(0)


if __name__ == "__main__":
    main()
