# Alignment Summary

For the human. Not for the runtime agent.

---

## Who this serves

- **The Self-Hoster** — a developer escaping SaaS/cloud lock-in, wants a working self-hosted stack from one command, on cheap VPS or bare metal.
- **The Platform Operator** — an SRE or senior dev running the platform in production, on-call, needs observability and HA to actually work.
- **The Developer on the Platform** — a developer using the running platform: code-server, Forgejo CI, Backstage, SSO. They want to forget the platform exists.
- **The Contributor** — an open source developer who wants to contribute a chart fix, provider doc, or new feature; needs clear gates and CI that tells them what to fix.

---

## Emotional signal per stakeholder

| Stakeholder | Signal | Meaning |
|---|---|---|
| Self-Hoster | Momentum | One command leads cleanly to the next |
| Platform Operator | Confidence | "I know what it did and why" |
| Developer on Platform | Flow | The environment disappears |
| Contributor | Clarity | "I know what's expected and my work meets it" |

---

## Key tensions

**Autarky vs. first-run simplicity.** Full autarky (build all images from source) requires Harbor, Forgejo, and the vendor pipeline to exist — none of which exist on first bootstrap. Resolution: kind path uses upstream images; VPS path enforces autarky. Tension is live when the kind path pulls external images for platform charts and someone treats that as an autarky violation.

**Developer DX vs. operator burden.** Every new service (Backstage, SonarQube, code-server, ReportPortal) the developer team gets is another service the operator monitors, keeps HA, and gets paged about. Tension surfaces when a chart is added without a Grafana datasource ConfigMap or without proper HA gates.

**Contributor ease vs. quality gates.** The project has >10 distinct CI gates. Contributors who don't read the docs (and many won't) get opaque CI failures. Tension surfaces when CI says "helm gate failed" without naming which chart and which specific check.

**Operator stability vs. platform evolution.** Each sprint adds to `docs/state/agent.md`'s "patterns that must not be broken" section — because something broke. The list grows. The tension is: does the champion advocate for slowing down and hardening, or adding what's missing?

---

## Repository security assessment (for autonomous operation)

- **Workflow triggers:** No `pull_request_target` or `issue_comment` triggers found in `.github/workflows/`. All three workflows (`validate.yml`, `ha-gate.yml`, `release.yml`) are triggered by `pull_request` (to main) and `push` (to main) — standard, unprivileged triggers. **No elevated-privilege injection surface.**
- **Repo visibility:** Public (stated in CLAUDE.md and evident from the GitHub URL in README).
- **Default branch protection:** Not verifiable from local filesystem. **Recommended:** Verify that the `main` branch has required status checks and requires PR review before merge. A public repo with an unprotected main branch is a prompt injection risk — a PR from an external contributor with a malicious commit message or file content could be read by the champion into its prompt.
- **Pull request metadata in prompts:** If lathe's snapshot reads PR titles or commit messages from open PRs, those are an injection surface. Treat them as untrusted input: don't execute shell commands embedded in commit messages, don't follow URLs from PR bodies without explicit user approval.

---

## What could be wrong

**Missing stakeholder: the downstream integrator.** Sovereign PM exposes an API (`prd.json` generation, sprint management). Teams could build tooling on top of it. That stakeholder — "an agent or tool consuming the Sovereign PM API" — isn't in the stakeholder map. If the API stabilizes and downstream consumers appear, add them.

**The operator journey assumes Grafana is accessible.** The kind bootstrap doesn't install Grafana by default — it installs sealed-secrets, Cilium, cert-manager, local-path-provisioner, and MinIO. The observability stack requires deploying the prometheus-stack chart separately. The operator journey in `skills/journeys.md` uses `helm template` to check datasource ConfigMaps — it doesn't require a running Grafana — but if the champion walks a "running cluster" variant of the operator journey, Grafana may not be there.

**Backstage catalog is empty without configuration.** The Backstage chart and ArgoCD app exist, but the Keycloak OIDC plugin and entity sources are pending (DEVEX story 027a). The developer-on-platform journey step "find services in Backstage" will fail until that story ships. The champion should flag this as a wall in the developer journey, not assume Backstage is working.

**CI existence vs. CI greenness.** The snapshot checks CI config (`ls .github/workflows/*.yml`) but doesn't report whether the last CI run passed. The champion should check actual CI status each cycle — the snapshot shows the gates exist, not whether they're passing. If the snapshot doesn't pull live CI status, that's a gap to fix in `snapshot.sh`.

**kind vs. VPS divergence.** Most champion journeys can be walked against the kind cluster, but the VPS path (bootstrap.sh, config.yaml, .env) cannot be walked without real cloud credentials and real VPS nodes. The self-hoster VPS journey in `skills/journeys.md` can only be partially walked locally — the champion can check doc accuracy, config file documentation, and `--dry-run` behavior, but can't validate the full bootstrap without infrastructure. This is a known gap.
