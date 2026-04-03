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
