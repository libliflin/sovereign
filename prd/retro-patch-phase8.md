# Retro Patch: Phase 8 — testing-and-ha
Generated: 2026-03-25T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 0 | 0 pts |
| Incomplete → backlog | 1 | 3 pts |
| Killed | 0 | — |

Sprint delivered 0 of 1 stories. Story 031a was attempted once and failed review on two ACs.
It is already marked `returnedToBacklog: true` in the sprint file and present in `prd/backlog.json`.

---

## 5 Whys: incomplete stories

### 031a: HA helpers template and foundation chart hardening (cilium, cert-manager, crossplane, sealed-secrets, vault, rook-ceph)

**Failure 1: Cilium install-cni-binaries initContainer missing resource limits**

- Why 1: Review found `install-cni-binaries` initContainer had no `resources.limits` despite `initResources.limits` being set in values.yaml.
- Why 2: The upstream Cilium Helm chart does not wire `initResources` to the `install-cni-binaries` initContainer — it uses a different (undocumented) key for that specific container.
- Why 3: The AC was written assuming all initContainers in the upstream Cilium chart respect the generic `initResources` key — this assumption was not validated against the upstream chart's templates.
- Why 4: Story grooming did not require the implementer to inspect the upstream chart's `templates/` before writing resource-limit ACs for wrapper charts.
- Why 5: No checklist item asks "what is the actual upstream values key for this container's resources?" before writing an AC against an upstream chart we do not own.

**Root cause**: ACs for upstream-chart wrappers were written against assumed (not verified) values key names. The correct upstream key for a specific initContainer was never identified, so the implementation used the wrong key and the review caught it.

**Decision**: Return to backlog as-is (already done). The reviewNotes contain the exact fix needed.
**Remediation story**: `043r` — Add "upstream values key verification" step to HA story grooming checklist.

---

**Failure 2: rook-ceph volumeClaimTemplates AC is architecturally incorrect**

- Why 1: AC required `volumeClaimTemplates` in rook-ceph templates to reference `global.storageClass`.
- Why 2: rook-ceph is a storage *provider* — it creates StorageClasses, it does not consume one for its own StatefulSet storage.
- Why 3: The AC was written by analogy with stateful services (e.g. Keycloak, GitLab) that do consume a StorageClass. This analogy does not apply to the Ceph operator itself.
- Why 4: The distinction between "storage provider" and "storage consumer" was not documented anywhere visible to the story author.
- Why 5: No architecture note in the rook-ceph chart or in `docs/state/architecture.md` describes this inversion.

**Root cause**: Absent documentation of rook-ceph's provider role led to an AC that misunderstood what the chart is allowed to reference. The architecture truth was not written down, so it couldn't be checked.

**Decision**: Return to backlog as-is (already done). ReviewNotes give two options: add a CephCluster CR template referencing `global.storageClass` (the right fix — provides a concrete CR for cluster deployment) OR remove the AC. The backlog story should add the CephCluster CR template.
**Remediation story**: `044r` — Document storage provider/consumer distinction in rook-ceph chart and `docs/state/architecture.md`.

---

## Flow analysis (Heijunka check)

- Sprint capacity: 15 pts. Actual story load: 3 pts (1 story). The sprint was severely under-loaded.
- No oversized stories (> 8 pts).
- No split candidates (> 5 pts).
- Root cause of under-loading: increment-8 was defined as a large theme (Selenium Grid, k6, MailHog, Chaos Mesh, HA pass) but only the HA-helpers story was pulled into the sprint. The rest of the increment's stories remain in the backlog.

**Implication**: The sprint planning ceremony is not pulling enough stories to fill capacity. Either the backlog for phase 8 stories was not populated, or the planning ceremony is being too conservative. This is a planning gap, not a sizing gap.

**Remediation story**: `045r` — Sprint planning checklist: require that pulled stories sum to >= 75% of sprint capacity before planning closes.

---

## Remediation backlog stories

### 043r — Add upstream values-key verification to HA grooming checklist

**Problem**: Story writers authored ACs against assumed Helm values keys for upstream charts without verifying the upstream chart's `templates/` directory. The review ceremony caught a wrong key; the grooming ceremony should have caught it first.

**Fix**: Add a mandatory step to the grooming ceremony prompt for any HA story that touches an upstream chart wrapper: "For each resource-limit AC, identify the exact upstream values key by running `helm show values <chart>` or reading `charts/<name>/values.yaml`. Quote the key in the AC."

### 044r — Document rook-ceph provider role; add CephCluster CR template

**Problem**: rook-ceph's role as a storage *provider* (creates StorageClasses, does not consume one) is undocumented. This led to an architecturally incorrect AC.

**Fix**: (1) Add a `NOTES.txt` or README section to `charts/rook-ceph/` stating "rook-ceph is a storage provider — it does not consume `.Values.global.storageClass`. The Ceph operator creates StorageClasses; other charts reference those classes." (2) Add a `CephCluster` CR template to `charts/rook-ceph/templates/` that sets `spec.storage.storageClassDeviceSets[*].volumeClaimTemplates` referencing `{{ .Values.global.storageClass }}` for bootstrap storage — this is the correct way to satisfy the original intent of the AC.

### 045r — Sprint planning: enforce >= 75% capacity fill before close

**Problem**: Phase 8 sprint closed with 3 pts pulled against a 15-pt capacity. A single story failure wiped the sprint entirely. Denser sprints would deliver more value even when one story fails.

**Fix**: Add a capacity-fill check to the planning ceremony: count story points of pulled stories, verify sum >= `capacity * 0.75`, emit a warning if not. If the backlog for the current phase is exhausted, pull the highest-priority backlog stories from adjacent phases.

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Upstream chart AC validation**: Before writing an AC that sets a specific values key on an upstream chart we wrap (cilium, cert-manager, etc.), run `helm show values` or inspect the upstream `templates/` to confirm the key exists and is applied to the target resource. "It should work" is not enough — quote the exact key in the AC.
- **Storage provider vs consumer**: rook-ceph (and other storage operators) *create* StorageClasses; they do not consume one for their own pods. Do not write ACs requiring `volumeClaimTemplates` → `global.storageClass` for operator charts. Instead, add a CephCluster CR template that configures storage device sets with a storageClass reference.
- **Sprint under-loading**: A sprint with one story is a planning failure, not a delivery failure. If a sprint closes with < 75% capacity filled, investigate whether the planning ceremony pulled aggressively enough from the backlog.

---

## Quality gate improvements

1. **Grooming ceremony**: Add a check — for any story that references resource limits on an upstream chart container, require that the story text quotes the exact upstream values key (found via `helm show values` or upstream chart source inspection). If the key is not quoted, the story is not ready.
2. **Review ceremony**: When an AC about resource limits fails, the failure message should include the correct values key (or a pointer to find it) — not just "this key doesn't work." This speeds up the next iteration.
3. **Planning ceremony**: Add a capacity-fill assertion: `pulled_points / capacity >= 0.75`. Warn and suggest additional backlog pulls if below threshold.

---

## Velocity

| Phase | Points completed | Stories accepted | Pass rate |
|-------|-----------------|-----------------|-----------|
| 8 (testing-and-ha) | 0 | 0 / 1 | 0% |

Velocity trend: insufficient data (prior sprints not recorded in manifest velocity array). Recommend backfilling from sprintHistory in future retros.
