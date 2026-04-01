# Retro — After Cycle 20

## Progress

| Cycle | First Failure | Directive Target | Surgeon Action | Result |
|-------|---------------|------------------|----------------|--------|
| 15 | L2: harbor-core (SSA conflict + memory) | L2: `--force-conflicts` in deploy.sh | Applied | Helm upgrade landed (rev 28); core still Pending (memory) |
| 16 | L2: harbor-core (Insufficient memory) | L2: `harbor.trivy.enabled: false` | Applied | **L2 cleared** — harbor-core Running |
| 17 | L3: keycloak (ImagePullBackOff) | L3: loosen seeding gate to harbor-core only | Applied | Seeding executes but fails — unauthenticated push |
| 18 | L3: keycloak (ImagePullBackOff) | L3: add `docker login` before seeding loop | Applied | Port-forward not ready when login runs — deploy exits 1 |
| 19 | L3: keycloak (ImagePullBackOff) | L3: replace `sleep 3` with PF readiness poll | Applied | Port-forward readiness fix pending result next cycle |

## Layer Trajectory
- Started at Layer 2, advanced to Layer 3 after Cycle 16
- Net advancement: **+1 layer** (L2 → L3)
- Stuck at Layer 3 for 3 consecutive cycles (17, 18, 19)
- Total pods Running (Cycle 20 report): ~67 Running / ~55 not Running

## Patterns Detected

### Incremental seeding debug — 3-cycle stagnation at Layer 3 (Cycles 17–19)
- **Evidence:** Three consecutive cycles targeting keycloak/seeding in deploy.sh, each exposing the next sequential bug: (17) gate too broad → (18) missing `docker login` → (19) port-forward race condition. Each fix was applied correctly but revealed the next layer of failure.
- **Impact:** Layer 3 has been blocked for 3 cycles, but this is not circular failure — each cycle made genuine incremental progress through a multi-bug code path. The port-forward readiness poll (Cycle 19) is the last known bug in the seeding chain.
- **Recommendation:** No prompt change needed. Expected to clear in Cycle 20 or 21. If Layer 3 remains blocked after Cycle 21 (2 more cycles), reclassify and look for a fundamentally different seeding approach (skopeo copy, pre-seeded PV snapshot, or seed from within cluster).

### Infra-incompatible backlog accumulating — 5+ cycles of known failures (Cycles 15–19)
- **Evidence:** falco (`/lib/modules/6.10.14-linuxkit/build: No such file or directory`) appears in every pod list all 5 cycles. tempo (`rook-ceph-rgw-sovereign.rook-ceph.svc.cluster.local: no such host`) appears all 5 cycles. opa-gatekeeper CRD ordering failure appears 5/5 cycles. All three are listed as pre-emptive warnings in counsel's directive every cycle but no directive has been issued.
- **Impact:** The moment Layer 3 clears, Layer 4 (gitlab-redis deleted tag) becomes the blocker, then Layers 5–6 expose tempo, thanos, falco, and opa-gatekeeper in rapid succession. Each costs a cycle if not pre-queued.
- **Recommendation:** Adjust counsel.md to allow pre-emptive batching of INFRA_INCOMPATIBLE fixes. See Prompt Adjustments below.

### Dead docker.io image tags — 5 cycles unaddressed (Cycles 15–19)
- **Evidence:** `docker.io/bitnami/redis:6.2.7-debian-11-r11` (gitlab), `docker.io/bitnami/thanos:0.36.0-debian-12-r1` (thanos), `docker.io/bitnami/postgresql:11.14.0-debian-10-r22` (sonarqube), `docker.io/bitnami/rabbitmq:3.12.11-debian-11-r0` (reportportal) — all NotFound on docker.io, all appearing every cycle, none directed for fix.
- **Impact:** Multiple Layer 4–7 components will fail immediately after Layer 3 clears. Known tags, known fix (find the correct available tag and update values.yaml). Each costs a cycle if addressed one at a time.
- **Recommendation:** Same batching note as above — queue these alongside INFRA_INCOMPATIBLE fixes in pre-emptive mode.

## Prompt Adjustments

### counsel.md — Allow pre-emptive batching when lower-layer fix is confirmed in-flight

**Evidence:** 3+ cycles of identical INFRA_INCOMPATIBLE and IMAGE_ISSUE pre-emptive warnings listed but never actioned. When Layer 3 clears, Layers 4–6 will each cost a cycle on failures known for 5+ cycles.

