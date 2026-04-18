# Stakeholder Journeys

Concrete step-by-step journeys the champion walks each cycle. One per stakeholder.
Walk these paths. Run the commands. Notice where momentum lives and where it dies.

---

## 1. Sovereignty Seeker — VPS Bootstrap Journey

**Emotional signal:** "This is actually mine" — completeness, no hidden dependencies.

**Prerequisites they have:** 3 Hetzner CX32 nodes running Ubuntu 22.04+, a domain on Cloudflare, `bash`, `kubectl`, `helm` v3+.

**Steps to walk:**

1. `git clone https://github.com/libliflin/sovereign && cd sovereign`
2. `cat README.md` — does the intro immediately communicate what this is and who it's for?
3. `ls bootstrap/` — does the layout match what the README says?
4. `cp bootstrap/config.yaml.example bootstrap/config.yaml` — are the fields self-explanatory? What's ambiguous?
5. `cp .env.example .env` — count how many tokens you need to find. Is each one's source documented?
6. `./bootstrap/bootstrap.sh --estimated-cost` — does it give real numbers? Does it name the cloud resources it will create?
7. `./bootstrap/bootstrap.sh --dry-run` — does the preview match the README's description?
8. Read `docs/quickstart.md` — does it fill in the gaps the README left?

**Watch for:**
- Steps where you need to open a browser tab to find information the README should have given you
- Error messages that say what failed but not how to fix it
- The moment you realize you're still depending on something you don't control (Cloudflare during bootstrap, external images during deploy)
- Whether `--dry-run` output matches the actual bootstrap behavior

---

## 2. Kind Kicker — Local Evaluation Journey

**Emotional signal:** Momentum — each step feels like forward progress, not debugging.

**Prerequisites they have:** Docker Desktop running, `kind`, `kubectl`, `helm`, `gh` installed via brew.

**Steps to walk:**

1. Read "Option A — Local testing with kind" in the README
2. `./cluster/kind/bootstrap.sh --dry-run` — does it print a useful preview?
3. `./cluster/kind/bootstrap.sh` — watch the output. Is progress legible? Does the ~4 minute wait have output?
4. Run the exact `helm install test-release` command from the README (copy-paste verbatim)
5. `kubectl --context kind-sovereign-test get pods -n sealed-secrets` — do the pods start? How long?
6. `kind delete cluster --name sovereign-test` — does teardown work cleanly?

**Watch for:**
- Any command in the README that fails because a path doesn't exist (README chart path validation is a CI check — but feel it yourself)
- Whether the output during bootstrap is informative or a wall of text
- The moment a pod fails to start and you have to figure out why
- Whether you understand what you just deployed, or if it's a black box

---

## 3. Platform Contributor — PR Journey

**Emotional signal:** Confidence and collaboration — CI feels like a knowledgeable reviewer.

**Prerequisites they have:** A fork, a change (e.g., a new chart or a provider doc update).

**Steps to walk:**

1. Read `CONTRIBUTING.md` — are the requirements clear before starting?
2. Read the relevant `CLAUDE.md` (root or `platform/charts/CLAUDE.md`)
3. Make a change to a chart (or simulate one by running checks on an existing chart)
4. `helm lint platform/charts/<chart-name>/`
5. `bash scripts/ha-gate.sh --chart <chart-name>` — scoped to just this chart
6. `helm template platform/charts/<chart-name>/ | grep PodDisruptionBudget` — present?
7. `helm template platform/charts/<chart-name>/ | grep podAntiAffinity` — present?
8. Push and open a PR; read the CI output on the HA Gate workflow

**Watch for:**
- Whether the ha-gate.sh output tells you *what to fix*, not just *that something failed*
- Whether a failure in a pre-existing chart blocks the contributor's unrelated change
- Whether the contributor can reproduce every CI check locally before pushing
- The gap between what CONTRIBUTING.md says and what CI actually checks

---

## 4. Security Auditor — Zero-Trust Verification Journey

**Emotional signal:** Paranoia satisfied — every claim verifiable, not asserted.

**Steps to walk:**

1. Read the "Core Principles" section of the README — list every claim made
2. `python3 contract/validate.py contract/v1/tests/valid.yaml` — does it exit 0?
3. `python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml` — does it exit 1 with a specific message?
4. `grep -rn "docker.io\|quay.io\|ghcr.io\|gcr.io\|registry.k8s.io" platform/charts/*/templates/` — any external registries in templates?
5. Read `platform/vendor/VENDORS.yaml` — are BSL/SSPL licenses actually blocked?
6. Check whether the `autarky.externalEgressBlocked: true` invariant is backed by a NetworkPolicy in any chart template
7. Read `docs/governance/sovereignty.md` — does it match what the code actually does?

**Watch for:**
- Claims in the README that aren't falsifiable by a specific command
- The contract validator accepting configs that violate a stated invariant
- The gap between "autarky.externalEgressBlocked: true" in the contract schema and actual NetworkPolicy enforcement in chart templates
- Any vendor entry in VENDORS.yaml with a blocked license that isn't marked deprecated

---

## 5. Ceremony Observer — Pipeline Health Journey

**Emotional signal:** Confidence in the machine — the loop is advancing real things.

**Steps to walk:**

1. `git log --oneline -10` — do commit messages communicate what changed and why?
2. Read the snapshot output (run `bash .lathe/snapshot.sh`) — is it concise? Does it give health signals or raw dumps?
3. Read the last 4 goals in `.lathe/session/goal-history/` — are different stakeholders getting attention?
4. Check `prd/manifest.json` for the active increment
5. Read `docs/state/agent.md` — is it current with what git log shows?

**Watch for:**
- Whether the snapshot's output is scannable in 30 seconds or requires deep reading to extract health
- Whether the goal history shows genuine rotation across stakeholders or fixation on one
- Whether changelogs cite specific moments ("step 3 of the CLI install") or generic categories ("improved UX")
- Whether `docs/state/agent.md` reflects what's actually happening vs. being stale
