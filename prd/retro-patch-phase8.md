# Retro Patch: Phase 8 — testing-and-ha
Generated: 2026-03-24T23:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 0 | 0 pts |
| Incomplete → backlog | 1 | 3 pts |
| Killed | 0 | — |

Sprint goal: Harden all platform Helm charts with HA primitives so every deployment survives a node failure.

**Result: 0 / 3 story points delivered. Single story failed review twice on two specific ACs.**

---

## 5 Whys: incomplete stories

### 031a: HA helpers template and foundation chart hardening (cilium, cert-manager, crossplane, sealed-secrets, vault, rook-ceph)

**8 of 10 ACs passed review. 2 ACs failed:**

**Failure A — Cilium `install-cni-binaries` initContainer resource limits missing**

- Why 1: Story failed review → `install-cni-binaries` initContainer had `resources.requests` but no `resources.limits`
- Why 2: Implementor set generic `initResources` key, assuming it would cover all initContainers → the upstream Cilium chart does NOT route `initResources` to the `install-cni-binaries` init container
- Why 3: The story described the goal ("resource limits on every container") without specifying which upstream values.yaml key maps to each initContainer
- Why 4: The implementor did not cross-reference the upstream Cilium chart's values schema to verify that `initResources` is applied to all init containers
- Why 5: Story authoring for wrapper charts that depend on complex upstream charts (cilium, cert-manager) assumes implementors will research upstream values schemas in depth — but there is no gate that forces this research before implementation

**Root cause A**: Stories applying HA standards to upstream wrapper charts lack AC-level specificity for which values.yaml keys control each container/initContainer's resource limits. The test plan (`grep -A5 resources:`) is a necessary-but-not-sufficient gate — it can pass if most containers have limits even if one init container is missing. The review gate (`check-limits.py`) correctly caught this, but only after the sprint iteration was consumed.

**Decision**: Return to backlog. Fix is targeted: identify the correct upstream values.yaml key for `install-cni-binaries` (e.g., `cni.resources` or `installCNIBinariesResources`) and add it to `charts/cilium/values.yaml`.

---

**Failure B — rook-ceph `volumeClaimTemplates reference global.storageClass` AC is architecturally incorrect**

- Why 1: Story failed review → `grep -rn 'global.storageClass' charts/rook-ceph/templates/` returned no output for volumeClaimTemplates
- Why 2: The AC was copied from the standard HA template without adapting it to rook-ceph's unique role: rook-ceph **creates** StorageClasses (CephBlock, CephFilesystem), it does not **consume** a pre-existing StorageClass for its own mon/mgr StatefulSet PVs
- Why 3: Story grooming applied the generic HA template AC verbatim to a storage provider chart — a category of chart with fundamentally different storage semantics
- Why 4: The story grooming ceremony has no explicit check distinguishing "storage consumer" charts (standard HA applies) from "storage provider" charts (rook-ceph, etcd, etc.) where the storage AC needs semantic adaptation
- Why 5: The SMART achievable scoring checks whether the *implementation* is feasible, but does not check whether each AC is *semantically valid* for the chart's architectural role

**Root cause B**: The grooming ceremony does not distinguish storage-provider charts from storage-consumer charts when applying standard HA acceptance criteria. This results in ACs that are impossible to satisfy (not because implementation is hard, but because the AC is factually wrong for the chart's role). A storage provider cannot consume a StorageClass that it has not yet created.

**Decision**: Return to backlog with two resolution options:
- Option A: Add a `CephCluster` CR template in `charts/rook-ceph/templates/` that references `{{ .Values.global.storageClass }}` for the *initial bootstrap phase* (before Ceph's own StorageClasses are ready), using the pre-existing StorageClass for mon/mgr PVs during first-install.
- Option B: Remove the AC and replace it with: "A comment in values.yaml documents that rook-ceph creates (not consumes) StorageClasses; the chart does not provision its own mon/mgr PVs via a pre-existing StorageClass."

**Remediation story**: `042r` — Fix rook-ceph storageClass AC architectural mismatch

---

## Flow analysis (Heijunka check)

- Sprint avg story size: 3.0 pts
- Point distribution: {3: 1}
- Oversized (> 8 pts): 0
- Split candidates (5–8 pts): 0

No sizing issues. The story was correctly sized at 3 points and is bounded. The failure was
precision-of-implementation and precision-of-AC-authoring, not scope overreach.

**Story 031a had `achievable: 3` in its SMART score with a note that it was "near the 3-point story budget ceiling."** In hindsight, the achievable concern was correct — the story assumed the implementor would research all upstream chart values schemas in depth AND correctly interpret rook-ceph's dual role. Both assumptions failed.

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **Upstream wrapper charts need values-schema research before AC authoring.** When an HA story covers a chart that wraps an upstream Helm chart (cilium, cert-manager, crossplane), the AC must name the specific upstream values.yaml key that controls each container/initContainer resource limits. Generic ACs like "resource limits on every container" will be passed by implementors who set a generic key — catch this in grooming by requiring: "list the upstream chart key for each container's resources."

- **Storage-provider charts require semantically different HA ACs.** Charts that ARE storage (rook-ceph, etcd, Ceph) cannot follow the standard "volumeClaimTemplates reference global.storageClass" AC because they create StorageClasses rather than consuming them. Grooming ceremony should have a check: "Is this chart a storage provider? If yes, volumeClaimTemplates AC is inapplicable — replace with appropriate HA AC for this service's StatefulSet."

- **The review gate is stronger than the test plan gate.** The review used `check-limits.py` to exhaustively enumerate container specs and caught the missing limit. The story's test plan used `grep -A5 resources:` which is insufficient. For HA hardening stories, the test plan should reference the review gate's verification command: `helm template | python3 check-limits.py`.

---

## Quality gate improvements

**Gate #13 (every container spec has resources.requests/limits):** The test plan for HA hardening stories MUST use `check-limits.py` (or equivalent exhaustive parse), not `grep -A5 resources:`. Update story templates for HA hardening to include: `helm template charts/<name>/ | python3 scripts/check-limits.py` in the test plan.

**Grooming gate — storage provider role check:** Before adding "volumeClaimTemplates reference global.storageClass" to any story's ACs, confirm the chart is a storage consumer, not a storage provider. If it is a storage provider, write a custom AC describing how its own StatefulSet PVs are managed.

---

## Velocity

| Increment | Points Completed | Stories Accepted | Review Pass Rate |
|-----------|-----------------|-----------------|-----------------|
| 0 (ceremonies) | 15 | — | 100% |
| 1 (bootstrap) | 14 | — | 100% |
| 2 (foundations) | 10 | 4 | 75% |
| 2h (ci-hardening) | 5 | 4 | 100% |
| 2i (integration) | 13 | — | 100% |
| 3 (gitops-engine) | 12 | 2 | 100% |
| 4 (autarky) | 13 | 5 | 80% |
| 5 (security) | 12 | 5 | 20% |
| 6 (observability) | 8 | 4 | 100% |
| 7 (devex) | 2 | 1 | 0% |
| **8 (testing-and-ha)** | **0** | **0** | **0%** |

Trend: Two consecutive low-delivery increments (7: 2 pts, 8: 0 pts). Both failed on HA gate precision.
Root cause shared: HA quality gate is catching real issues but the **story authoring** is not pre-specifying the exact implementation targets precisely enough. This causes iteration waste.

Retro patch → `prd/retro-patch-phase8.md`
