# Stakeholder Journeys

Concrete first-encounter journeys for each stakeholder. The champion walks one of these each cycle. Steps are literal — commands to run, docs to read, output to observe.

---

## Journey 1: Self-Hoster — Bringing Up a Real Cluster

**Emotional signal:** Confidence. Every step should feel expected, not surprising.

**Starting point:** 3 Hetzner nodes, a domain on Cloudflare, a local machine with bash/ssh/kubectl/helm.

1. Read `README.md` top-to-bottom. Register: 3-node minimum is enforced by `bootstrap.sh`.
2. `git clone https://github.com/libliflin/sovereign && cd sovereign`
3. `cp bootstrap/config.yaml.example bootstrap/config.yaml`
4. Open `bootstrap/config.yaml`. Try to fill in: `domain`, `provider`, `frontDoor`, `sshKeyPath`, `nodes.count`, `hetzner.apiToken`, `hetzner.sshKeyName`, `cloudflare.apiToken`, `cloudflare.accountId`, `cloudflare.zoneId`, `cloudflare.tunnelName`, `platform.repoUrl`.
5. `cp .env.example .env` — source credentials.
6. `./bootstrap/bootstrap.sh --estimated-cost` — verify cost estimate before spending.
7. `./bootstrap/bootstrap.sh --confirm-charges` — provision real servers.
8. Wait for bootstrap to complete. Read every line of output — does each phase say what it's doing?
9. `./bootstrap/verify.sh` — all checks should pass within 5-10 minutes of DNS propagation.
10. Open `https://argocd.<domain>` — login with printed admin credentials.
11. Open `https://forgejo.<domain>` — log in via Keycloak SSO.
12. Push a commit to a test repo — watch Forgejo CI trigger and ArgoCD sync.

**Where to stretch:** After the platform is up, try to rotate an OpenBao token. Try to add a new user in Keycloak and see them propagate to Forgejo. Try `./bootstrap/bootstrap.sh` against a different provider (generic/bare-metal).

**Common friction moments:**
- `config.yaml.example` field is ambiguous — what exactly is `cloudflare.tunnelName`?
- Bootstrap fails mid-run with no resume path — must re-run from the start.
- `verify.sh` passes but ArgoCD shows apps out of sync.
- SSO login to Forgejo fails because Keycloak isn't ready yet.

---

## Journey 2: Platform Contributor — Adding a Helm Chart

**Emotional signal:** Momentum. Quality gates should be fast, clear, and consistent with CI.

**Starting point:** A forked repo, feature branch, a chart to add or modify. Kind optionally running.

1. Read `CONTRIBUTING.md` top-to-bottom. Note the pre-push checklist.
2. Create `platform/charts/<name>/` with `Chart.yaml`, `values.yaml`, `templates/`.
3. Ensure `values.yaml` has: `replicaCount: 2` minimum, `podDisruptionBudget`, `podAntiAffinity`, `resources.requests/limits`, `global.imageRegistry` reference.
4. `helm lint platform/charts/<name>/` — must exit 0.
5. `bash scripts/ha-gate.sh --chart <name>` — scoped to this chart; must exit 0.
6. `grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/<name>/templates/` — must return no matches.
7. `grep -n ":\s*latest" platform/charts/<name>/values.yaml` — must return no matches.
8. If adding an ArgoCD app: `python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read())" platform/argocd-apps/<tier>/<name>-app.yaml` — must exit 0.
9. Create PR. Watch `validate.yml` CI workflow.
10. Read CI failure output — does it name exactly what to fix?

**Where to stretch:** Try running `bash scripts/ha-gate.sh` (no `--chart` flag) against the full chart corpus. Watch it handle `platform/charts/_globals/` (no replicaCount field). Try the autarky check across all charts. Try adding a new namespace to `platform/charts/network-policies/values.yaml`.

**Common friction moments:**
- `ha-gate.sh` runs under `set -euo pipefail` and a `grep` with no match kills the script.
- CI runs a check that isn't documented in `CONTRIBUTING.md`.
- The HA gate passes locally but CI fails on a different check.
- `platform/charts/_globals/` causes `ha-gate.sh` to exit early with a false failure.

---

## Journey 3: Developer on Sovereign — Daily Development Work

**Emotional signal:** Reliability. The platform should be invisible — never demanding attention.

**Starting point:** Keycloak credentials, a team repo in Forgejo, Grafana access.

