# Domains

The knowledge domains this project spans, their authoritative sources, and where boundaries create confusion.

---

## Domain Map

### Kubernetes / Helm

**What it covers:** Pod scheduling, resource management, networking primitives, CRD management, HA patterns (PDB, podAntiAffinity, replicaCount), storage classes, namespace isolation.

**Authoritative source:** Kubernetes docs, upstream chart values.yaml for wrapper charts.

**Where it creates confusion:**
- `kubectl apply --dry-run=client` silently fails for CRD-backed resources (ArgoCD Applications, Crossplane XRs) — use YAML-only validation instead
- Upstream wrapper charts (bitnami, etc.) may have PDB/affinity support under non-obvious keys — always check the upstream values.yaml before writing templates
- `helm template` renders Go template expressions; ACs that grep for `{{ .Values.* }}` will never match rendered output

### GitOps / ArgoCD

**What it covers:** App-of-Apps pattern, ApplicationSet, sync policies, revision history, health checks.

**Authoritative source:** ArgoCD docs, the Application CRD spec.

**Where it creates confusion:**
- ArgoCD CRDs are not installed in the kind cluster — `kubectl apply --dry-run` fails for Application manifests; use Python YAML parse only
- `revisionHistoryLimit: 3` is a sovereign invariant, not an ArgoCD default — omitting it passes `helm lint` but fails CI
- Domain injection is via `spec.source.helm.parameters`, not `valueFiles` — these look equivalent but behave differently at runtime

### Service Mesh / Zero Trust (Istio)

**What it covers:** mTLS via PeerAuthentication, traffic policies, Envoy sidecars, Kiali topology.

**Authoritative source:** Istio docs, the PeerAuthentication CRD spec.

**Where it creates confusion:**
- G8 checks the default namespace policy in istio-system but does NOT check per-namespace overrides in service charts — a service chart that disables mTLS for its namespace is not caught by G8
- `PERMISSIVE` mode looks like it works (traffic flows) but breaks the zero-trust invariant silently

### Sovereignty / Autarky

**What it covers:** License policy (Apache 2.0/MIT/BSD approved, BSL blocked), external registry prohibition, distroless images, vendor build pipeline.

**Authoritative source:** `docs/governance/license-policy.md`, `docs/governance/sovereignty.md`, `platform/vendor/VENDORS.yaml`, `contract/v1/cluster.schema.yaml`.

**Where it creates confusion:**
- G6 checks `platform/charts/*/templates/` — it does NOT check `cluster/kind/charts/*/templates/` or ArgoCD app manifests
- The autarky grep in `validate.yml` checks `values.yaml` image.repository for hardcoded external registries, but only for top-level image keys — subchart images may not be checked
- During bootstrap, `imageRegistry.internal: ""` is intentional — the contract validator allows an empty string for this field
- BSL (Business Source License) is blocked; SSPL is blocked; AGPL needs case-by-case review

### Constitutional Gates

**What it covers:** Machine-checkable invariants that protect themes. Stop-the-line enforcement.

**Authoritative source:** `prd/constitution.json`. Indicators are the authoritative test commands — not CLAUDE.md descriptions.

**Where it creates confusion:**
- A gate that always passes provides no signal — see the `_retired` section in constitution.json for examples of gates that were removed for this reason
- G9 reports non-compliant charts but requires `ha-gate.sh` to exit 0 — a single failing chart blocks everything
- Gates check structure, not runtime behavior: G8 verifies the chart renders STRICT, but doesn't verify a running cluster enforces it

### Sprint / Ceremony System (Ralph)

**What it covers:** Increment lifecycle, story schema, ceremony sequencing, SMART scoring, gate evaluation.

**Authoritative source:** `prd/manifest.json` (active sprint), `prd/constitution.json` (gates), `scripts/ralph/ceremonies/` (ceremony behavior), `docs/state/agent.md` (current state).

**Where it creates confusion:**
- "Phase" is the old vocabulary — use "increment" in all new code and documents
- `passes: true` means the implementer ran the ACs and saw them pass — not that the review ceremony accepted the story
- `reviewed: true` is set only by the review ceremony, never by the implementer
- Pre-accepted stories (`passes: true, reviewed: true`) consume sprint capacity without requiring implementation — if they exceed 50% of capacity, the sprint won't reach implementation stories
- Stories with `smart.achievable < 4` must be split before entering a sprint

### Shell Scripting

**What it covers:** Bootstrap scripts, ha-gate.sh, kind smoke tests, vendor scripts.

**Authoritative source:** shellcheck 0.10.0 (CI version), bash 3.2 compatibility (macOS target).

**Where it creates confusion:**
- `set -euo pipefail` + grep on an optional YAML field = silent failure when the field is absent — always add `|| true` to optional greps
- `local x=$(cmd)` triggers SC2155 — split into `local x; x=$(cmd)`
- Empty array with `set -u`: use `"${ARRAY[@]+"${ARRAY[@]}"}"`
- `pipefail` subshell behavior differs between bash 3.2 (macOS) and GNU bash 5.x
- Scripts that iterate `platform/charts/` must handle `_globals` (underscore-prefixed, not a real chart)

### Observability Stack (Prometheus/Grafana/Loki/Tempo/Thanos)

**What it covers:** Metrics, logs, traces, Grafana datasources, Falco events, long-term retention via Thanos.

**Authoritative source:** Upstream chart values.yaml for each component, Grafana datasource ConfigMap format.

**Where it creates confusion:**
- Observability charts must include a Grafana datasource ConfigMap in templates/ for auto-registration — `helm template | grep -i datasource` is the gate
- Loki Simple Scalable and Tempo distributed are multi-component charts — their PDB count is > 1; the count check must use `>= N`, not `== 1`

---

## Boundary Confusion Matrix

| Symptom | Might look like... | Actually is... |
|---------|-------------------|----------------|
| `kubectl apply --dry-run` fails for ArgoCD app | Helm template error | CRDs not in kind cluster — use YAML parse |
| G6 passes but image pulls fail at runtime | False gate | G6 only checks chart templates, not values.yaml or subchart images |
| `shellcheck` passes locally, fails in CI | Environment difference | CI uses shellcheck 0.10.0; local may be different version |
| A gate never fires | Good health | May be vacuous — check the rationale, consider retiring |
| story passes implement, fails review | Implementation error | AC was wrong at authoring time — AC authoring is a first-class concern |
| `helm template` grep returns nothing | Pattern not in chart | Pattern uses Go template syntax; grep for the resolved value or key name instead |
