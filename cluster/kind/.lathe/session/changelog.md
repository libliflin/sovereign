# Verification — Cycle 1, Round 1 (Verifier)

## What I compared
Goal: fix the contradiction between `bootstrap.sh`'s "Next step: platform/deploy.sh" and the README's `helm install test-release cluster/kind/charts/sealed-secrets/`.

Builder's diff: replaced the `platform/deploy.sh` line with the `helm install` command plus `kind delete cluster` tear-down. Dynamic `kind-${CLUSTER_NAME}` (defaults to `sovereign-test`).

I ran:
- `shellcheck -S error cluster/kind/bootstrap.sh` → EXIT: 0
- `bash cluster/kind/bootstrap.sh --dry-run` → clean 4-line preview, no mention of deploy.sh
- Side-by-side comparison of terminal output vs README Option A steps 3 and 4

## What's here, what was asked
Core contradiction is fixed. The `platform/deploy.sh` reference is gone; the terminal now directs to `helm install`. The dynamic `${CLUSTER_NAME}` correctly resolves to `sovereign-test` for the default path, matching the README's hardcoded `kind-sovereign-test`.

Gap found: README step 3 shows two commands — `helm install ... --wait` followed immediately by `kubectl --context kind-sovereign-test get pods -n sealed-secrets`. The builder's terminal output included the helm install and the tear-down but skipped the `kubectl get pods` verification step. A developer copy-pasting from the terminal would install but never confirm the pods are running — the part of the smoke test that actually tells you it worked.

## What I added
Added the missing `kubectl get pods` line to `bootstrap.sh`'s terminal output so it fully matches README step 3:

```
Smoke test:  helm install test-release cluster/kind/charts/sealed-secrets/ \
               --namespace sealed-secrets --create-namespace \
               --kube-context kind-${CLUSTER_NAME} --wait
             kubectl --context kind-${CLUSTER_NAME} get pods -n sealed-secrets
Tear down:   kind delete cluster --name ${CLUSTER_NAME}
```

Files: `cluster/kind/bootstrap.sh`
Commit: `d09f9fc`

## Notes for the goal-setter
None. The fix is tight, shellcheck passes, the terminal output now mirrors the README's step 3 exactly.
