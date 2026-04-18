# Domain Map — Sovereign Platform

Every non-trivial problem in Sovereign spans multiple domains. When a bug or gap appears,
this map tells you which domain is authoritative and where the boundaries create confusion.

---

## Kubernetes / Helm
**Covers:** Chart structure, values templating, resource manifests, HA requirements (PDB, antiAffinity, replicaCount), ArgoCD App-of-Apps pattern.
**Authoritative source:** Helm docs, Kubernetes API docs, the HA gate (`scripts/ha-gate.sh`), `platform/charts/CLAUDE.md`.
**Boundary confusion:** A chart can lint cleanly and still deploy incorrectly (e.g., PDB with wrong selector). "Passes ha-gate.sh" is not the same as "deploys correctly to a live cluster." Kind integration tests are the next layer.

## GitOps / ArgoCD
**Covers:** App-of-Apps structure, sync policies, `revisionHistoryLimit`, application manifests in `argocd-apps/`.
**Authoritative source:** ArgoCD docs, `argocd-apps/` directory, the ArgoCD validate job in CI.
**Boundary confusion:** A chart can be valid Helm but not be reachable by ArgoCD if the `argocd-apps/<tier>/<service>-app.yaml` is missing or misconfigured. The CI job checks `revisionHistoryLimit` but not full sync validity.

## Autarky / Vendor System
**Covers:** Image sourcing, SHA-pinned vendoring, distroless builds, Harbor as the internal registry, rollout/rollback pipeline.
**Authoritative source:** `platform/vendor/CLAUDE.md`, `platform/vendor/VENDORS.yaml`, `platform/vendor/recipes/`, the autarky gate in CI and snapshot.
**Boundary confusion:** The autarky gate checks chart templates for external registry refs, but it does not verify that Harbor actually contains the images. "No external refs in templates" ≠ "images available in Harbor." On a fresh cluster before vendor build runs, images won't be present even if the gate passes.

## Cluster Contract
**Covers:** The `sovereign.dev/cluster/v1` schema, what fields are required vs. invariant, the validator.
**Authoritative source:** `contract/validate.py`, `contract/v1/`, the cluster-values.yaml format.
**Boundary confusion:** The contract declares `autarky.externalEgressBlocked: true` as an invariant — but this is a claim, not an enforcement. The field being present in cluster-values.yaml does not create a NetworkPolicy. The enforcement is separate (Istio + OPA + NetworkPolicy in charts). When auditing zero-trust claims, always distinguish: "field declared in contract" vs. "behavior enforced by running workloads."

## Security Mesh (Zero Trust)
**Covers:** Istio mTLS, OPA/Gatekeeper, Falco, Trivy, NetworkPolicy, Sealed Secrets, OpenBao.
**Authoritative source:** Individual chart docs, `docs/governance/sovereignty.md`, Istio docs, OPA docs.
**Boundary confusion:** Istio STRICT mode is declared in the Istio chart, but whether every service mesh peer actually honors it depends on PeerAuthentication objects per-namespace. "Istio installed" ≠ "mTLS enforced everywhere." The Security Auditor's paranoia is only satisfied when the per-namespace objects exist.

## Bootstrap / Cluster Provisioning
**Covers:** VPS provisioning, K3s installation, kube-vip, Cilium, the kind local cluster.
**Authoritative source:** `cluster/CLAUDE.md`, `cluster/kind/bootstrap.sh`, provider scripts.
**Boundary confusion:** Bootstrap scripts are tested statically only (shellcheck). Their actual behavior on real VPS is not CI-tested. "shellcheck passes" ≠ "bootstrap works on your Hetzner nodes." Provider-specific quirks (Ubuntu version, firewall rules, SSH config) are outside the static test surface.

## Front Door / Ingress
**Covers:** Cloudflare Tunnel (default), the 5-hook front door interface, ingress controllers.
**Authoritative source:** `docs/providers/cloudflare-setup.md`, `docs/providers/front-door-custom.md`, `bootstrap/frontdoor/`.
**Boundary confusion:** The kind cluster has no front door — services are accessed via `kubectl port-forward` or NodePort. The Production front door is Cloudflare Tunnel. These are different paths with different assumptions. An error that makes sense in one context (no tunnel in kind) may be confusing in the other.

## Sprint / Ceremony System
**Covers:** `prd/manifest.json`, `prd/backlog.json`, `prd/constitution.json`, the ralph ceremony scripts (`scripts/ralph/ceremonies.py`), constitutional gates G1/G2/G6/G7.
**Authoritative source:** `prd/` directory, `scripts/ralph/`, the snapshot's constitutional gate checks.
**Boundary confusion:** The ceremony system is itself a platform component — it can break, and when it does, it may not be obvious whether the block is in the ceremony scripts (G1) or in the underlying project state (G2/G6/G7). Always check the snapshot's gate section first.

---

## Cross-Domain Problem Patterns

**"The chart passes CI but doesn't work."**
CI validates Helm structure and static assertions. Actual deployment to a cluster (even kind) is not automated in CI. If a chart passes all gates but fails to deploy, the gap is in the integration layer — kind smoke tests are the next check.

**"The autarky gate passes but images are missing."**
Autarky gate checks template content. Harbor population is separate. A fresh cluster after bootstrap.sh will not have Harbor-hosted images until the vendor build pipeline runs.

**"The contract says egress is blocked but it isn't."**
`autarky.externalEgressBlocked: true` is a contract invariant (declared value) not an enforced constraint. Enforcement requires NetworkPolicy + Istio AuthorizationPolicy per namespace. The Security Auditor should check both the contract field and the actual manifest presence.

**"Shellcheck passes but the script fails on the target OS."**
Shellcheck is static analysis. Provider-specific behavior (Hetzner API quirks, Ubuntu version differences) is outside shellcheck's reach. The Bootstrap Validate job catches structural issues; production environment issues require manual testing.
