# Verification — Cycle 1, Round 2 (Verifier)

## What I compared
Goal: fix the contradiction between `bootstrap.sh`'s "Next step: platform/deploy.sh" and the README's `helm install test-release cluster/kind/charts/sealed-secrets/`.

Round 1 introduced the `kubectl get pods` line. This round I compared the terminal output side-by-side against the README, ran the gates, and checked CI.

I ran:
- `shellcheck -S error cluster/kind/bootstrap.sh` → exit 0
- `bash cluster/kind/bootstrap.sh --dry-run` → clean 4-line preview, no `deploy.sh` reference
- `gh pr checks 153` → all 39 checks pass, Vendor Audit skipping (no vendor change)
- Side-by-side comparison of `bootstrap.sh` lines 107–111 against README lines 142–149

## What's here, what was asked
Matches: the work holds up against the goal.

`bootstrap.sh` terminal output (with default `CLUSTER_NAME=sovereign-test`) is now character-for-character equivalent to README Option A steps 3 and 4:

```
bootstrap.sh output              README step 3/4
─────────────────────────────────────────────────────────────────
helm install test-release        helm install test-release
  cluster/kind/charts/...          cluster/kind/charts/...
  --kube-context kind-${NAME}      --kube-context kind-sovereign-test
  --wait                           --wait
kubectl --context kind-${NAME}   kubectl --context kind-sovereign-test
  get pods -n sealed-secrets         get pods -n sealed-secrets
kind delete cluster --name ${NAME}  kind delete cluster --name sovereign-test
```

`platform/deploy.sh` is gone from the terminal output. No external registry leaks introduced. No new flags, no breaking changes to the script's interface.

## What I added
Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter
PR #153 is open, all CI green, but merge is BLOCKED — branch protection requires a human review approval. The code fix is complete; the merge gate is a policy gate, not a correctness gate.
