# Alignment Summary

For the human reviewing lathe initialization. Plain English. This is not an agent-facing file.

---

## Who This Serves

- **Sovereignty Seeker** — self-hosted operators deploying to VPS who need the bootstrap to actually work and the "autarky" claim to be real at runtime
- **Kind Kicker** — developers evaluating the platform locally, following Option A in the README, who need momentum and copy-pasteable commands that actually work
- **Platform Contributor** — open source participants adding charts or provider docs, who need CI to catch what they missed and give clear, scoped feedback
- **Security Auditor** — zero-trust verifiers checking whether the platform's claims (autarky.externalEgressBlocked, mTLS STRICT, distroless everywhere) are backed by actual enforcement, not just assertion
- **Ceremony Observer** — the person (or agent) monitoring whether the autonomous delivery loop is making real progress or spinning on low-value work

---

## Emotional Signal Per Stakeholder

| Stakeholder | Signal |
|---|---|
| Sovereignty Seeker | "This is actually mine" — completeness, no hidden runtime dependencies |
| Kind Kicker | Momentum — forward progress at each step, commands that work verbatim |
| Platform Contributor | Confidence + collaboration — CI as a helpful reviewer, not a black box |
| Security Auditor | Paranoia satisfied — every zero-trust claim falsifiable by a specific command |
| Ceremony Observer | Confidence in the machine — the loop advances real things |

---

## Key Tensions

**Sovereignty vs. Usability (Seeker vs. Kicker)**
The kind evaluation path may pull in external images during eval — fine for evaluation, confusing if autarky error messages assume a live Harbor registry. Signal: if kind failures reference Harbor before Harbor exists, the messaging is wrong.

**HA Enforcement vs. Contributor Friction (Contributor)**
The HA gate is non-negotiable, but a contributor's PR shouldn't fail on a pre-existing chart they didn't touch. The `--chart` flag on ha-gate.sh exists for exactly this reason. Signal: if CI blocks a contributor on an unrelated chart failure, the scoped gate isn't being used correctly.

**Claim vs. Implementation (Auditor)**
`autarky.externalEgressBlocked: true` is a contract invariant (declared) not an enforced constraint (NetworkPolicy). The enforcement layer requires per-namespace NetworkPolicy + Istio AuthorizationPolicy. The gap between the claim and enforcement is real and not fully closed. Signal: the auditor should be able to grep for NetworkPolicy manifests in chart templates and find coverage for every service.

**Maturation vs. New Features (all)**
Adding new charts while the kind evaluation journey is still rough means the Kind Kicker can't get through the door while the Sovereignty Seeker gets new capabilities. Signal: when the same first-encounter friction persists across multiple goal cycles, stop adding features and fix the wall.

---

## Repository Security for Autonomous Operation

Checked during init (approximate — gh API not available in this session):

- **Workflow triggers:** No `pull_request_target` or `issue_comment` triggers found in `.github/workflows/`. The three workflows (`ha-gate.yml`, `validate.yml`, `release.yml`) use `pull_request`, `push`, and tag triggers only. Prompt injection via PR metadata is not a vector with these triggers.
- **External registry in CI:** CI uses `actions/checkout@v4`, `azure/setup-helm@v4`, `azure/setup-kubectl@v4`, `actions/cache@v4` — these are GitHub-hosted actions, not operator-controlled. This is standard for public repos but worth noting: the CI trusts GitHub's action marketplace for these specific pinned versions.
- **Repo visibility:** Marked as public in CLAUDE.md (dogfood domain publicly referenced). This means any PR from a fork can trigger CI — standard for open source, but lathe should not commit any secrets or credentials in goal files.
- **Branch protection:** Could not verify via API in this session. Recommend checking that the `main` branch requires PR reviews and CI passing before merge.

---

## What Could Be Wrong

1. **Missing stakeholder: downstream team / API client.** The contract system (`contract/validate.py`, `sovereign.dev/cluster/v1` schema) implies there could be teams who consume this as a platform contract — writing their own cluster-values.yaml and relying on the invariants. This stakeholder wasn't fully fleshed out because the evidence in the code is thin (only two test fixtures). If the contract system grows, this stakeholder should be added.

2. **Ceremony Observer is an unusual stakeholder.** Most platforms don't have "the person monitoring the autonomous loop" as a real user. This is correct for Sovereign given its operating-room / lathe architecture, but future goal.md maintainers should verify this stakeholder remains real as the system evolves.

3. **The "autarky at runtime" claim has a known gap.** The autarky gate (G6) checks chart templates for external registry refs. It does not verify that Harbor is populated. A champion walking the Sovereignty Seeker journey on a fresh cluster will find images missing until the vendor build pipeline runs — this is a real and known friction point.

4. **Kind first-encounter journey is the most testable.** The Sovereignty Seeker journey requires real VPS and credentials. The champion can only walk it partially (dry-run, README reading, config inspection) without live infrastructure. The Kind Kicker journey is fully walkable on any laptop. The champion should weight kind-walkable evidence more heavily than VPS-inferred evidence.

5. **Brand.md is not yet present.** Without a brand.md, the champion should skip the brand-tint step described in goal.md and fall back to stakeholder emotional signals alone. Once enough cycles have run to establish the project's character from evidence, brand.md should be written.
