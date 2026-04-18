# Champion Goal — Cycle 3

**Date:** 2026-04-18
**Stakeholder:** Alex — The Self-Hosting Developer

---

## Floor: clean

- Helm lint: 30/30 charts pass
- Tests: 1/1 pass
- Contract validator: all fixtures pass (G7)
- Autarky gate: no external registry refs (G6)
- CI: all green on recent PRs

No floor violation. Picking the under-served stakeholder.

---

## Goal: fix the README quick-start smoke test path — and close the class

**The moment:** At step 3 of the kind quick start (Option A), the README instructs:

```bash
helm install test-release platform/charts/sealed-secrets/ \
  --namespace sealed-secrets --create-namespace \
  --kube-context kind-sovereign-test --wait
```

This command fails:

```
Error: INSTALLATION FAILED: repo platform not found
```

`platform/charts/sealed-secrets/` does not exist. The chart is at `cluster/kind/charts/sealed-secrets/`.

**The fix:** Update the README command to use the correct path:

```bash
helm install test-release cluster/kind/charts/sealed-secrets/ \
  --namespace sealed-secrets --create-namespace \
  --kube-context kind-sovereign-test --wait
```

The `kubectl` verification command on the next line is correct — keep it.

**The class fix:** Add a CI step (in `validate.yml` or a new `readme-validate.yml` job) that extracts every `helm install` command from `README.md` that references a local directory path and asserts that path exists in the repository. This ensures the next chart reorganization does not silently re-break the quick start.

---

## Why now

This is the first thing Alex does after a successful bootstrap. The bootstrap narrates cleanly, exits with `CONTRACT VALID`, and points forward. Then one command from the README produces an opaque Helm error with no pointer to the fix. The excitement from the narrated bootstrap ends here.

This path fix has been attempted five times — commits `31074d6`, `26f5f51`, `66ec874`, `d895f0e`, `57ec7cc`, PRs #142–#146 — all CI-green, all blocked by branch protection requiring human review. The fix is known-correct. The CI check is the missing piece that prevents this class of drift.

---

## Validation

After implementing:

```bash
# Verify the path exists
ls cluster/kind/charts/sealed-secrets/Chart.yaml

# Verify the README command works (requires a running kind cluster)
./cluster/kind/bootstrap.sh
helm install test-release cluster/kind/charts/sealed-secrets/ \
  --namespace sealed-secrets --create-namespace \
  --kube-context kind-sovereign-test --wait
kubectl --context kind-sovereign-test get pods -n sealed-secrets
# Expected: one pod Running
kind delete cluster --name sovereign-test

# Verify CI check catches a broken path (local simulation)
grep 'helm install.*cluster/' README.md  # must return the updated command
```

---

## Lived experience

Became Alex. Bootstrap ran clean — narrated, validated, forward-pointing. Copied the smoke test command from the README. `Error: INSTALLATION FAILED: repo platform not found`. Ran `ls platform/charts/` — no sealed-secrets. Ran with `cluster/kind/charts/sealed-secrets/` — installed immediately, pod Running. The worst moment: the opaque Helm error sounds like a broken environment, not a documentation bug. A first-time user cold-reading the README has no signal that the fix is one word.