**Change:** Added one paragraph to the "Be pragmatic about infra-incompatible components" section of `operating-room/agents/counsel.md`, after the "Known kind incompatibilities" list:

**Text added:**
> **Pre-emptive batching:** When the current first-failing-layer fix is confirmed in-flight (surgeon applied it last cycle and it is a timing or config fix, not a structural failure), you MAY include a second "Pre-emptive Fix" in the directive targeting the next known INFRA_INCOMPATIBLE or dead-image-tag blocker — but ONLY if: (a) the next failure has appeared 3+ consecutive cycles in the failing pod list, (b) the fix does not touch the same files as the primary directive, and (c) the fix is mechanical (disable in values.yaml, update a tag). Label it clearly as "Pre-emptive Fix" and list it after the primary directive. Surgeon applies both in the same cycle.

**Rationale:** The "ONE directive per cycle" rule is right for uncertain failures. For confirmed-mechanical INFRA_INCOMPATIBLE failures that have been failing for 5+ cycles, one-at-a-time is pure cycle waste.

---

No other prompt changes. Operator and surgeon prompts are performing correctly. The loop is making genuine forward progress.

## Escalation
NONE

---

# Retro — After Cycle 14

## Progress

| Cycle | First Failure | Directive Target | Surgeon Action | Result |
|-------|---------------|------------------|----------------|--------|
| 10 | Layer 3 / keycloak / ImagePullBackOff (harbor token HTTPS refused) | Layer 3/harbor: remove force-upgrade block; add kubectl rollout undo/patch/restart/status block | Applied: removed lines 132-144, inserted 4 kubectl commands after install_chart | REGRESSION — Layer 2 in Cycle 11 report; kubectl commands gave field-manager ownership of helm-managed annotations |
| 11 | Layer 2 / harbor-core / Pending (Insufficient memory) | Layer 2/harbor-core: add `memory: "128Mi"` to core.resources.requests | Applied: added memory request to values.yaml | No improvement — Layer 2 still; helm upgrade now fails with kubectl field-manager conflict; memory fix cannot land |
| 12 | Layer 2 / harbor / UPGRADE FAILED (field conflict) + harbor-core Pending | Layer 2/harbor: remove kubectl rollout block (source of field-manager conflict) | Applied: removed rollout block | No improvement — Layer 2 still; stale managedFields persist in live Deployment object even after block removed |
| 13 | Layer 2 / harbor / UPGRADE FAILED (field conflict persists) + harbor-core Pending | Layer 2/harbor: add `--force` to harbor install_chart to clear stale managedFields | Applied: added `--force` flag | No improvement — Layer 2 still; `--force` deprecated/incompatible with SSA: `invalid operation: cannot use server-side apply and force replace together` |
| 14 | Layer 2 / harbor / UPGRADE FAILED (--force incompatible with SSA) + harbor-core Pending | Layer 2/harbor: remove `--force`, reduce memory 128Mi → 64Mi | Applied: removed --force, changed memory to 64Mi | Pending — Cycle 15 not yet run; notably, --force DID delete/recreate the Deployment in Cycle 14, clearing managedFields |

## Layer Trajectory

- Previous retro (Cycle 9): first failure at Layer 3
- Cycle 10 report: Layer 3 (keycloak — harbor token endpoint refused)
- Cycle 11–14 reports: Layer 2 (harbor — Helm upgrade failures, harbor-core Pending)
- Net movement: **regressed -1 layer** (Layer 3 → Layer 2) due to Cycle 10 fix introducing kubectl/Helm field conflict
- Total pods Running (Cycle 14 / Cycle 15 report): ~71 Running out of ~132 total

## Patterns Detected

### kubectl on Helm-managed resources — root cause of 5-cycle stagnation
- **Evidence:** Cycle 10 surgeon added `kubectl rollout undo`, `kubectl patch`, `kubectl rollout restart` targeting the `harbor-core` Deployment. All three commands set `managedFields.manager=kubectl` on `.spec.template.metadata.annotations.checksum/secret`. Helm uses server-side apply and cannot reclaim a field already owned by a different manager. Every subsequent `helm upgrade harbor` (Cycles 11–14) failed with `conflict with "kubectl" using apps/v1: .spec.template.metadata.annotations.checksum/secret`. Four cycles were consumed by the cascading consequences.
- **Impact:** The 128Mi memory fix (correct, applied Cycle 11) never reached the running cluster for 4 cycles. The first failing layer regressed from 3 to 2 and stayed there. Cycle 14's --force accidentally fixed the managed fields by deleting the Deployment — which was the correct resolution but took 3 extra cycles to reach.
- **Recommendation:** Add explicit prohibition to surgeon.md: never use kubectl to modify fields on Helm-managed resources.

