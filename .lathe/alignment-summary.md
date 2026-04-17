# Alignment Summary

Plain-English summary for the human reviewing this init. This file is not read by the runtime agent.

---

## Who this serves

- **S1 — The Self-Hoster:** A technical person trying to own their infrastructure on Hetzner/VPS. First encounter is `clone → configure → bootstrap`. Success = cluster up, nothing phoning home.
- **S2 — The Platform Developer:** A developer on a team whose infrastructure runs on Sovereign. Uses Forgejo, ArgoCD, Grafana daily. Success = push code, watch it deploy, see what happened.
- **S3 — The Chart Author / Contributor:** A developer adding a new service chart or fixing an existing one. Success = PR passes CI on the first try; rules are discoverable.
- **S4 — The Security Auditor:** A security engineer certifying the platform satisfies zero trust, autarky, and licensing requirements. Success = every claim is machine-verifiable with a command.
- **S5 — The Delivery Machine (Ralph):** The autonomous ceremony loop. Reads `agent.md` and sprint files to implement stories. Success = stories pass first review; G1 stays green; no archaeology required.

---

## Emotional signal per stakeholder

- **S1:** Confidence. *This will work when I need it.* Track unease at each bootstrap step.
- **S2:** Momentum. *I can see it moving.* Track stalls, especially silent ones.
- **S3:** Respect. *The rules make sense and I can find them.* Track hazing — rules that only exist as tribal knowledge.
- **S4:** Certainty. *I can prove this is compliant.* Track unverifiable claims.
- **S5:** Orientation. *I know where I am and what to do next.* Track archaeology.

---

## Key tensions

**Autarky vs. Bootstrap simplicity.** The vendor system (fetch, patch, build from source into distroless) is the sovereign ideal. The bootstrap experience needs to work in under 30 minutes. Signal for tie-breaking: if the kind path hits a wall before any service is running, simplify bootstrap; if kind works cleanly, advance autarky.

**Gate strictness vs. Discoverability for contributors.** The HA gate, autarky gate, check-limits.py, and shellcheck together create a high bar. Each is protecting a real value. Each failure message that doesn't explain the fix is hazing S3. Signal: does ha-gate.sh output tell you the exact chart and exact rule that failed?

**Sovereignty vs. Upstream convenience.** The `ha_exception` and upstream wrapper chart patterns represent pragmatic compromises. Signal: if constitutional gates are green and the platform works for S1/S2, tighten toward full autarky; if gates are failing or bootstrap is broken, pragmatic wrappers are the right call.

---

## Repository security assessment (for autonomous operation)

The `.github/workflows/` directory contains three workflows:

- `validate.yml` — triggers on `pull_request` (branches: main) and `push` (branches: main). Uses `pull_request` (not `pull_request_target`). **Safe.** PRs from forks run in a restricted context without access to secrets.
- `ha-gate.yml` — triggers on `pull_request` with path filter on `platform/charts/**`. Uses `pull_request`. **Safe.**
- `release.yml` — not fully read; check for `pull_request_target` or `issue_comment` triggers if adding automation.

The repo is public (visible at `https://github.com/libliflin/sovereign`). The lathe reads CI status and PR metadata from GitHub into the agent prompt — this is a prompt injection surface. The current workflow design mitigates this by using `pull_request` (not `pull_request_target`), but PR titles and descriptions from external contributors could still contain adversarial text. The agent should treat snapshot data from CI as potentially untrusted.

**Default branch protection:** Unknown from code inspection alone. Check GitHub → Settings → Branches → Protection rules. Given the ceremony loop's "proof of work" norm (push branch, open PR, wait for CI, merge), branch protection should require at least: PR required, CI must pass.

---

## What could be wrong

**Missing stakeholders?** The S2 journey (Platform Developer) assumes a running cluster, which the champion can't walk locally for most steps. The champion will need to either work with a running kind cluster or treat "can I walk this journey?" as the gate — a broken kind path means S2's experience is completely opaque. This is a genuine constraint, not a design error, but it means S2 may be under-served relative to S1 and S3.

**S5 as a stakeholder?** Calling the delivery machine a "stakeholder" is a deliberate choice — the agent loop has real needs (accurate state, self-explanatory ACs, working gates) and degrades visibly when those needs aren't met. But the champion can't *inhabit* S5 the way it can inhabit S1; it can only read the `agent.md` and try to implement a story from it. This is a structural limit.

**Governance docs not read:** `docs/governance/license-policy.md`, `docs/governance/sovereignty.md`, `docs/governance/cluster-contract.md`, `docs/governance/scope.md` were not read during this init. The architecture skill captures what's visible in the code; the governance docs may contain additional constraints or nuance.

**Bootstrap scripts not found:** The README references `bootstrap/bootstrap.sh`, `bootstrap/config.yaml.example`, and `bootstrap/verify.sh`. These were not found in the directory listing (only `cluster/kind/bootstrap.sh` was confirmed present). The VPS path in the S1 journey may reference files that don't exist yet. The champion should verify before walking that journey.

**G9 status:** constitution.json shows G9 was added with a note that it "currently fails 20 charts." The snapshot will show G9's current state each cycle. If G9 is failing, the champion should treat it as floor-level work.

**Brand.md absent:** `.lathe/brand.md` doesn't exist. goal.md instructs the champion to fall back to stakeholder emotional signal when brand.md is absent or emergent. This is correct behavior for a project at this stage.
