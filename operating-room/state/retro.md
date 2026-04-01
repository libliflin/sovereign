# Retro — After Cycle 29

## Progress

| Cycle | First Failure | Directive Target | Surgeon Action | Result |
|-------|---------------|------------------|----------------|--------|
| 25 | L3: keycloak (harbor seed :8080 i/o timeout) | L2: remove `:8080` from `harbor.externalURL` in deploy.sh | Applied: line 123 changed | No change — `chart_healthy` skip gate fired, helm upgrade never ran |
| 26 | L3: keycloak (harbor seed :8080 i/o timeout) | L2: bypass `chart_healthy` skip gate for harbor | Applied: replaced `install_chart harbor` with unconditional `helm upgrade --install` | Harbor upgraded (REVISION 30); harbor-core pod never restarted — serving stale config |
| 27 | L3: keycloak (harbor seed :8080 i/o timeout) | L2: `kubectl rollout restart deployment/harbor-core` in deploy.sh | Applied: rollout restart + status block added | harbor-core restarted; new error: `UNAUTHORIZED: unauthorized to access repository: bitnami/keycloak, action: push` |
| 28 | L3: keycloak (harbor seed UNAUTHORIZED push) | L2: add `--username admin --password "${HARBOR_ADMIN_PASS}"` to `crane copy` | Applied: flags added after `copy --insecure` | `Error: unknown flag: --username` — crane requires auth flags before subcommand |
| 29 | L2: harbor (crane flag rejection) | L2: reorder flags to `crane --username --password copy --insecure` | Applied | TBD (Cycle 30 not yet run) |

## Layer Trajectory
- All 5 cycles: first failure at Layer 3 (Cycles 25–28) then Layer 2 (Cycle 29)
- Net advancement: **0 layers** (still at L2/L3 boundary)
- However: genuine sequential progress through harbor seeding chain each cycle — not circular stagnation
- Total pods Running (Cycle 29 report): ~67 Running / ~55 not Running — unchanged from previous retro window

## Patterns Detected

### Harbor seeding chain — 10-cycle incremental debug (Cycles 20–29)
- **Evidence:** This is the second 5-cycle window on the same root-cause chain. From the previous retro window (20–24): docker networking → sudo no-terminal → pod IP vs ClusterIP → sed bind-mount → grep-v fix. This window (25–29): externalURL wrong → helm skip gate → pod not restarting → crane auth missing → crane flag ordering. Each cycle surfaced the next sequential bug.
- **Impact:** Keycloak has had zero images in Harbor for 20+ hours. All layers above 3 are downstream. But the progress is real — each fix correctly resolved the stated error and exposed the next one.
- **Recommendation:** Crane flag reorder (Cycle 29) is the last known seeding bug. If Cycle 30 still fails, step back and check whether the Harbor project exists and has public push access before further crane flag diagnosis.

### kubectl rollout restart rule violated — Cycles 27–28
- **Evidence:** The Cycle 14 retro added an explicit rule to surgeon.md: "Never use kubectl to modify fields on Helm-managed resources." Despite this, Cycle 27's directive instructed `kubectl rollout restart deployment/harbor-core` be added to deploy.sh, and surgeon applied it. The violation occurred because counsel.md Step 3 still contains: "Direct a `kubectl rollout restart` this cycle." — directly contradicting the surgeon.md prohibition. Two agents received conflicting instructions; counsel's directive won.
- **Impact:** So far no SSA field conflict has appeared (harbor upgraded to REVISIONs 31–32 without error in Cycles 28–29). Risk remains: if a future harbor chart update adds a checksum annotation to the core Deployment, Helm SSA will conflict with the kubectl-owned `restartedAt` annotation. Same failure mode as Cycles 11–13.
- **Recommendation:** Fix counsel.md Step 3 to replace the `kubectl rollout restart` directive with the Helm-idiomatic approach: pass `--set "harbor.core.podAnnotations.forceRestart=$(date +%s)"` in the helm upgrade invocation to force pod template change. See Prompt Adjustments.

### Pre-emptive queue: 8+ items, 5+ cycles each, still not batched
- **Evidence:** All of the following have appeared in EVERY cycle (25–29) with no directive issued:
  - `falco-lb9mk` Init:CrashLoopBackOff — eBPF kernel headers absent (15+ cycles total)
  - `tempo-*` CrashLoopBackOff — rook-ceph-rgw DNS absent (10+ cycles)
  - `thanos-query-*` ImagePullBackOff — `docker.io/bitnami/thanos:0.36.0-debian-12-r1` not found (10+ cycles)
  - `gitlab-redis-master-0` ImagePullBackOff — `docker.io/bitnami/redis:6.2.7-debian-11-r11` not found (10+ cycles)
  - `opa-gatekeeper` FAILED — CRD race, 5 cycles identical error
  - `sonarqube-postgresql-0` ImagePullBackOff — `docker.io/bitnami/postgresql:11.14.0-debian-10-r22` not found
  - `reportportal` FAILED — RabbitMQ password required on upgrade
  - `harbor-jobservice-dcf699cdf-fstnh` — stale pod Pending/Running alongside new revision (Cycles 27–29)
