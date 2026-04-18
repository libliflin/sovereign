# Verification — Cycle 1, Round 3 (Verifier)

## What I compared
Goal: fix the contradiction between `bootstrap.sh`'s "Next step: platform/deploy.sh" and the README's `helm install test-release cluster/kind/charts/sealed-secrets/`.

I ran:
- `shellcheck -S error cluster/kind/bootstrap.sh` → exit 0
- `bash cluster/kind/bootstrap.sh --dry-run` → 4-line clean preview, exits before the smoke test / teardown lines (correct — dry-run should not show them)
- `gh pr view 153` → state: MERGED; fix is in main as `ec8323d`
- `gh pr checks 153` → all CI jobs pass
- Side-by-side read of `bootstrap.sh` lines 107–111 against README lines 142–149

## What's here, what was asked
Matches: the work holds up against the goal.

With the default `CLUSTER_NAME=sovereign-test`, `bootstrap.sh` terminal output is:
```
==> Smoke test:  helm install test-release cluster/kind/charts/sealed-secrets/ \
==>                --namespace sealed-secrets --create-namespace \
==>                --kube-context kind-sovereign-test --wait
==>              kubectl --context kind-sovereign-test get pods -n sealed-secrets
==> Tear down:   kind delete cluster --name sovereign-test
```

README steps 3–4 show:
```
helm install test-release cluster/kind/charts/sealed-secrets/ \
  --namespace sealed-secrets --create-namespace \
  --kube-context kind-sovereign-test --wait
kubectl --context kind-sovereign-test get pods -n sealed-secrets

kind delete cluster --name sovereign-test
```

Chart path, namespace flags, kube-context, and cluster name are identical in both. `platform/deploy.sh` is gone from the terminal output. One source of truth after bootstrap exits. PR #153 merged to main, all CI green.

## What I added
Nothing this round — the work holds up against the goal from my lens.

## Notes for the goal-setter
None.
