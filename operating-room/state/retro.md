# Retro — After Cycle 44

## Progress

| Cycle | First Failure | Directive Target | Surgeon Action | Result |
|-------|---------------|------------------|----------------|--------|
| 40 | L3 — keycloak-postgresql ErrImagePull (`harbor.../bitnami/postgresql:16.3.0-debian-12-r14`, 19h) | L3 keycloak-postgresql, IMAGE_ISSUE | `PG_TAG="16"` → `"16.3.0-debian-12-r14"` to seed the full tag | No improvement — tag never seeded (crane silently failing); pod still pulls chart default |
| 41 | L3 — keycloak-postgresql ImagePullBackOff (same tag, 19h) | L3 keycloak-postgresql, CONFIG_ERROR | Removed `keycloak.` prefix from `--set` path (line 283) | No improvement — wrong direction; `keycloak.` prefix is the sub-chart alias, not spurious |
| 42 | L3 — keycloak-postgresql ImagePullBackOff (same tag, 19h) | L3 keycloak-postgresql, CONFIG_ERROR | Restored `keycloak.` prefix on line 283 | Timing lag; fix was correct but pod was never restarted by helm (StatefulSet) |
| 43 | L3 — keycloak-0 ImagePullBackOff (`harbor.../bitnami/keycloak:24.0.5-debian-12-r0`, 19h) | L3 seeding mechanism, IMAGE_ISSUE | Replaced crane with host `docker pull`/`docker push` | Seeding mechanism now correct; tag `24.0.5-debian-12-r0` is retired — pull fails silently |
| 44 | L3 — keycloak-0 ImagePullBackOff (`harbor.../bitnami/keycloak:24.0.5-debian-12-r0`, 20h) | L3 KEYCLOAK_TAG, IMAGE_ISSUE | Hardcoded `KEYCLOAK_TAG="24.0.5-debian-12-r8"`, added `--set keycloak.image.tag` | Pending — first cycle with this fix; Cycle 45 report confirms same state (fix just landed) |

## Layer Trajectory

- Started at Layer 3, still at Layer 3 after 5 cycles
- Net advancement: **0 (stagnant)**
- Total pods Running (Cycle 45 latest report): ~73 Running / ~113 total
- No secondary layer movement — all DEGRADED layers (4–7) unchanged

## Patterns Detected

### Silent harbor seeding failures masked by "ready ✓" (Cycles 40–44)
- **Evidence:** Every cycle, `==> harbor: ready ✓` appears in the deploy output regardless of whether images were actually seeded. The crane-based seeding used `|| log "WARN: ..."` which discarded the failure. The operator report format had no step to verify harbor image presence. The true root cause (images absent from harbor) was not identified until Cycle 43 — 4+ cycles after it began affecting pods.
- **Impact:** 3 cycles (40–42) were spent on `--set` path manipulation for an override that was reaching a sub-chart that never had its image. All those fixes were correct mechanics applied to the wrong root cause.
- **Recommendation:** Add a harbor verification step to operator.md — after the seeding loop, probe harbor for each expected image tag and surface failures explicitly. A silent WARN is not a skip; it is a blocker.

### --set path oscillation (Cycles 41–42)
- **Evidence:** Cycle 41 removed `keycloak.` prefix from `postgresql.image.tag`; Cycle 42 restored it. Two cycles consumed. The evidence that `keycloak.` was correct (line 284's working `keycloak.postgresql.primary.podAnnotations.forceRestart`) was present in both cycles' reports.
- **Impact:** 2 cycles lost. The correct fix (Cycle 42) was available in Cycle 41 had counsel cross-referenced the working path on line 284.
- **Recommendation:** Add to counsel.md: before recommending a `--set` path change, verify it against at least one other working `--set` or values path in the same helm invocation for that component.

### Queued structural failures growing (Cycles 40–44, all 5)
- **Evidence:** gitlab StatefulSet immutable field, opa-gatekeeper CRD ordering, reportportal RabbitMQ password, tempo MinIO credential failure, thanos `docker.io` ImagePullBackOff — all appear in every cycle, never targeted (correctly, per layer rule).
- **Impact:** None now — correctly suppressed. But once Layer 3 clears, ALL of these will surface simultaneously as the new first failures. The loop has no pre-queued fixes for them.
- **Recommendation:** Cycle 45 counsel should include pre-emptive fixes per existing "Pre-emptive batching" rule: gitlab StatefulSet delete + reinstall, and thanos/sonarqube image routing through harbor. These have been visible 5+ cycles.

## Prompt Adjustments

### operator.md — add harbor image verification step
Added as Step 2.5 between "Quick layer status" and "Diagnose failures":

```
### 2.5. Verify harbor seeding (if harbor is UP)

Check that the expected images were actually seeded. For any image the seeding loop
attempted, verify presence by calling the harbor API via the port-forward:

    curl -sk -u admin:${HARBOR_ADMIN_PASS} \
      "http://localhost:${HARBOR_LOCAL_PORT}/api/v2.0/repositories/bitnami/artifacts?page_size=5" \
      | python3 -m json.tool 2>/dev/null | grep '"name"' | head -10

If the seeding loop emitted any WARN lines or if the above returns no matching tag,
report the seeding failure explicitly — do NOT summarize it as "harbor: ready".
```

**Why:** Seeding failures were invisible for at least 4 cycles. The `|| log "WARN"` pattern in deploy.sh suppresses non-zero exits from `docker pull`. The operator must surface these as failures, not skip them.

### counsel.md — verify --set paths against working examples
Added to Section 3, before "Be pragmatic about infra-incompatible components":

> **Verify `--set` paths before directing path changes.** Before recommending a change to a `helm upgrade --set` path, check the same invocation for other working `--set` paths targeting the same sub-chart. If `--set A.B.C` is confirmed working, then `--set A.B.D` is the correct form for a sibling value. Do not change the prefix without evidence from the working example.

**Why:** Cycles 41–42 oscillated because counsel changed `keycloak.postgresql.image.tag` to `postgresql.image.tag` without noticing that `keycloak.postgresql.primary.podAnnotations.forceRestart` was working in the same invocation. The rule closes this gap.

## Escalation

NONE. The Cycle 44 fix (hardcoded `KEYCLOAK_TAG="24.0.5-debian-12-r8"` with matching `--set keycloak.image.tag`) is the right direction. The seeding mechanism is now correct (host docker push, not crane). If Cycle 45's next report still shows keycloak ImagePullBackOff, counsel should verify the tag is reachable in harbor before trying another tag change — the operator verification step will surface this.
