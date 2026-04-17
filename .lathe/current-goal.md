# Goal — Cycle 1

**Status: floor violation — fix before any other work**

---

## What to change

Fix `platform/charts/perses/` so `helm lint` passes.

The upstream perses subchart (`perses-0.8.0.tgz`) has `additionalProperties: false` in its `values.schema.json`. It exposes `replicas` (not `replicaCount`), and has no `affinity`, `podDisruptionBudget`, or `security` key in its schema. The wrapper chart currently passes all four of these under the `perses:` alias, which the upstream schema rejects:

```
[ERROR] templates/: values don't meet the specifications of the schema(s) in the following chart(s):
perses:
- at '': additional properties 'affinity', 'podDisruptionBudget', 'security', 'replicaCount' not allowed
```

Three things must happen:

1. **`perses.replicaCount` → `perses.replicas`** in `values.yaml` (the upstream's actual key).

2. **Move `affinity` and `podDisruptionBudget` out of the `perses:` block** and into the wrapper chart's own `templates/` directory. The wrapper's `templates/` currently has only `_helpers.tpl` and `ingress.yaml` — it needs a `pdb.yaml` and the affinity must be expressed at the wrapper level.

3. **`perses.security`** — the upstream schema has no such key. This block contains OIDC config. Investigate whether the upstream chart accepts OIDC via a different key (e.g., nested under `config:`) or whether this must be moved. Do not silently drop it; OIDC is load-bearing for zero trust.

Quality gates to run after the fix:
```bash
helm lint platform/charts/perses/
helm template platform/charts/perses/ | grep PodDisruptionBudget   # must find it
helm template platform/charts/perses/ | grep podAntiAffinity        # must find it
```

---

## Which stakeholder, and why now

**Floor violation — serves everyone, blocks everyone.**

The Helm Lint section of the snapshot: `FAIL — 1/33 charts failed: platform/charts/perses`.

The CI `validate.yml` workflow runs `helm lint` on all charts — any PR fails here, not because of the PR's change, but because `perses` is already broken. S3 (Chart Author) discovers this the moment they run `helm lint` locally. S5 (Delivery Machine) hits it during preflight. The broken chart also demonstrates the wrong pattern for other chart authors: it looks like the way to pass HA config to a subchart is to put it under the subchart alias in values.yaml — which is wrong when the upstream schema has `additionalProperties: false`.

---

## Lived experience note

**Stakeholder walked:** S4 (Security Auditor), constitutional gate check → snapshot.

Ran the S4 journey commands. Constitutional gates G1, G6, G7 all PASS — sovereignty invariants clean. Then the full snapshot: Helm Lint FAIL.

Pulled the upstream chart tarball, inspected `values.schema.json`. `additionalProperties: false`. The upstream uses `replicas` not `replicaCount`, and has no `affinity`, `podDisruptionBudget`, or `security` key. The wrapper chart was written as though the upstream schema would accept sovereign's HA additions. It does not.

**The worst moment:** the failure message — `at '': additional properties ... not allowed` — gives no path to resolution. An S3 contributor opening this chart as a reference for HA config in a subchart wrapper would learn the wrong pattern. The broken example is worse than no example: it teaches the mistake.

**The structural lesson:** wrapper charts with upstream subcharts that have `additionalProperties: false` must manage PDB and affinity in their own `templates/`, not by passing them through the subchart alias. This fix should establish that pattern clearly.