1. Open `https://forgejo.<domain>` — log in via Keycloak SSO.
2. Clone team repo: `git clone https://forgejo.<domain>/<org>/<repo>`.
3. Push a commit: `git commit -am "test" && git push`.
4. Watch Forgejo Actions (CI) trigger — observe build log output.
5. Open `https://argocd.<domain>` — see the app sync within minutes.
6. Open `https://grafana.<domain>` — find the service's metrics dashboard.
7. Open Loki in Grafana — search for the service's log output.
8. Try to access `https://vault.<domain>` (OpenBao) — retrieve a test secret.
9. Try to access `https://backstage.<domain>` — find the service in the catalog.

**Where to stretch:** Try the full on-call path: trigger an alert (let a pod fail), see it arrive in Alertmanager, find the corresponding Loki logs, trace the request in Tempo. Try rotating a credential: update a Sealed Secret and verify it propagates.

**Common friction moments:**
- Keycloak session expires and the re-login flow is confusing.
- Grafana shows a service but the dashboard is empty (scrape not configured).
- Loki log query times out because the time range is too broad.
- Backstage catalog is stale — service exists but isn't registered.

---

## Journey 4: Security Auditor — Verifying Zero-Trust Claims

**Emotional signal:** Paranoia satisfied. Every claim must be machine-verifiable.

**Starting point:** Repo cloned locally, helm installed.

1. Read `docs/architecture.md` — Security Model section. List every claim.
2. Claim: "mTLS everywhere." Verify: `helm template platform/charts/istio/ | grep -A5 PeerAuthentication` — confirm `mode: STRICT`.
3. Claim: "No external registries." Verify: `grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/*/templates/` — expect no output.
4. Claim: "Sovereignty contract enforced." Verify:
   - `python3 contract/validate.py contract/v1/tests/valid.yaml` — must exit 0.
   - `python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml` — must exit 1.
5. Claim: "Deny-all network policy." Read `platform/charts/network-policies/` — verify there's a deny-all base with explicit allows.
6. Check `platform/vendor/VENDORS.yaml` — any BSL-licensed components? Any AGPL without review?
7. Read `contract/validate.py` — does it actually enforce `autarky.externalEgressBlocked: true`?
8. Run G8: `helm template platform/charts/istio/ 2>/dev/null | grep -q "kind: PeerAuthentication" && grep -q "mode: STRICT"`.

**Where to stretch:** Try to write an invalid contract that bypasses the validator. Try to add a chart template that references `docker.io` — does CI catch it (G6)? Find the PeerAuthentication gate path that would let someone set `enabled: false` without the gate catching it.

**Common friction moments:**
- `contract/validate.py` passes a contract that it should reject.
- The Istio gate only checks the default namespace policy, not per-service overrides.
- A chart exists with an external registry reference that G6 missed (old path bug).
- VENDORS.yaml has an entry with no license field.

---

## Journey 5: AI Agent in code-server — Working from Inside the Cluster

**Emotional signal:** Autonomy. No dead ends. Every tool works. The environment doesn't fight the agent.

**Starting point:** Browser open to `https://code.<domain>`.

1. Open browser terminal.
2. `git --version` — verify git is installed.
3. `kubectl version --client` — verify kubectl is installed.
4. `helm version` — verify helm is installed.
5. `shellcheck --version` — verify shellcheck is installed.
6. `kubectl get nodes` — verify kubeconfig is mounted and the cluster is reachable.
7. `git clone https://forgejo.<domain>/<org>/<repo>` — verify Forgejo credentials work.
8. `cd <repo> && bash scripts/ha-gate.sh --chart sealed-secrets` — verify quality gate runs from inside.
9. Edit a file. Push. Verify the push goes through (`git push origin HEAD`).
10. Check that `/home/coder` is persistent: `ls /home/coder` — workspace should survive a pod restart.
11. Check VS Code extensions are pre-installed: YAML, Kubernetes Tools, ShellCheck.

**Where to stretch:** Try opening a PR from inside code-server. Try running `helm install` against the kind cluster from inside. Try running `python3 contract/validate.py` — is Python available? Try a multi-step autonomous task: clone a repo, make a change, run quality gates, open a PR — all without leaving the browser terminal.

**Common friction moments:**
- `kubectl` not installed or kubeconfig not mounted.
- `/home/coder` is ephemeral — workspace reset on pod restart (no PVC).
- Extension install tries `marketplace.visualstudio.com` and fails (no external egress allowed).
- `shellcheck` not available.
- Git credentials require interactive auth that the agent can't complete.
