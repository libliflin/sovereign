# Stakeholder Journeys

Concrete step-by-step journeys for the customer champion to walk each cycle. Each journey starts at the very beginning — no prior knowledge assumed. The emotional signal is what you're tracking, not a score. Walk until you feel it, or until you feel it break.

---

## Journey 1: The Self-Hoster — Kind Quickstart

**Emotional signal:** Confidence and momentum. Each step clearly succeeds before the next starts.

**Prerequisites (what they have):** Docker Desktop running, `kind`/`kubectl`/`helm`/`gh`/`shellcheck` installed, the repo cloned.

**Steps:**

1. Read `README.md` — specifically the "Quick Start / Option A" section. Is the path clear? Is there anything you need that isn't in the prerequisites list?

2. Run the dry-run first:
   ```
   ./cluster/kind/bootstrap.sh --dry-run
   ```
   Read every line. Does the output tell you what it's going to do? Would a K8s-unfamiliar developer understand it?

3. Run the actual bootstrap:
   ```
   ./cluster/kind/bootstrap.sh
   ```
   Time it. The README says ~4 minutes. Does it complete? Does the output tell you when each step succeeds? When something takes a long time, does it say it's working or go silent?

4. After bootstrap, install the reference chart:
   ```
   helm install test-release platform/charts/sealed-secrets/ \
     --namespace sealed-secrets --create-namespace \
     --kube-context kind-sovereign-test --wait
   kubectl --context kind-sovereign-test get pods -n sealed-secrets
   ```
   Does the install succeed? Are the pods Running? Does the output of `get pods` look like a passing state?

5. Read the provider cost table in the README. Find the Hetzner CX32 recommended tier. Is the path to "now do this on a real VPS" obvious from here?

6. Open `bootstrap/config.yaml.example`. Read every field. Is it obvious what to fill in? Are there fields that would require outside knowledge (e.g., what is `frontDoor`? what values are valid for `provider`?)?

