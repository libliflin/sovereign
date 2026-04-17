# Alignment Summary

For the human. This is not read by the runtime agents.

---

## Who This Serves

**The Self-Hoster** — Someone paying $200+/mo for cloud-managed services (GitLab, Vault, a container registry) who wants to own their stack. Technical, not necessarily a K8s expert. First encounter is the kind quickstart. Success is ArgoCD, GitLab, Grafana running at their domain on hardware they control.

**The Platform Developer** — A developer whose organization runs Sovereign as internal platform. They use GitLab, Backstage, code-server, ArgoCD. They don't operate Kubernetes. Success is "I pushed code and it deployed" without filing a ticket.

**The Contributor** — Someone submitting a Helm chart fix, a new service chart, or a ceremony script improvement. Success is a PR that passes CI on first try and gets actionable review feedback.

**The Security Operator** — Someone in a production environment who needs to prove zero-trust compliance, audit CVEs, and verify autarky. Success is machine-checkable proof for every security claim.

**The Delivery Machine Maintainer** — The repo author (or autonomous agent) operating the ralph ceremony system. Success is "the delivery machine runs itself, I steer." Red flag: more than 2 remediation sprints in the last 10 increments.

---

## Emotional Signal Per Stakeholder

| Stakeholder | Signal | One-line check |
|---|---|---|
| Self-Hoster | Confidence and momentum | Each step tells me it succeeded before I take the next |
| Platform Developer | Transparent ease | Does any of this feel like Kubernetes? (bad if yes) |
| Contributor | Certainty | Do I know CI will pass before I push? |
| Security Operator | Verifiable trust | For every security claim, is there a machine check that falsifies it? |
| Delivery Machine Maintainer | Low-friction continuity | Is the machine running, or am I debugging it? |

---

## Key Tensions

**First-encounter simplicity vs. autarky depth.** The kind quickstart must not require understanding Harbor or the vendor build system. Full autarky is for production. Signal: if kind quickstart requires vendor setup, autarky is blocking evaluation — fix the quickstart first.

**HA rigor vs. contributor friction.** The HA gate is non-negotiable. What's negotiable is whether contributors can discover it before CI fails them. Signal: walk the contributor's journey to PR open; if the first CI failure is something not in CONTRIBUTING.md, that's the gap to fix.

**Delivery machine investment vs. platform feature work.** Count remediation sprints in `prd/manifest.json`. > 2 in the last 10 increments = delivery machine needs attention. ≤ 2 = platform feature work takes precedence.

**Security claims vs. verifiability.** Every security claim should have a machine-checkable gate. Documentation without a gate is no trust at all. Signal: README claim → find the CI step that falsifies it. When one doesn't exist, that's the goal.

---

## Repository Security Assessment

- **Default branch protection**: Unknown — verify in GitHub repo settings. Should have: require PR review before merging, require status checks (validate.yml, ha-gate.yml).
- **Workflow trigger audit**: `validate.yml` uses `pull_request` and `push`. `ha-gate.yml` uses `pull_request`. Neither uses `pull_request_target` or `issue_comment`. **No prompt injection surface from PR metadata or comments in CI.** Low risk.
- **Repo visibility**: Public (`github.com/libliflin/sovereign`). Goal files committed to the repo are publicly readable. The customer champion's goal.md, skills files, and alignment summary will be publicly visible. No credentials or private operational details should go in `.lathe/`.

---

## What Could Be Wrong

1. **Missing stakeholder: downstream API consumers.** The `contract/v1/` layer suggests there might be tooling or teams that consume `cluster-values.yaml` files and validate them against the contract. If such consumers exist (e.g., an org deploying Sovereign across multiple clusters), they're a stakeholder this init didn't identify because there's no evidence of them in the current codebase. If they exist, add them to `goal.md`.

2. **The delivery machine maintainer may be the same person as the self-hoster.** For a solo maintainer, these aren't separate people — they're the same person wearing different hats on different days. The champion should still rotate between these identities, because the needs are genuinely different.

3. **kind path ≠ production path.** The kind cluster is explicitly not HA (single-node). Several HA-gate checks are enforced in CI but can't be fully validated on kind without the 3-node setup. The self-hoster's first experience is necessarily incomplete — they can't validate production HA behavior on kind. This is a known and accepted gap, but it means the self-hoster's trust at the end of the kind journey is partial trust.

4. **G2 staleness check doesn't verify accuracy.** `docs/state/agent.md` can be touched without updating its content to pass G2. If several sprints pass without a genuine sync ceremony updating this file, the "live briefing" may be misleading. The champion should check whether `docs/state/agent.md` accurately reflects current state, not just whether it was recently modified.

5. **Remediation sprint pattern.** ~10% of increments have been remediation sprints (4 out of 41 at init time). This is within tolerance but bears watching. If the next 5 increments include 2+ remediation sprints, the delivery machine needs a cycle dedicated to improving ceremony reliability and gate signal quality.

6. **Autarky gap in values.yaml.** The G6 gate checks `platform/charts/*/templates/` for external registry refs, but not `values.yaml`. A chart with `image.repository: docker.io/myimage` in values.yaml bypasses G6. The CI `helm-validate` job has a separate check for this, but it's heuristic (looks for obvious external registry prefixes). A carefully crafted values.yaml might slip through. This is a known gap — if the security operator journey surfaces it, the goal should be closing it structurally.
