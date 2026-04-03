# Changelog — Cycle 38

## Observed
- Layer: 6 (Istio, OPA-Gatekeeper, Falco, Trivy — security mesh)
- Service: trivy-operator (Layer 6, fourth and final component — not yet deployed)
- Category: DEPENDENCY_MISSING (Trivy not started; Istio + OPA-Gatekeeper + Falco all healthy)
- Evidence:
  - All pods Running or Completed — no failures in snapshot
  - No `trivy-operator` helm release; no `trivy-system` namespace
  - `trivy-operator/values.yaml` had `global.storageClass: "ceph-block"` (same pattern as prior cycles)
  - OPA Gatekeeper `require-labels` constraint (enforcing `app` and `tier` on Deployments) had no namespace exclusions — would block upstream trivy-operator Deployment
  - OPA Gatekeeper `require-resource-limits` would block trivy-operator operator controller pod (upstream chart has `resources: {}` for the controller)

## Applied
- Fixed `global.storageClass: "ceph-block"` → `"local-path"` in `platform/charts/trivy-operator/values.yaml`
- Added `resources:` for operator controller pod to `platform/charts/trivy-operator/values.yaml` (cpu 100m-500m, memory 128Mi-512Mi)
- Added `requireLabelsExcludedNamespaces: [trivy-system]` to `platform/charts/opa-gatekeeper/values.yaml`
- Updated `constraint-require-labels.yaml` template to emit `spec.match.excludedNamespaces` from the new value
- Upgraded OPA-Gatekeeper (revision 3→4) to apply the constraint update with trivy-system exclusion
- Installed trivy-operator (revision 1); operator pod 1/1 Running, scan jobs firing immediately
- Files: `platform/charts/trivy-operator/values.yaml`, `platform/charts/opa-gatekeeper/values.yaml`, `platform/charts/opa-gatekeeper/templates/constraint-require-labels.yaml`

## Validated
```
helm lint platform/charts/trivy-operator/
→ 1 chart(s) linted, 0 chart(s) failed

helm lint platform/charts/opa-gatekeeper/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate: PASS

helm upgrade opa-gatekeeper ... --set constraintsEnabled=true → STATUS: deployed REVISION: 4

kubectl get k8srequirelabels require-labels -o yaml | grep -A5 match:
→ match:
→   excludedNamespaces:
→   - trivy-system

helm upgrade --install trivy-operator ... → STATUS: deployed REVISION: 1

kubectl get pods -n trivy-system
→ trivy-operator-77fdcfdd67-hdvzh   1/1   Running   0   21s
→ scan jobs: Init:0/1 (ephemeral scan pods firing — expected)
```

## Expect Next Cycle
- trivy-operator: 1/1 Running, VulnerabilityReport CRDs populated with scan results
- Layer 6 is complete: Istio ✓, OPA-Gatekeeper ✓, Falco ✓, Trivy ✓
- Next layer: Layer 7 (Backstage, mailpit — developer experience)
