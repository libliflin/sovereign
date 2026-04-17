# Sovereign Platform Constitution

A fully self-hosted, zero-trust Kubernetes infrastructure stack. Clone it, fill in a
config file, and get a complete production-grade platform. No cloud vendor lock-in.

Repo: https://github.com/libliflin/sovereign
Dogfood domain: sovereign-autarky.dev
Architecture: ArgoCD App-of-Apps, Helm charts, Crossplane compositions.

---

## Themes — Why This Project Exists

**T1 Sovereignty.** Zero dependency on any cloud provider, proprietary service, or
single-vendor project that could change terms or revoke access. All components use
permissive-licensed (Apache 2.0/MIT/BSD), foundation-governed software. The platform
runs on any bare-metal or VPS without a cloud account. No data leaves the cluster
without explicit operator configuration. The Vault-to-OpenBao migration is the
reference precedent.

**T2 Zero Trust.** No implicit trust anywhere. Every connection is authenticated,
encrypted, and authorized by policy. mTLS everywhere (Istio STRICT), deny-all
NetworkPolicy with explicit allows, OPA/Gatekeeper enforcement, Falco runtime
detection, Trivy vulnerability scanning before admission.

**T3 Developer Autonomy.** A developer clones this repo, fills in a config file, and
has a production-grade platform in under 30 minutes — with no cloud account required
for local development. kind-based local cluster, Backstage service catalog, browser-based
IDE (code-server), complete GitOps workflow via GitLab + ArgoCD.

**T4 Observability.** Every signal from every component is captured, correlated, and
queryable — metrics, logs, traces, security events — with no data leaving the cluster.
Prometheus, Loki, Tempo, Thanos for long-term retention, Falco events in Grafana.

**T5 Resilience.** The platform survives node failures, upgrades, and deliberate chaos
without data loss or unplanned downtime. PodDisruptionBudgets, podAntiAffinity, daily
backups with tested restore, zero-downtime rolling updates, Chaos Mesh scenarios.

---

## Constitutional Gates

Machine-checkable invariants that protect core values. If a gate fails, the ceremony
loop stops until it's fixed. Gates are defined in `prd/constitution.json` and evaluated
by orient.py at the start of every cycle. The constitution-review ceremony evaluates
whether each gate still serves the project.

Current gates:
- **G1** — Ceremony scripts compile without errors (T3: delivery machine health)
- **G2** — Living state docs exist and are current (T3: orientation without archaeology)
- **G6** — Zero external registry references in chart templates (T1: sovereignty)
- **G7** — Contract validator test suite passes (T1: sovereignty enforcement)

---

## Team Norms

**Stop the line.** When any gate fails, all new work stops. Fix the specific failure,
show the passing output, then continue. No deferrals, no "known issues."

**Proof of work.** Every completed story must: push to remote, create a PR, wait for
CI to pass, squash merge to main. Show actual command output — don't assert results.

**Never self-certify.** If you didn't run the command and see the output, you can't
mark it verified. "It should work" is not proof.

**Test contract first.** Before writing code, write the exact commands you'll run and
what output proves the story done. Run them after implementation. Show the output.

**Blocker protocol.** When you can't complete a story due to a missing prerequisite
(credentials, running cluster, external service), implement what you can, add a `blocker`
field to the story, set `passes: false`, and push what you have.

**Story lifecycle:**
```
passes: false, reviewed: false  -> needs implementation
passes: true,  reviewed: false  -> implemented, awaiting review ceremony
passes: true,  reviewed: true   -> accepted (done)
```

Mark `passes: true` when done. Never mark `reviewed: true` — that's the review ceremony's job.

---

## Architecture Decisions

- **ArgoCD App-of-Apps** — everything after bootstrap is an ArgoCD Application
- **Domain is a variable** — `{{ .Values.global.domain }}` everywhere, never hardcoded
- **Autarky** — after bootstrap, the cluster never pulls from external registries
- **HA mandatory** — 3+ nodes (odd), replicaCount >= 2, PDB, podAntiAffinity on every chart
- **Distroless mandatory** — all images use distroless bases, exceptions require VENDORS.yaml deprecation entry
- **License policy** — Apache 2.0/MIT/BSD approved, BSL blocked (OpenBao not Vault), AGPL needs review
- **Zero-downtime rollout** — staging first, smoke test, promote, auto-rollback on failure
- **Crossplane** for infrastructure compositions (namespaces, RBAC, cloud resources)
- **kind-first testing** — static analysis always, kind integration when possible, cloud never in CI

See subdirectory CLAUDE.md files for implementation details:
- `platform/charts/CLAUDE.md` — Helm chart standards, HA gates, values conventions
- `cluster/CLAUDE.md` — Bootstrap requirements, provider scripts
- `platform/vendor/CLAUDE.md` — Vendor recipes, distroless, license details

---

## Quality Gates

Run before marking any story `passes: true`:

```bash
# Helm charts
helm lint platform/charts/<name>/
helm template platform/charts/<name>/ | grep PodDisruptionBudget
helm template platform/charts/<name>/ | grep podAntiAffinity
bash scripts/ha-gate.sh --chart <name>   # scoped: exits 0/1 based on this chart only

# Scripts
shellcheck -S error <script>

# Autarky
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "FAIL" || echo "PASS"

# Contract
python3 contract/validate.py contract/v1/tests/valid.yaml
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml  # must fail
```

---

## Governance

Before adding any new dependency, read `docs/governance/license-policy.md` and
`docs/governance/sovereignty.md`. Before cluster-level architectural decisions,
read `docs/governance/cluster-contract.md`. Before anything outside the platform's
mission, read `docs/governance/scope.md`.

---

## Live State

Read `docs/state/agent.md` before implementing anything — it's the live briefing,
rewritten each sprint by the sync ceremony. Current patterns, current gotchas,
current platform state.

Read `docs/state/architecture.md` for architecture decisions currently in force.

Read subdirectory CLAUDE.md files when working in those directories.

---

## Sprint Mechanics

```
prd/manifest.json           <- source of truth: active sprint, increments
prd/increment-N-<name>.json <- sprint file: stories for this increment
prd/backlog.json            <- all future stories
prd/constitution.json       <- themes + constitutional gates
```

The ceremony system (`scripts/ralph/ceremonies.py`) runs the full delivery cycle:
orient -> constitution-review -> epic-breakdown -> backlog-groom -> plan -> preflight ->
smart -> execute -> smoke -> proof -> review -> retro -> sync -> advance.
