# Changelog — Cycle 37

## Observed
- Layer: 6 (Istio, OPA-Gatekeeper, Falco, Trivy — security mesh)
- Service: falco (Layer 6, third component — not yet deployed)
- Category: DEPENDENCY_MISSING (Falco not started; Istio + OPA-Gatekeeper healthy)
- Evidence:
  - All pods Running or Completed — no failures in snapshot
  - Istio: istiod 2/2 Running, STRICT PeerAuthentication active
  - OPA-Gatekeeper: 4 pods Running, 3 constraints enforcing deny
  - No `falco` helm release; no `falco` namespace
  - `falco/values.yaml` had `storageClass: "ceph-block"` (same pattern as cycles 35–36)
  - OPA Gatekeeper `no-privilege-escalation` constraint had no namespace exclusions — would block Falco's `privileged: true` DaemonSet pods
  - OPA Gatekeeper `require-resource-limits` would block falcoctl sidecar/init containers (upstream chart has `resources: {}`)

## Applied
- Fixed `global.storageClass: "ceph-block"` → `"local-path"` in `platform/charts/falco/values.yaml`
- Added resource limits to falcoctl sidecar and init containers in `platform/charts/falco/values.yaml` (falcoctl.artifact.follow.resources, falcoctl.artifact.install.resources, driver.loader.initContainer.resources)
- Added `privilegeEscalationExcludedNamespaces: [falco]` to `platform/charts/opa-gatekeeper/values.yaml`
- Updated `constraint-no-privilege-escalation.yaml` template to emit `spec.match.excludedNamespaces` from the new value
- Upgraded OPA-Gatekeeper (revision 3) to apply the constraint update with falco namespace exclusion
- Installed Falco DaemonSet (revision 1→2 after resource fix); all 3 pods 2/2 Running
- Files: `platform/charts/falco/values.yaml`, `platform/charts/opa-gatekeeper/values.yaml`, `platform/charts/opa-gatekeeper/templates/constraint-no-privilege-escalation.yaml`

## Validated
```
helm lint platform/charts/falco/
→ 1 chart(s) linted, 0 chart(s) failed

helm lint platform/charts/opa-gatekeeper/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate: PASS

helm upgrade opa-gatekeeper ... --set constraintsEnabled=true → STATUS: deployed REVISION: 3

kubectl get k8snoprivilegeescalation no-privilege-escalation -o yaml | grep -A5 match:
→ match:
→   excludedNamespaces:
→   - falco

helm upgrade --install falco platform/charts/falco/ -n falco → STATUS: deployed REVISION: 2

kubectl get pods -n falco
→ falco-5sph2   2/2   Running   0   39s
→ falco-r9www   2/2   Running   0   39s
→ falco-rsxbc   2/2   Running   0   39s
```

## Expect Next Cycle
- Falco DaemonSet: 3/3 pods Running on all nodes (runtime syscall monitoring active, JSON→stdout for Loki)
- Next Layer 6 component: Trivy (vulnerability scanning / admission)
- Layer 6 will be complete after Trivy