- Counsel has listed these as warnings in directives but has NOT issued pre-emptive Fix blocks. Pre-emptive batching conditions are met for all items.
- **Impact:** When crane seeding succeeds (Cycle 30 expected), keycloak will start. Layer 4+ will then surface all eight failures simultaneously. If addressed one-at-a-time, that is 8+ cycles of known failures. Batching can compress this to 2–3 cycles.
- **Recommendation:** Counsel should use the "Pre-emptive Fix" block format starting Cycle 30. Priority order: (1) thanos image tag update — docker.io/bitnami/thanos tag is gone, switch to current; (2) tempo storage reconfigure to MinIO (already running); (3) opa-gatekeeper CRD split; (4) falco disable driver-loader; (5) gitlab-redis image tag update.

### harbor-jobservice stale pod (Cycles 27–29)
- **Evidence:** `harbor-jobservice-dcf699cdf-fstnh Running` persists alongside new Pending revisions across 3 consecutive cycles. The old pod is not being evicted.
- **Impact:** Minor — harbor is functional with the old jobservice pod. But stale pods accumulate and obscure cluster health.
- **Recommendation:** Not critical. Note for when Layer 2 becomes the primary focus after keycloak unblocks.

## Prompt Adjustments

### counsel.md — Step 3: replace kubectl rollout restart directive with Helm-idiomatic approach

**Evidence:** 3 cycles (26, 27, 28) where counsel needed to force harbor-core to reload updated config. Cycle 27 directive used `kubectl rollout restart` which violates surgeon.md's explicit prohibition. The prohibition was added in the Cycle 14 retro specifically because this pattern caused 5 cycles of SSA field conflicts (Cycles 10–14). Counsel.md Step 3 still contains the contradictory instruction at line 80: "Direct a `kubectl rollout restart` this cycle."

**Change:** Replace the `kubectl rollout restart` instruction in Step 3 with guidance to force pod template change via Helm `--set` annotation. This keeps the fix Helm-idiomatic and avoids managedFields conflict.

**Old text (line 80):**
> - If last cycle directed a config change and the same pod is still Running with the same name, the fix didn't land. Direct a `kubectl rollout restart` this cycle.

**New text:**
> - If last cycle directed a config change and the same pod is still Running with the same name, the fix didn't land. Direct surgeon to add `--set "<component>.podAnnotations.forceRestart=$(date +%s)"` to the helm upgrade invocation for that component — this forces a pod template hash change and triggers a rolling restart without touching kubectl. Do NOT direct `kubectl rollout restart` on Helm-managed resources; it creates managedFields conflicts that break subsequent helm upgrades (see Cycles 10–14 incident).

---

No changes to operator.md or surgeon.md. Surgeon's rule is already correct; the violation came from counsel's conflicting instruction. This fix closes the contradiction.

## Escalation
NONE

---

# Retro — After Cycle 24

## Progress

| Cycle | First Failure | Directive Target | Surgeon Action | Result |
|-------|---------------|------------------|----------------|--------|
| 20 | L3: keycloak ImagePullBackOff | L3: replace docker pull/push with `crane copy` | Applied: removed docker login/pull/tag/push, added crane copy | Crane ran; failed `lookup harbor.sovereign.local: no such host` on host |
| 21 | L3: keycloak ImagePullBackOff | L3: add 2nd port-forward on 8080 + inject host `/etc/hosts` via `sudo tee` | Applied: added port-forward + sudo injection | `sudo: a terminal is required` — injection silently skipped; crane still fails |
| 22 | L3: keycloak ImagePullBackOff | L3: move crane inside kind node via `docker exec` | Applied: docker exec + crane bootstrap in kind node | Connection refused — crane resolved to pod IP 10.244.1.136 (no listener on :80/:443) |
| 23 | L2: harbor crane seed conn refused | L2: change HARBOR_IP lookup from pod IP to service ClusterIP | Applied: changed kubectl query to `.spec.clusterIP` | `sed -i` fails on bind-mounted `/etc/hosts` — stale pod IP entry never removed; crane still resolves to 10.244.1.136 |
| 24 | L2: harbor crane seed conn refused | L2: replace `sed -i` with `grep -v` + `cat >` redirect | Applied | Pending (Cycle 25 not yet run) |

## Layer Trajectory
- Entered this window at Layer 3 (Cycles 20–22), then Layer 2 (Cycles 23–24)
- Net advancement: **-1** (apparent regression, but Layer 2 is a newly-discovered sub-failure of the seeding path — not a higher-layer break)
- Underlying momentum: genuine forward progress each cycle; each fix correctly unblocked the next sub-issue in the seeding chain
- Total pods Running (Cycle 24 / Cycle 25 report): ~67 Running / ~55 not Running — unchanged across all 5 cycles

## Patterns Detected