**Friction watch points:**
- Silent failures in the bootstrap script (script exits 0 but something isn't running)
- Helm dependency errors on the first chart install that require reading chart internals
- Any output that assumes kubectl/Helm familiarity not stated in the prerequisites
- The README's "under 30 minutes" promise — is it realistic?

**The floor for this journey:** After step 4, `kubectl get pods -n sealed-secrets` shows Running pods. That's the minimum viable experience. Everything before it is the path to get there.

---

## Journey 2: The Self-Hoster — VPS Provisioning

**Emotional signal:** Confidence and momentum.

**Prerequisites:** Completed kind quickstart, has a Hetzner account and Cloudflare account, owns a domain.

**Steps:**

1. Copy and fill the config:
   ```
   cp bootstrap/config.yaml.example bootstrap/config.yaml
   cp .env.example .env
   ```
   Read `.env.example` — does it tell you where to get each credential? Is any field ambiguous?

2. Check the cost gate before committing:
   ```
   ./bootstrap/bootstrap.sh --estimated-cost
   ```
   Does the output clearly state the monthly cost and what it's provisioning?

3. Provision (note: this requires real credentials — the champion observes the script structure and does a dry-run if available, doesn't spend money):
   ```
   ./bootstrap/bootstrap.sh --confirm-charges  # (or --dry-run if available)
   ```
   Does the script tell you what it's doing at each step? If a step fails (e.g., wrong API key), does the error tell you which credential is wrong?

4. Verify:
   ```
   ./bootstrap/verify.sh
   ```
   Does the output give a clear pass/fail for each service?

---

## Journey 3: The Platform Developer — First Day on the Platform

**Emotional signal:** Transparent ease. The platform is invisible; only your code is visible.

**Prerequisites:** Sovereign is running (either kind or VPS). You have a service URL and credentials. You've never touched the cluster directly.

**Steps:**

1. Open `backstage.<domain>` in a browser. Log in with SSO (Keycloak). How long does login take? Is the Keycloak login page branded or generic? If there's an error, what does it say?

2. In Backstage, try to register a new service. The path is: add a `catalog-info.yaml` to a repo and register it. Find the "Register an existing component" button. Is it obvious? Does the documentation in Backstage tell you the format for `catalog-info.yaml`?

3. Open `code.<domain>`. Log in. Does code-server open a workspace? What tools are pre-installed (check: `git`, `kubectl`, `helm`, `node`, `python3`)? What's missing that you'd expect to use while developing on this platform?

4. Navigate to `gitlab.<domain>`. Create a new project. Try to push a simple commit. Does GitLab's CI pipeline run? What does the default pipeline do?

5. Navigate to `argocd.<domain>`. Find a running service. Can you tell from the ArgoCD UI what image version is deployed? Can you see the last sync time?

6. Navigate to `grafana.<domain>`. Find the dashboard for a service you care about. Can you tell whether that service is healthy right now?

**Friction watch points:**
- SSO login fails or requires configuration steps the platform developer shouldn't know about
- Backstage catalog is empty with no obvious "add my service" path
- code-server loads but feels like a blank VM — missing the tools a developer would expect
- GitLab CI fails with an error unrelated to the developer's code (e.g., registry pull error, autarky violation)
- ArgoCD shows applications but it's not obvious which one is "mine"

---

## Journey 4: The Contributor — First PR

**Emotional signal:** Certainty. Before I push, I know what CI will check, and I know I pass it.

**Prerequisites:** The repo is forked/cloned. You want to add a new Helm chart for a service (e.g., a minimal `mailpit` chart).

**Steps:**

1. Read `CONTRIBUTING.md` start to finish. What does it tell you? What does it *not* tell you that you'll discover when CI fails?

2. Try to create a minimal new chart from scratch, using only what `CONTRIBUTING.md` told you:
   ```
   mkdir -p platform/charts/myservice/templates
   # create Chart.yaml, values.yaml, templates/deployment.yaml, etc.
   ```

3. Run the quality gates *locally* as documented:
   ```
   helm lint platform/charts/myservice/
   helm template platform/charts/myservice/ | grep PodDisruptionBudget
   helm template platform/charts/myservice/ | grep podAntiAffinity
   bash scripts/ha-gate.sh
   helm template platform/charts/myservice/ | python3 scripts/check-limits.py
   ```
   Does every command produce output that tells you pass or fail clearly?

4. Deliberately introduce a violation: remove the PDB, set `replicaCount: 1`. Run the gates. Do they catch it? Is the error message actionable?

5. Fix the violation and open a PR. Watch CI run. Does the first CI run pass? If it fails, is the failure message identical to what the local gate told you?

**Friction watch points:**
- `check-limits.py` isn't mentioned in `CONTRIBUTING.md` but CI uses it
- `bash scripts/ha-gate.sh` output doesn't tell you *which* chart failed or *why*
- The reference chart to copy from (`platform/charts/sealed-secrets/`) uses patterns not documented in `CONTRIBUTING.md`
- CI has a job that runs locally (shellcheck, helm lint) and a job that doesn't (kind integration test) — the contributor can't replicate the full CI gate locally

---

## Journey 5: The Security Operator — Autarky Audit

**Emotional signal:** Verifiable trust. I can prove what the platform does, not just believe it.

**Prerequisites:** Sovereign is running (or you're operating offline with the codebase). You need to produce an audit report for a compliance review.

**Steps:**

1. Validate the cluster contract:
   ```
   python3 contract/validate.py cluster-values.yaml
   ```
   Does the output tell you specifically which fields are non-compliant? Does it tell you the *meaning* of each field it checks?

2. Verify the autarky gate:
   ```
   grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
     platform/charts/*/templates/ && echo "FAIL" || echo "PASS"
   ```
   Does it pass? If it fails, is the file and line number obvious?

3. Check the license compliance of all vendored dependencies:
   ```
   cat platform/vendor/VENDORS.yaml
   ```
   Is every entry's `license` field present? Are any BSL or SSPL entries present without a `deprecated` flag?

4. Check the contract test suite — the negative test is the most important:
   ```
   python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml
   ```
   It should exit non-zero. If it exits 0, the gate doesn't actually enforce autarky.

5. Open the Grafana Falco dashboard (if cluster is running): navigate to `grafana.<domain>`, find the "Falco Security Events" dashboard, and look at the last 24 hours. Do events have enough context to triage — which pod, which namespace, what syscall pattern matched which rule?

**Friction watch points:**
- `contract/validate.py` output on failure doesn't tell you what value is required, only that the field is missing/wrong
- No Grafana dashboard path documented for Falco events — requires knowing the dashboard name
- `VENDORS.yaml` has entries without all required fields; the CI job catches this but the file itself isn't annotated
- The autarky gate passes but there are image values in `values.yaml` that reference `docker.io` (G6 only checks `templates/`, not `values.yaml`)

---

## Journey 6: The Delivery Machine Maintainer — Sprint Review

**Emotional signal:** Low-friction continuity. The machine runs. I steer.

**Prerequisites:** You're the repo maintainer. A sprint has been running. You want to review what's been accomplished and advance the increment.

**Steps:**

1. Read `docs/state/agent.md`. After reading, can you answer: what is the active sprint working on? What's currently blocked? What should you work on next? If you can't answer these without opening other files, the briefing is stale.

2. Open `prd/manifest.json`. Find the active increment. Open its sprint file (`prd/increment-<N>-*.json`). How many stories are:
   - Not yet passing (`passes: false`)?
   - Passing but not reviewed (`passes: true, reviewed: false`)?
   
3. Run the G1 gate:
   ```
   python3 -c "from scripts.ralph.lib import orient, gates"
   ```
   Does it exit cleanly? Any import errors?

4. Run the orient ceremony:
   ```
   python3 scripts/ralph/ceremonies.py orient
   ```
   (or however ceremonies are invoked — check the script for the correct invocation)
   
   Does the output tell you: current sprint state, gate status, what to work on next?

5. Count remediation sprints in `prd/manifest.json`: look at the last 10 increments. How many have `"name": "remediation"` or a description mentioning "remediation"? If > 2, that's a signal for this cycle's goal.

**Friction watch points:**
- `docs/state/agent.md` says "rewritten each sprint" but the date in the header hasn't changed — it's stale
- The orient ceremony exits 0 but produces no output (silent success is indistinguishable from silent failure)
- Remediation sprints are accumulating — the delivery machine is consuming capacity
- Sprint files and `prd/manifest.json` are out of sync (manifest says `active`, sprint file doesn't exist)
