#!/usr/bin/env bash
# bootstrap/bootstrap.sh — VPS provisioning bootstrap (stub)
#
# Full implementation is planned. Until then:
#   - For local development: ./cluster/kind/bootstrap.sh
#   - For platform deployment on an existing cluster: ./platform/deploy.sh
#
# This stub exits with a clear message rather than "command not found".

set -euo pipefail

echo "BOOTSTRAP NOT IMPLEMENTED: VPS provisioning is not yet available."
echo ""
echo "For local development (no cloud account required):"
echo "  ./cluster/kind/bootstrap.sh"
echo ""
echo "For platform deployment on an existing cluster:"
echo "  ./platform/deploy.sh --cluster-values cluster-values.yaml"
echo ""
echo "See docs/quickstart.md for the full walkthrough."
exit 1