### Harbor seeding chain — 5-cycle incremental debug
- **Evidence:** Cycles 20–24 each made a correct diagnosis and targeted fix, but the seeding path has multiple sequential bugs: (20) docker networking isolated from host → (21) host DNS/sudo no-terminal → (22) pod IP vs service ClusterIP → (23) `sed -i` cannot atomic-rename bind-mounted file → (24) fix applied. Each cycle's error message was genuinely different. No circular failure.
- **Impact:** Keycloak has had zero images in Harbor for 15+ hours. Every layer above 3 is downstream of this. Layer trajectory is stalled but each cycle made real progress.
- **Recommendation:** If Cycle 25 still fails after the `grep -v`/`cat >` fix lands, the seeding architecture is fundamentally broken and should be replaced with a single approach: pre-copy all required images into a kind node local volume during cluster bootstrap (before deploy.sh runs) instead of live-seeding via a port-forward during deploy. This is a bigger change but eliminates the entire networking/DNS/bind-mount problem class.

### `sed: cannot rename` signal missed for 4 cycles
- **Evidence:** `sed: cannot rename /etc/sedXXX: Device or resource busy` appears in the deploy output of **every** cycle (20–24), 3 lines per cycle, before the seeding block. Counsel's diagnosis in Cycles 20–22 focused on crane/docker errors further down the log and correctly identified different root causes each cycle — so missing the sed error was not incorrect, just delayed. Cycle 25's directive correctly identified it as root cause once two IPs appeared in /etc/hosts.
- **Impact:** One extra cycle (23→24) consumed on a symptom that the sed errors had already explained.
- **Recommendation:** Add a step to counsel's protocol: before diagnosing the primary error message, scan the deploy output top-to-bottom for shell-level errors (`sed: cannot rename`, `sudo: a terminal is required`, `mount: permission denied`) that appear **before** the main failure. These are often the actual root cause being masked by downstream failure.

### Pre-emptive batching rule not firing — 5 INFRA_INCOMPATIBLE items queued
- **Evidence:** The following have appeared in EVERY cycle's pod list for 5+ cycles with no directive issued:
  - `falco-driver-loader` Init:CrashLoopBackOff (linuxkit eBPF — 15+ cycles total)
  - `tempo` CrashLoopBackOff (rook-ceph DNS absent — 5+ cycles in this window)
  - `thanos-query` ImagePullBackOff (`bitnami/thanos:0.36.0-debian-12-r1` not found — 5+ cycles)
  - `gitlab-redis-master-0` ImagePullBackOff (`bitnami/redis:6.2.7-debian-11-r11` not found — 5+ cycles)
  - `opa-gatekeeper` FAILED (CRD race — 4+ cycles in this window)
  - `sonarqube-postgresql` ImagePullBackOff (`bitnami/postgresql:11.14.0-debian-10-r22` not found)
  - `reportportal-rabbitmq` FAILED (Bitnami password upgrade error — 3+ cycles)
  - Multiple PVCs requesting `ceph-block` StorageClass (grafana, gitlab-gitaly, sonarqube, code-server) — never binds in kind
- Counsel listed these as "## Pre-emptive warnings" in directives every cycle — but **this section is not the "Pre-emptive Fix" block format described in the batching rule**. Surgeon acts on directive content only; comments are ignored.
- **Impact:** When seeding clears (Cycle 25 or 26), all eight failures surface immediately. Each costs a cycle if addressed one at a time — that's 8 cycles of known failures vs. 2–3 if batched.
- **Recommendation:** (1) Add a clarification to counsel.md: listing items under "## Pre-emptive warnings" does NOT schedule them for fixing — surgeon ignores it. To trigger a fix, use the explicit "## Pre-emptive Fix" block format with batching conditions met. (2) The batching conditions ARE met for all 8 items above. Counsel should batch 2 per cycle using the "Pre-emptive Fix" block as soon as the primary seeding fix is confirmed working.

## Prompt Adjustments

### counsel.md — Step 2: scan deploy output for shell-level errors first

**Evidence:** `sed: cannot rename` appeared 5 consecutive cycles; took until Cycle 25 to diagnose. Earlier detection = earlier fix.

**Change:** Added a scan instruction to Step 2 of the protocol ("Assess the root cause").

**Text added** (after "What specific error does the operator report show?"):
> Before examining pod-level errors, scan the deploy output from **top to bottom** for shell-level errors (`sed: cannot rename`, `sudo: a terminal is required`, `mount: permission denied`, `curl: (`) that appear before the first `WARN:` or `FAILED` line. These precede and often cause the downstream failure — diagnose the shell error first.

---

### counsel.md — Pre-emptive batching: clarify that warning comments don't trigger fixes

**Evidence:** 5 cycles of "## Pre-emptive warnings" sections in directives that surgeon never acted on. Batching rule existed but wasn't used effectively.

**Change:** Added one sentence to the Pre-emptive batching paragraph in the "Be pragmatic about infra-incompatible components" section.

**Text added** (at end of the pre-emptive batching paragraph):
> Note: listing items in a "## Pre-emptive warnings" comment block in the directive does NOT queue them for fixing — surgeon acts on directive content only. Use the "Pre-emptive Fix" section format described above.

---

Both changes are minimal, targeted, and supported by 5 cycles of evidence.

## Escalation
NONE

---

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
