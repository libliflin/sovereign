# Champion Goal — Cycle 2

**Date:** 2026-04-17

---

## Floor: still violated

`helm lint platform/charts/perses/` fails with the same error as cycle 1:
```
at '': additional properties 'podDisruptionBudget', 'replicaCount', 'affinity', 'security' not allowed
```

Four open PRs target this violation. None are merged. The fix is complete.

---

## Goal: land the fix — do not re-implement it

**Merge PR #137. Close PRs #134, #135, #136 as superseded.**

PR #137 title: "fix: resolve all 7 helm-validate CI failures"
- All CI checks: SUCCESS
- Verifier confirmed in cycle 1 round 1: all 7 charts fixed, all gates pass after merge

The fix includes:
- `platform/charts/perses/values.yaml` — `replicas: 1` (ha_exception), wrapper-level PDB, schema-incompatible keys removed
- `platform/charts/perses/templates/poddisruptionbudget.yaml` — new PDB template
- `platform/vendor/VENDORS.yaml` — perses, mailhog, zot: `ha_exception: true`
- `platform/charts/victorialogs/values.yaml` — PDB + podAntiAffinity added
- `platform/charts/prometheus-stack/values.yaml` — PDB `enabled: true`
- `platform/charts/jaeger/templates/poddisruptionbudget.yaml` — collector + query PDBs
- `.github/workflows/validate.yml` — ha_exception bypass for podAntiAffinity check

**After merge, verify:**
```
helm lint platform/charts/perses/
# expected: 0 chart(s) failed
```

---

## Why merge, not implement

This is the second consecutive cycle with the same floor violation. The rules require a changed approach: the builder built the fix; the builder must now close it. Re-implementing the same fix a third time would produce PR #138 — also unmerged.

The problem is not the code. The problem is the delivery loop not closing.

---

## Lived experience

Ran `helm lint platform/charts/perses/` — identical failure. Ran `gh pr list` — four open PRs for one broken chart. The worst moment: not the error itself, but seeing four accumulated fixes sitting open while the floor stays broken. The fix is done. Land it.
