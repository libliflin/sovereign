#!/usr/bin/env bash
# bootstrap/verify.sh — post-bootstrap cluster verification (stub)
#
# Full implementation is planned. Until then, run manual checks:
#   kubectl get nodes
#   kubectl get pods -A | grep -v Running | grep -v Completed

set -euo pipefail

echo "VERIFY NOT IMPLEMENTED: post-bootstrap verification is not yet available."
echo ""
echo "Manual cluster check:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A | grep -v Running | grep -v Completed"
exit 1