### Memory fix orphaned by script-level failures (4 cycles)
- **Evidence:** `memory: "128Mi"` added to `platform/charts/harbor/values.yaml` in Cycle 11. In Cycles 11, 12, 13: harbor helm upgrade fails before applying values; the memory request never lands. The values file is correct; the failure is in deploy.sh. harbor-core-7bfb5558b-lcvsx has `FailedScheduling` events from 14h+ as of the Cycle 15 report.
- **Impact:** 3 wasted cycles attempting values fixes that could not land. Correct diagnosis (RESOURCE_ISSUE) but fix was blocked by a separate failure (script/Helm interaction).
- **Recommendation:** None — counsel correctly reclassified each cycle. The root cause was the kubectl prohibition gap in surgeon.md.

### ceph-block StorageClass PVCs — untracked INFRA_INCOMPATIBLE accumulating
- **Evidence:** Cycle 14 report (Cycle 15 data) shows PVCs in Pending requesting `ceph-block` StorageClass for: `prometheus-stack-grafana`, `repo-data-gitlab-gitaly-0`, `sonarqube-sonarqube`. The cluster only has `local-path` (default) and `standard` (also local-path). The `ceph-block` StorageClass does not exist and will never exist in kind. This is a known-to-be-absent infrastructure dependency.
- **Impact:** These PVCs will never bind. grafana, gitlab-gitaly, and sonarqube will stay Pending indefinitely. When Layer 2 clears, these become Layer 4, 5, 7 failures that are not in counsel's "Known kind incompatibilities" list and will consume diagnosis cycles.
- **Recommendation:** Add `ceph-block StorageClass → change to standard` to counsel.md's Known kind incompatibilities list.

### INFRA_INCOMPATIBLE pre-emption queue has grown to 4 components
- **Evidence:** Falco (eBPF / linuxkit kernel headers absent) flagged since Cycle 5 (10 cycles). Tempo (rook-ceph DNS absent, MinIO fix known) flagged since Cycle 5. OPA-Gatekeeper (CRD race) flagged since Cycle 6. ceph-block PVCs now confirmed. All four are in counsel's pre-emptive warnings every cycle.
- **Impact:** When Layer 2 clears next cycle, all four fire simultaneously: Layer 5 (tempo, thanos-query-frontend ImagePullBackOff), Layer 6 (falco, opa-gatekeeper), Layer 5+ (grafana PVC). Each will require one cycle to address unless pre-batched.
- **Recommendation:** No prompt change beyond adding ceph-block to known incompatibilities. Counsel already has the 3+ cycles → pre-empt rule; it should apply it as soon as Layer 2 is up.

## Prompt Adjustments

### surgeon.md — Rule added: kubectl must not modify Helm-managed resources

**Evidence threshold met:** 5 consecutive cycles of harbor failures traceable to a kubectl rollout block the surgeon added in Cycle 10. The same surgeon would make the same mistake again without this rule because "kubectl rollout restart" looks like a reasonable fix for a stuck pod.

**Change:** Added one rule to the Rules section of `operating-room/agents/surgeon.md`.

**Rule added:**
> **Never use kubectl to modify fields on Helm-managed resources.** `kubectl patch`, `kubectl rollout restart`, `kubectl set`, and similar commands create `managedFields` entries with `manager=kubectl` that Helm's server-side apply cannot reclaim. Subsequent `helm upgrade` will fail with `conflict with "kubectl" using apps/v1`. If a Helm-managed Deployment needs a restart, change a value in the chart's values.yaml to force a pod template hash change. Reserve kubectl for resources that Helm does not own (e.g., Jobs, manual ConfigMaps, CRDs installed separately).

### counsel.md — Known kind incompatibilities: add ceph-block StorageClass

**Evidence threshold met:** 3+ cycles of PVCs in Pending requesting `ceph-block` (grafana, gitlab-gitaly, sonarqube confirmed in Cycle 14 report). Not in the known incompatibilities list; will consume a diagnosis cycle when surfaced.

**Change:** Added one bullet to the "Known kind incompatibilities" list in `operating-room/agents/counsel.md`.

**Entry added:**
> - `ceph-block` StorageClass: does not exist in kind — PVCs for grafana, gitlab-gitaly, sonarqube, code-server will never bind. Change PVC storageClassName to `standard` in the affected chart values.

## Escalation
NONE
