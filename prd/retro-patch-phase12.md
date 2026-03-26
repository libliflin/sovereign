# Retro Patch: Phase 12 — developer-portal
Generated: 2026-03-26T00:00:00+00:00

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 2 | 5 pts |
| Incomplete → backlog | 1 | 3 pts |
| Killed | 0 | — |

## 5 Whys: incomplete stories

### 027a: Helm chart — Backstage scaffold with Keycloak OIDC and ArgoCD app

- **Why 1**: Story didn't pass review → AC #9 "kubectl apply --dry-run=client -f argocd-apps/devex/backstage-app.yaml exits 0" failed with "no matches for kind Application in version argoproj.io/v1alpha1"
- **Why 2**: `kubectl apply --dry-run=client` requires CRDs to be registered in the cluster → kind-sovereign-test does not have ArgoCD CRDs installed
- **Why 3**: The story's test plan used `kubectl apply --dry-run=client` for an ArgoCD Application manifest without first ensuring the operator CRDs were available
- **Why 4**: The kind/setup.sh cluster setup does not install ArgoCD CRDs — it only provisions a bare cluster, so CRD-dependent dry-run checks always fail for operator resources
- **Why 5**: There is no documented validation pattern in CLAUDE.md for CRD-dependent manifests (ArgoCD Application, Crossplane XR, etc.) — the quality gate says "kubectl apply --dry-run=client" but that only works for core K8s resources, not custom resources

**Root cause**: The quality gate `kubectl apply --dry-run=client` is specified generically in CLAUDE.md but silently fails for custom resources (ArgoCD Application, Crossplane XR, etc.) unless the operator CRDs are pre-installed. The kind setup does not install any operator CRDs, so every ArgoCD Application manifest will fail this gate indefinitely.

**Decision**: Return to backlog. All 8 other ACs pass; only AC #9 needs fixing. Two valid resolutions: (a) install ArgoCD CRDs into kind-sovereign-test during setup, or (b) update the AC to use `python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]))"` for CRD-backed manifests. Remediation story added to fix the kind setup.

**Remediation story**: `054r-kind-argocd-crds` — Install ArgoCD CRDs into kind-sovereign-test so Application manifests can be validated with kubectl dry-run

---

## Flow analysis (Heijunka check)

- Sprint average story size: 2.7 pts
- Point distribution: {2: 1, 3: 2}
- Oversized (> 8 pts): 0
- Split candidates (5–8 pts): 0

No flow issues. All stories were correctly sized at ≤ 3 points. The single incomplete story was not a sizing problem — it was a tooling gap.

---

## Patterns discovered (add to CLAUDE.md LEARNINGS section)

- **`kubectl apply --dry-run=client` does NOT work for CRD-backed resources** (ArgoCD Application, Crossplane XR, etc.) unless the operator is installed in the target cluster. For ArgoCD Application manifests, use `python3 -c "import yaml, sys; [yaml.safe_load(d) for d in open(sys.argv[1]).read().split('---') if d.strip()]"` as the validation gate, OR pre-install the CRDs in kind-sovereign-test.
- **kind-sovereign-test is a bare cluster** — it only has what kind/setup.sh installs. Operator CRDs (ArgoCD, Crossplane, etc.) are not present. Any AC that requires dry-run of a CRD-backed manifest must either install the CRD first or use YAML-only validation.
- **Review ceremony notes are precise** — the reviewNotes for 027a specified exactly the fix needed (install ArgoCD CRDs OR switch to yaml.safe_load). When a story is returned with reviewNotes, the fix is usually 1–2 lines, not a reimplementation.

## Quality gate improvements

The CLAUDE.md quality gate currently states:
> "For ArgoCD apps: validate YAML with `kubectl apply --dry-run=client`"

This should be split into two cases:
- **Core K8s resources** (Deployment, Service, Ingress, PDB, etc.): `kubectl apply --dry-run=client` is correct
- **CRD-backed resources** (ArgoCD Application, Crossplane XR/XRC, etc.): use `python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())"` OR pre-install the CRD with `kubectl apply -f <crd-url>` before the dry-run check

## Velocity

| Increment | Points Accepted | Stories Accepted | Review Pass Rate |
|-----------|----------------|-----------------|-----------------|
| 11 (remediation) | 2 | 1/1 | 100% |
| 12 (developer-portal) | 5 | 2/3 | 67% |

Sprint 12 first-review pass rate: 33% (1 of 3 stories accepted on first review — 027b passed; 027a and 029 both required re-work).

Retro patch → `prd/retro-patch-phase12.md`
