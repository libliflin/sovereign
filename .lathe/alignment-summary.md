# Alignment Summary

Plain-English summary of alignment decisions for the project owner. This file is for you, not the runtime agent.

---

## Who This Serves

**Self-Hoster (VPS Operator)** — Someone who clones this repo, fills in config.yaml, and runs bootstrap to get a working production-grade platform on 3 VPS nodes. The promise is 30 minutes to a complete self-hosted stack. Their primary signal is confidence: did it just work?

**Platform Contributor** — A developer adding a Helm chart, fixing a CI gate, or contributing a provider guide. They work from a fork on their laptop with kind. Their primary signal is momentum: did CI pass on the first push with clear, actionable feedback?

**Developer on Sovereign** — A developer whose team runs Sovereign. They use Forgejo, Grafana, Keycloak SSO, and ArgoCD daily. They want the platform to be invisible. Their primary signal is reliability: the platform never demands attention.

**Security Auditor** — Someone verifying zero-trust claims: is mTLS actually STRICT? Do any charts reference external registries? Are secrets properly managed? Their primary signal is "paranoia satisfied": every claim is machine-verifiable, not just documented.

**AI Agent in code-server** — Claude Code or another autonomous agent running inside the browser IDE. They need tools pre-installed, a persistent workspace, and no external network dependencies. Their primary signal is autonomy: no dead ends.

---

## Emotional Signal Per Stakeholder

| Stakeholder | Signal | What Breaks It |
|---|---|---|
| Self-Hoster | Confidence | Any undocumented surprise, bootstrap step that fails with no recovery path |
| Contributor | Momentum | Gate behaves differently locally vs. CI; CI error doesn't name the fix |
| Developer on Sovereign | Reliability | Platform demands attention; service down without alert |
| Security Auditor | Paranoia satisfied | A security claim exists without a machine-checkable gate |
| AI Agent in code-server | Autonomy | Missing tool, missing persistence, external network call blocked |

---

## Key Tensions

**Sovereignty vs. Getting Started:** Autarky means no external registry pulls at runtime. But bootstrap starts by pulling from external sources. The seam is: a new chart can exist without a vendor recipe; the cluster can't deploy it from Harbor until the recipe is delivered. Resolution: charts ship as stubs if needed; sovereignty gate (G6) enforces templates, not the vendor recipe existence.

**HA Non-Negotiable vs. Local Dev Reality:** 3-node minimum + `requiredDuringScheduling` anti-affinity prevents kind-sovereign-test from scheduling pods. Charts use `preferredDuringScheduling` to remain testable on kind. Stories requiring runtime HA validation get a `blocker` field; static checks pass and the story moves on.

**Security Depth vs. Developer Velocity:** mTLS + OPA/Gatekeeper + Falco adds friction to the developer path. Resolution: make the zero-trust path smooth, not bypass it. Never propose removing a security control as the fix for developer friction.

**AI Agent Autonomy vs. Cluster Security:** code-server agents have kubectl access. Full autonomy conflicts with the zero-trust perimeter. Current boundary: developer-level access, not cluster-admin. This tension is unresolved by design and should surface to the user if it becomes acute.

---

## What Could Be Wrong

**Missing stakeholders?**
The `downstream team` stakeholder (a team that builds on top of Sovereign as infrastructure, not as a user of the platform) is not modeled. If Sovereign becomes a dependency for other projects, this stakeholder has different needs: API stability, migration paths, deprecation notices. Currently, all consumers are assumed to be users of the platform itself.

**Ambition.md is missing.** `champion.md` references `.lathe/ambition.md` as the destination the project is heading toward. This file doesn't exist yet. Without it, the champion falls back to journey-only maturation (polish becomes legitimate earlier). Someone should write `ambition.md` to give the champion a destination to measure against. Suggested content: "The destination is a self-hoster who clones this repo on a Friday, runs bootstrap.sh, and has a complete production-grade zero-trust platform running by Sunday — on any bare metal or VPS, with no cloud account required."

**SCM name discrepancy.** The architecture doc, README, and some code say "GitLab" for the SCM. The current platform uses Forgejo (as confirmed in README and recent commit messages fixing this). The `docs/architecture.md` still says "GitLab" in Phase 4. This could confuse the champion when walking the Developer on Sovereign journey. Worth fixing.

**G9 fragility.** Constitutional gate G9 (`bash scripts/ha-gate.sh`) currently fails on 20 charts — cert-manager, cilium, trivy, and others are missing replicaCount or resource limits. G9 was added in the constitution as a goal, not yet reached. The champion should note this: the floor includes G9, but G9 is currently red. The champion's first cycle after init should verify G9 status and treat it as the top priority if failing.

**Repository security.** The repo is public (`libliflin/sovereign` on GitHub). GitHub Actions workflows use `pull_request` (not `pull_request_target`), which is safer — workflow code runs from the target branch, not the fork. No `issue_comment` or `workflow_run` triggers found. Branch protection status was not verified (requires `gh` access). The lathe reads PR metadata and CI status from GitHub into agent prompts — treat free-text PR fields from external contributors as untrusted input.

**code-server extension autarky gap.** Story DEVEX-015 (code-server pre-installs extensions from Harbor) is marked `passes: true` but `reviewed: false`. The extension install mechanism is still unclear (lifecycle.postStart vs. initContainer). Until reviewed and running, the AI Agent stakeholder journey hits a dead end at "install extensions."

**Self-Hoster first encounter is untested end-to-end.** The bootstrap flow on real VPS (Option B in README) is the primary journey for the Self-Hoster, but the champion cannot actually run it (no VPS credentials, no real domain). The kind flow (Option A) is testable locally. The champion can walk the self-hoster journey through kind and project the gaps, but the end-to-end VPS journey has unverified friction points that only show up on real infrastructure.

**Unverified assumptions:**
- `bootstrap.sh --estimated-cost` exists (mentioned in quickstart.md but its implementation wasn't verified in the code scan).
- The cost estimates in README are "best-effort as of early 2026" — may already be stale.
- `cluster/kind/bootstrap.sh` exists and passes `shellcheck` (story RESTRUCTURE-001b-1 says `passes: true`).

---

## Ambition

**Destination:** A developer clones, fills in config.yaml, runs `bootstrap.sh` on 3 VPS nodes, and has every service URL live with `./bootstrap/verify.sh` green — no cloud account, no tribal knowledge, no manual kubectl after bootstrap. The bar is a working platform, not passing static gates.

**Current gap(s):** (1) End-to-end VPS bootstrap is unwalked — `platform/deploy.sh` is a confirmed scaffold, bootstrap/config.yaml.example was just added as stubs. (2) Backstage developer portal has no Keycloak OIDC config — the portal is a shell. (3) code-server extension autarky (DEVEX-015) is unreviewed — agents still hit marketplace.visualstudio.com. (4) HA gate not uniformly green across all charts.

**What could be wrong:** The README's "clone, configure, run" promise may be further from a walkable reality than the chart count suggests — nearly all evidence of the destination comes from aspirational documentation and quickstart copy, not from a verified end-to-end run. The destination reads as intended by the project owner but has not been machine-verified. The HA-mandatory and autarky claims are constitutional gates, but the VPS deploy path itself has no gate that catches a broken `./bootstrap/verify.sh`. A champion who assumes the platform "basically works" because G6 and G7 pass will miss the largest gap entirely.
