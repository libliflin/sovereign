# Alignment Summary

For the user — plain-English summary of the decisions made during init.

---

## Who This Serves

| Stakeholder | One line |
|---|---|
| **Alex** (Self-Hosting Developer) | The developer who wants to escape SaaS lock-in and run their own stack. Cares about the 30-minute promise. Arrives via README. |
| **Morgan** (Production Operator) | The person responsible for a live deployment. Gets paged at 3am. Needs observability and honest rollouts. |
| **Jordan** (Platform Contributor) | The developer adding a new chart or fixing a ceremony script. Cares about the rules being clear and locally verifiable. |
| **Sam** (Security Evaluator) | The person auditing Sovereign for a regulated environment. Needs every zero-trust and autarky claim to be machine-verifiable. |
| **Casey** (Contract Consumer) | The team building automation on top of Sovereign's cluster-contract schema. Needs the validator to be stable, versioned, and to produce actionable errors. |

---

## Emotional Signal Per Stakeholder

| Stakeholder | Signal |
|---|---|
| Alex | **Excitement** — "I want to tell someone this exists." |
| Morgan | **Trust and transparency** — "I know what it did and why." |
| Jordan | **Clarity and confidence** — "The rules are stated, I know what passing looks like." |
| Sam | **Paranoia satisfied** — "I verified it myself. I don't have to take it on faith." |
| Casey | **Confidence and predictability** — "The contract is a stable API I can depend on." |

---

## Key Tensions

| Tension | The conflict | Resolution signal |
|---|---|---|
| Sovereignty vs. Accessibility | Autarky strictness is right for T1 but creates friction for Alex before they've seen anything work. | If Sam or regulated-env users are in the room → sovereignty wins. If Alex's kind quick start stalls → accessibility matters now. |
| HA Requirements vs. Contributor Speed | PDB/anti-affinity/replicaCount are non-negotiable for Morgan, but add overhead for Jordan. | If CI gate failures are catching real violations → HA holds. If CI has false positives or local/CI gap → contributor friction needs attention. |
| Observability Depth vs. Operator Simplicity | Deep observability serves Morgan's 3am. But setup complexity competes with Morgan's time. | If Morgan can't diagnose a failure → depth matters. If Morgan can't reach observability tools at all → simplicity wins first. |

---

## What Could Be Wrong

### Missing stakeholders

- **Downstream team** — a team that has integrated Sovereign's API contract into their own CI, distinct from Casey's single-consumer framing. If Sovereign becomes a platform-of-platforms for multiple internal teams, this stakeholder emerges. Currently Casey covers this.
- **Security researcher / penetration tester** — someone trying to break Sovereign's zero-trust posture, not just evaluate it. Sam is modeled as evaluative. An adversarial role might find gaps Sam's journey misses. Not modeled here.

### Unverified assumptions

- **Default branch protection:** Could not verify whether the `main` branch has GitHub branch protection rules enabled (required PR reviews, status checks required before merge). This is important for autonomous operation — without branch protection, a compromised PR could merge without CI passing. **Recommend verifying in GitHub repository Settings → Branches.** Flag in goal.md was intentionally omitted (it's a current-state fact, not a journey pattern), but the risk is real.
- **Repository visibility:** The repo appears to be public (github.com/libliflin/sovereign). This is consistent with the project's sovereignty mission (open source). CI workflows use `pull_request` (not `pull_request_target`) triggers — this is the safer choice. No `issue_comment` triggers found. Prompt injection risk is low but non-zero for public PRs.
- **Forgejo workflows:** The snapshot.sh checks for `.forgejo/workflows/*.yml` in addition to `.github/workflows/*.yml`. If Sovereign is dogfooding its own Forgejo as the primary CI (self-hosted), the GitHub Actions workflows may be secondary. The champion should check the snapshot for active CI provider and whether both are being maintained.
- **The vendor recipe system's completeness:** VENDORS.yaml was referenced in CI but not fully inspected. If entries are missing or licenses are wrong, the vendor-audit CI job will catch it — but only if the job runs (it's path-filtered to `platform/vendor/**` changes). Sam's journey would surface this.
- **Istio mTLS STRICT enforcement:** The architecture states STRICT mTLS everywhere. The `platform/charts/istio/` chart was not deeply inspected. It's possible the default values configure PERMISSIVE mode for easier adoption, with STRICT requiring manual configuration. This would be a gap between the zero-trust claim and the default deployment.

### Structural note

The champion is modeled as reading from `skills/journeys.md` each cycle. These journeys describe steps to walk, not a fixed state of the project. Current-state observations ("CI is currently passing") deliberately live in the snapshot, not in goal.md or journeys.md — they'd be stale by cycle 2.

Brand is currently absent (`brand.md` deleted). The champion's goal.md instructs falling back to stakeholder emotional signal when brand.md is in emergent mode. No action required until brand.md is written.
