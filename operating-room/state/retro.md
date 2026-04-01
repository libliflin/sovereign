# Retro — After Cycle 39

## Progress

| Cycle | First Failure | Directive Target | Surgeon Action | Result |
|-------|---------------|------------------|----------------|--------|
| 35 | Layer 3 — keycloak ImagePullBackOff (bitnami/postgresql:16.3.0-debian-12-r14) | Layer 3, keycloak, IMAGE_ISSUE | crane source: bitnamilegacy → docker.io/bitnami | No improvement — tag absent on docker.io/bitnami |
| 36 | Layer 3 — keycloak ImagePullBackOff (same) | Layer 3, keycloak, IMAGE_ISSUE | crane source: docker.io/bitnami → ghcr.io/bitnami | No improvement — tag absent on ghcr.io |
| 37 | Layer 3 — keycloak ImagePullBackOff (same) | Layer 3, keycloak, CONFIG_ERROR | crane source: ghcr.io/bitnami → oci.registry.bitnami.com/bitnami | No improvement — tag absent on oci.registry.bitnami.com |
| 38 | Layer 3 — keycloak ImagePullBackOff (same) | Layer 3, keycloak, IMAGE_ISSUE | PG_TAG: 16.3.0-debian-12-r14 → 16; crane source → docker.io/bitnami | No pod restart — Helm state drift; StatefulSet never patched in Kubernetes |
| 39 | Layer 3 — keycloak UPGRADE FAILED + ImagePullBackOff | Layer 3, keycloak, CHART_ERROR | Added --set forceRestart=$(date +%s) to keycloak install_chart | FAILED — Helm inferred int64 from bare integer; annotation requires string |

## Layer Trajectory

- Started at Layer 3, still at Layer 3 after 5 cycles
- Net advancement: **0 (stagnant)**
- Total pods Running (latest report, Cycle 39): ~78 Running, ~35 non-Running
- Minor secondary movement: falco-f957h recovered to Running in Cycle 37 (oscillated back to Error/Running across cycles 38–39)

## Patterns Detected

### Registry cycling exhausted 3 cycles before tag was considered (Cycles 35–37)
- **Evidence:** Three consecutive cycles tried distinct registry sources (docker.io/bitnami → ghcr.io/bitnami → oci.registry.bitnami.com) for the same tag `16.3.0-debian-12-r14`. All three failed. The tag-change fix (PG_TAG→16) did not arrive until Cycle 38.
- **Impact:** 3 cycles lost. The rule "Never issue the same image-source directive twice" was technically satisfied (each source was distinct) while the spirit was violated — all three sources were being asked for the same retired tag.
- **Recommendation:** Add a two-source cap to counsel.md Section 5: if two distinct sources fail for the same tag, stop changing the source and change the tag instead. (Prompt change applied — see below.)

### Helm `--set` typed integer rejected by Kubernetes annotation (Cycle 39)
- **Evidence:** `failed to create typed patch object (keycloak/keycloak-postgresql; apps/v1, Kind=StatefulSet): .spec.template.metadata.annotations.forceRestart: expected string, got &value.valueUnstructured{Value:1775066426}` — `$(date +%s)` expanded to a bare integer; Helm's `--set` inferred int64; Kubernetes annotations require strings. The Cycle 40 directive correctly identifies `--set-string` as the fix.
- **Impact:** 1 cycle lost. The mechanism (pod-annotation to force pod-template hash change) was correct; only the Helm flag was wrong.
- **Recommendation:** Add to surgeon.md: when injecting timestamps or integers as annotation values via `helm upgrade`, use `--set-string`, not `--set`. (Prompt change applied — see below.)

### gitlab StatefulSet immutable field — queued but never addressed (Cycles 35–39)
- **Evidence:** The error `StatefulSet.apps "gitlab-gitaly" is invalid: spec: Forbidden: updates to statefulset spec...` appears in the deploy output of every cycle in this window — 5 cycles straight, 7+ consecutive total. It is blocked by the Layer 3 rule (never fix Layer 4 while Layer 3 is down) and noted in every directive's anti-patterns.
- **Impact:** None yet — correctly held. But once keycloak clears (Cycle 40 directive is the --set-string fix), this becomes the immediate Layer 4 primary. The fix is known: add `kubectl delete statefulset gitlab-gitaly -n gitlab --cascade=orphan` before the gitlab helm upgrade in deploy.sh.
- **Recommendation:** No prompt change. Counsel should queue this as the Cycle 41 primary once Cycle 40's keycloak fix lands and Layer 3 is confirmed UP.

## Prompt Adjustments

### counsel.md — two-source cap on registry cycling
Added after "Never issue the same image-source directive twice" in Section 5:

> **Two-source rule:** If two distinct registry sources have been tried for the same image tag and both failed, STOP changing the source. The tag is retired or wrong. Reclassify as IMAGE_ISSUE and change the tag. Do not try a third source.

**Why:** Three cycles (35–37) were lost because each registry was technically "different" so the existing rule didn't fire. An explicit numeric cap closes the loophole.

### surgeon.md — --set-string for annotation string values
Added to Section 3 "Make the fix" under Shell scripts:

> **Helm annotation strings:** When injecting a timestamp or numeric value as a Kubernetes annotation via `helm upgrade`, always use `--set-string` not `--set`. Helm's `--set` infers YAML scalar types: `$(date +%s)` becomes int64. Kubernetes annotation values must be strings. `--set-string` unconditionally coerces the value to string.

**Why:** Cycle 39 lost a full cycle to this Helm gotcha. It is non-obvious, will recur in future forceRestart patterns, and the fix is one word.

## Escalation

NONE. The loop is moving. The Cycle 40 fix (`--set` → `--set-string`) is correct and minimal. If keycloak-postgresql-0 does not restart after Cycle 40, the next diagnostic should verify that `keycloak.postgresql.primary.podAnnotations` is the correct values path in the Bitnami PostgreSQL subchart — if the path is wrong, the annotation lands in the wrong place and the pod template hash does not change.
