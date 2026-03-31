# SMART Guidance: Vendor API Field Values in Acceptance Criteria

This file contains supplemental rules for the SMART check ceremony.
See `smart-check.md` for the full SMART scoring rubric.

---

## CRD spec citation rule

When an AC asserts a **vendor-specific status field value** — for example a phase name,
condition string, or status key emitted by a third-party operator — the story **must** do
one of the following:

1. **Cite the upstream CRD documentation** for the pinned chart version.
   Example: "per chaos-mesh v2.6.3 CRD spec, `.status.phase` transitions to `Not Injected`
   once the experiment concludes."

2. **Note that the value was empirically confirmed** against a running instance of that
   chart version.
   Example: "verified empirically against chaos-mesh v2.6.3 running in kind."

### Why this rule exists

TEST-004b failed review three times because AC3 asserted `phase=Finished` — the value
documented in older releases — but chaos-mesh v2.6.3 uses `Not Injected` as the terminal
recovery state.  The implementation was correct; the AC was wrong.  No gate required
cross-referencing the pinned chart version's CRD spec before the story was written.

### Affected field patterns

This rule applies whenever an AC references any of the following patterns:

- `phase.*value` — e.g. `.status.phase == "Finished"`, `.status.phase == "Running"`
- `status.*field` — e.g. `.status.conditions[].type`, `.status.state`
- `vendor.*field` — any field defined by a vendor CRD (chaos-mesh, cert-manager, ArgoCD,
  Crossplane, etc.)
- `condition` strings — e.g. `Ready=True`, `Synced=True`

### SMART scoring impact

| Situation | Score impact |
|-----------|-------------|
| AC asserts a vendor status field value **with** CRD citation or empirical confirmation | No penalty |
| AC asserts a vendor status field value **without** citation or confirmation | Measurable ≤ 3 |
| Story explicitly notes "value unverifiable without running cluster" | Achievable ≤ 3 |

### How to apply this rule

When scoring a story in the SMART check ceremony:

1. Scan each AC for vendor-specific field value assertions.
2. If found, check whether the story body or AC cites the chart version CRD spec or notes
   empirical confirmation.
3. If neither citation nor confirmation is present, reduce **Measurable** to ≤ 3 and add a
   note in `smart.notes` identifying the specific AC and the missing citation.

---

## Chart-iteration script gate

Any shell script story whose description mentions iterating `platform/charts/` **must include**
"run against all existing charts in `platform/charts/`" as an explicit acceptance criterion —
not just synthetic fixture charts.

### `set -euo pipefail` + grep on optional fields

When a shell script uses `set -euo pipefail` and runs `grep` for an optional YAML field
(e.g. `replicaCount`), the grep will exit 1 when the field is absent. With `pipefail`, this
silently kills the script.

**Required fix**: always use `|| true` on grep pipelines where the field may be absent:

```bash
replica_count="$(grep -E '^replicaCount:' "$values" | awk '{print $2}' || true)"
```

Mark `achievable ≤ 3` for any story whose shell script iterates `platform/charts/` and whose
test plan does not include running against the full chart corpus.

---

## Related guidance

- For the full shell script quality gates rubric, see `smart-check.md` under
  "Shell script quality gates".
- The pinned chart version is always the version recorded in `vendor/VENDORS.yaml` or the
  chart's `Chart.yaml` `dependencies[].version` field.
