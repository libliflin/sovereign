# Stakeholder Journeys

Concrete first-encounter journeys the champion walks each cycle. One per stakeholder. These are the steps to actually execute — run the commands, read the output, notice what the stakeholder would feel.

Update this file when the project state changes (new bootstrap path, new service URL, changed convention). Stale journeys mislead more than no journeys.

---

## Journey: The Self-Hoster (kind path)

**Emotional signal to track:** Momentum. Does one command lead cleanly to the next?

**Prerequisites the stakeholder has:** Docker Desktop running, `kind`/`kubectl`/`helm`/`gh` installed.

### Steps to walk

1. Open the README. Read the Quick Start Option A section. Note: is the sequence clear? Are the commands copy-pasteable?

2. Run `./cluster/kind/bootstrap.sh --dry-run` from the repo root. Read the output. Does it explain what it would do?

3. Run `./cluster/kind/bootstrap.sh`. Watch for errors. Time it. Does it give feedback while running or go silent for minutes?

4. Once complete, run the smoke-test command from the README:
   ```bash
   helm install test-release cluster/kind/charts/sealed-secrets/ \
     --namespace sealed-secrets --create-namespace \
     --kube-context kind-sovereign-test --wait
   ```
   Does this work? Does the README give the right chart path?

5. Run `kubectl --context kind-sovereign-test get pods -n sealed-secrets`. Are pods Running?

6. Now ask: what do I do next? Is the README's "next steps" path clear, or does it dead-end?

**Where the wall usually lives:** Step 4 (wrong chart path in README), step 3 (silent failure during bootstrap), step 6 (no clear next step after the smoke test).

---

## Journey: The Self-Hoster (VPS path)

**Emotional signal to track:** Momentum and trust. Does the estimated cost output match reality? Does bootstrap give feedback while running?

**Prerequisites the stakeholder has:** A domain with Cloudflare DNS, Hetzner + Cloudflare tokens, 3 VPS nodes already running Ubuntu 22.04+.

### Steps to walk

1. Read `docs/quickstart.md`. Is it current? Does it reference correct file paths?

2. Copy and edit config:
   ```bash
   cp bootstrap/config.yaml.example bootstrap/config.yaml
   # check: does config.yaml.example document all required fields?
   ```

3. Copy and edit credentials:
   ```bash
   cp .env.example .env
   # check: does .env.example tell you where to get each token?
   ```

4. Run `./bootstrap/bootstrap.sh --estimated-cost`. Read the output. Is it useful?

5. Read `docs/providers/hetzner.md`. Does it give real-world cost numbers and gotchas?

6. Review what `./bootstrap/bootstrap.sh --confirm-charges` would do. Is there a `--dry-run`? Is there a way to inspect the plan before spending money?

**Where the wall usually lives:** Undocumented config fields, `.env.example` that's vague about where to get credentials, bootstrap that fails without a clear error message.

---

## Journey: The Platform Operator

**Emotional signal to track:** Confidence. Does the observability tell me what I need to know?

**Prerequisites the stakeholder has:** A running cluster (kind or VPS). `kubectl` configured. Access to Grafana.

### Steps to walk

1. Check the state of the cluster:
   ```bash
   kubectl --context kind-sovereign-test get pods -A | grep -v Running | grep -v Completed
   ```
   Are there any non-Running pods? What's the story?

2. Look at what Helm charts are deployed and which have Grafana datasource ConfigMaps:
   ```bash
   helm template platform/charts/prometheus-stack/ | grep -i datasource
   helm template platform/charts/loki/ | grep -i datasource
   ```
   Do the observability charts register themselves in Grafana automatically?

3. Check HA posture across deployed charts:
   ```bash
   bash scripts/ha-gate.sh
   ```
   Read the output. Are there any failures? If so, which charts, and what's missing?

4. Simulate a "what failed" investigation: pick a chart, look at its Helm values for resource limits, and verify `check-limits.py` would pass:
   ```bash
   helm template platform/charts/prometheus-stack/ | python3 scripts/check-limits.py
   ```

5. Read the network-policies chart values to understand what egress is being controlled:
   ```bash
   cat platform/charts/network-policies/values.yaml
   ```
   Does this list all deployed namespaces? Is anything missing?

6. Ask: if I got paged right now because `argocd.<domain>` was unreachable, what would I look at first? Does the observability stack guide that investigation?

**Where the wall usually lives:** A chart missing its Grafana datasource ConfigMap, the ha-gate showing a PDB missing, a namespace not in the network-policies egress baseline.

---

## Journey: The Developer on the Platform

**Emotional signal to track:** Flow. Does the environment disappear, or do I keep hitting it?

**Prerequisites the stakeholder has:** A URL for code-server, SSO credentials (Keycloak).

### Steps to walk

1. Open `code-server` at its configured URL. Authenticate through Keycloak SSO.

2. Open a terminal in code-server. Run:
   ```bash
   kubectl version --client
   helm version
   k9s version
   ```
   Are these tools available? Are they on PATH without any setup?

3. Check the workspace persistence: create a file, close and reopen code-server. Is the file there?

4. Look at the code-server Helm values to understand the toolchain initContainer:
   ```bash
   grep -A 20 toolchainInit platform/charts/code-server/values.yaml
   ```
   Does the toolchain init container copy the right tools?

5. Look at Backstage to find services: navigate to `backstage.<domain>`. Is the service catalog populated? Can you find the ArgoCD, Grafana, and Forgejo entries?

6. Open Forgejo at `forgejo.<domain>`. Can you log in with Keycloak SSO? Create a test repo.

**Where the wall usually lives:** code-server missing `kubectl`/`helm` in PATH (toolchain initContainer not working), Backstage showing empty catalog, SSO not wired to Forgejo or Backstage.

---

## Journey: The Contributor

**Emotional signal to track:** Clarity. Do I know what's expected and does my work meet it?

**Prerequisites the stakeholder has:** The repo forked and cloned. A change in mind — say, a new provider doc or a small Helm chart fix.

### Steps to walk

1. Read `CONTRIBUTING.md`. Does it tell you what gates to run before opening a PR?

2. Read the root `CLAUDE.md` Quality Gates section. Can you run these locally?

3. Try running the key gates against an existing chart:
   ```bash
   bash scripts/ha-gate.sh --chart platform/charts/prometheus-stack
   helm lint platform/charts/prometheus-stack/
   helm template platform/charts/prometheus-stack/ | python3 scripts/check-limits.py
   ```
   Do these work? Are the error messages clear when something fails?

4. Try `shellcheck` on a script:
   ```bash
   shellcheck -S error scripts/ha-gate.sh
   ```
   Does it pass? Do errors give you enough information to fix them?

5. Open `.github/workflows/validate.yml`. Compare what CI checks against what CONTRIBUTING.md documents. Are they aligned?

6. Imagine CI failed on your PR with "Assert replicaCount >= 2" for a chart you modified. Would the CI message tell you which chart, which file, and what value to change?

**Where the wall usually lives:** CONTRIBUTING.md that's outdated or references wrong paths, CI failure messages that name the check but not the specific fix, missing documentation of the `ha_exception` pattern for single-instance services.
