# Changelog — Cycle 36

## Observed
- Layer: 6 (Istio, OPA-Gatekeeper, Falco, Trivy — security mesh)
- Service: opa-gatekeeper (Layer 6, second component — not yet deployed)
- Category: DEPENDENCY_MISSING (Layer 6 second component not started; all lower layers and Istio healthy)
- Evidence:
  - All pods Running or Completed — no failures in snapshot
  - Istio deployed and healthy (istiod 2/2 Running, STRICT PeerAuthentication active)
  - No `opa-gatekeeper` helm release, no `gatekeeper-system` namespace
  - `values.yaml` had `storageClass: "ceph-block"` (same pattern corrected in cycle 35 for istio)
  - Constraint templates had no `constraintsEnabled` guard — required for two-pass install

## Applied
- Fixed `global.storageClass: "ceph-block"` → `"local-path"` in `platform/charts/opa-gatekeeper/values.yaml`
- Added `constraintsEnabled: false` flag to `values.yaml`
- Wrapped all 3 constraint files with `{{- if .Values.constraintsEnabled }}` guard (ConstraintTemplate files untouched — safe in pass 1)
- Pass 1: installed `opa-gatekeeper` with `constraintsEnabled=false` — controller (3 replicas), audit, and ConstraintTemplates deployed
- Waited for Gatekeeper controller to process ConstraintTemplates and establish K8s* CRDs
- Pass 2: upgraded with `constraintsEnabled=true` — all 3 constraints active with `deny` enforcement
- Files: `platform/charts/opa-gatekeeper/values.yaml`, `templates/constraint-no-privilege-escalation.yaml`, `templates/constraint-require-labels.yaml`, `templates/constraint-require-resource-limits.yaml`

## Validated
```
helm lint platform/charts/opa-gatekeeper/
→ 1 chart(s) linted, 0 chart(s) failed

autarky gate: PASS

helm upgrade --install opa-gatekeeper ... --set constraintsEnabled=false
→ STATUS: deployed REVISION: 1

kubectl get pods -n gatekeeper-system
→ gatekeeper-audit-59cdddbc9d-spg7f                1/1   Running   0
→ gatekeeper-controller-manager-6d4f7fcc4c-4fgmn   1/1   Running   0
→ gatekeeper-controller-manager-6d4f7fcc4c-bfzp4   1/1   Running   0
→ gatekeeper-controller-manager-6d4f7fcc4c-tz4rb   1/1   Running   0

kubectl get constrainttemplates
→ k8snoprivilegeescalation, k8srequirelabels, k8srequireresourcelimits

kubectl wait --for=condition=Established crd/k8snoprivilegeescalation.constraints.gatekeeper.sh → condition met (all 3)

helm upgrade opa-gatekeeper ... --set constraintsEnabled=true → STATUS: deployed REVISION: 2

kubectl get constraints -A
→ k8snoprivilegeescalation/no-privilege-escalation   deny
→ k8srequirelabels/require-labels                    deny
→ k8srequireresourcelimits/require-resource-limits   deny
```

## Expect Next Cycle
- OPA-Gatekeeper remains healthy (4 pods Running, 3 constraints enforcing deny)
- Next Layer 6 component: Falco (runtime security / syscall detection)
- Falco requires a real kernel — Lima VMs have kernel 6.8.0-101-generic (real kernel, eBPF capable)

---

# Changelog — Cycle 35

## Retro Analysis (Cycles 30–34)

| Cycle | Layer | Issue | Outcome |
|-------|-------|-------|---------|
| 30 | 5 (Jaeger) | storageClass/ingress/badger config errors | Fixed, Jaeger deployed |
| 31 | 2 (Harbor) | arm64 SIGSEGV — wrong arch images | D1 applied: Zot replaces Harbor |
| 32 | 5 (Jaeger/Cassandra) | OOM from unused Cassandra subchart | Fixed, ~3GB freed |
| 33 | 0 (sovereign-2 DiskPressure) | 22GB Harbor PVC consuming disk | Freed, DiskPressure cleared |
| 34 | 1 (openbao-0 503) | Released Harbor PVs driving helper-pod loop | PVs deleted, loop stopped |

**Assessment:** Steady forward progress — no layer stuck 3+ cycles. Layers 0–5 fully green. openbao 2/3 nodes healthy (quorum satisfied). Ready to advance to Layer 6.

---

## Observed
- Layer: 6 (Istio, OPA-Gatekeeper, Falco, Trivy — security mesh)
- Service: istio (not yet deployed)
- Category: DEPENDENCY_MISSING (Layer 6 not started; all lower layers healthy)
- Evidence:
  - All pods Running or Completed — no failures in snapshot
  - Layers 0–5 green: cert-manager, sealed-secrets, openbao, zot, keycloak, forgejo, argocd, prometheus-stack, victorialogs, jaeger all deployed
  - Layer 6 has 0 helm releases
  - values.yaml had `storageClass: "ceph-block"` — corrected to `local-path` before install

## Applied
- Fixed `global.storageClass: "ceph-block"` → `"local-path"` in `platform/charts/istio/values.yaml`
- Installed `istio` release in `istio-system` namespace (revision 1)
  - istio/base CRDs installed
  - istiod control plane: 2 replicas, both Running
  - PeerAuthentication `default` STRICT mode created in istio-system
  - Gateway `sovereign-gateway` created in istio-system
- Files: `platform/charts/istio/values.yaml`

## Validated
```
helm lint platform/charts/istio/
→ 1 chart(s) linted, 0 chart(s) failed

helm upgrade --install istio platform/charts/istio/ -n istio-system --create-namespace --timeout 120s --wait
→ STATUS: deployed REVISION: 1

kubectl get pods -n istio-system
→ istiod-5df7c7f97c-rnw8g   1/1   Running   0
→ istiod-5df7c7f97c-x8hgt   1/1   Running   0

kubectl get peerauthentication -n istio-system
→ default   STRICT   35s

kubectl get gateway.networking.istio.io -n istio-system
→ sovereign-gateway   35s

autarky gate:
→ PASS
```

## Expect Next Cycle
- Istio remains healthy (istiod 2/2 Running)
- Next Layer 6 component: OPA-Gatekeeper (policy enforcement)
- OPA-Gatekeeper requires two-pass install (CRDs first, then constraints)
