# Stakeholder Journeys

Concrete first-encounter journeys for each stakeholder. Walk these each cycle. The emotional signal notes what the champion should track at each step.

---

## S1 — The Self-Hoster (Platform Operator)

**Emotional signal: Confidence.** Track unease. Each step that produces ambiguous output or an unrecoverable error is a confidence loss.

### Kind path (walk this first — no cloud account needed)

```bash
# Prerequisites check
docker info                         # Docker Desktop must be running
kind version                        # must be installed
kubectl version --client            # must be installed
helm version                        # must be installed
shellcheck --version                # must be installed

# Clone and start
git clone https://github.com/libliflin/sovereign
cd sovereign
./cluster/kind/bootstrap.sh         # ~4 minutes — watch the output

# Verify cluster
kind get clusters                   # should show sovereign-test
kubectl --context kind-sovereign-test get nodes   # should show 3 nodes Ready

# Smoke test a chart
helm install test-release cluster/kind/charts/sealed-secrets/ \
  --namespace sealed-secrets --create-namespace \
  --kube-context kind-sovereign-test --wait
kubectl --context kind-sovereign-test get pods -n sealed-secrets

# Validate the cluster contract
python3 contract/validate.py cluster-values.yaml

# Tear down
kind delete cluster --name sovereign-test
```

**Watch for friction at:**
- `bootstrap.sh` output — is progress legible or a wall of text?
- The gap between "prerequisites" and what's actually needed (Docker Desktop vs. Docker CLI)
- Error messages when bootstrap fails — do they tell you what to fix?
- The `helm install --wait` output — does it tell you what's happening during the wait?
- `contract/validate.py` output — does it say clearly what passed and why?

### VPS path (walk when kind path is solid)

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
# Edit: domain, provider (hetzner), nodes.count (must be 3 or 5)
cp .env.example .env
# Edit: HETZNER_TOKEN, CLOUDFLARE_API_TOKEN, etc.
source .env

./bootstrap/bootstrap.sh --estimated-cost   # no money spent yet
./bootstrap/bootstrap.sh --confirm-charges  # provisions real servers

./bootstrap/verify.sh
```

**Watch for friction at:**
- `.env.example` — does it tell you where to get each credential?
- `--estimated-cost` — does it give enough to make a spending decision?
- Node count validation — does bootstrap fail clearly when count is even or < 3?
- `verify.sh` output — does green mean green, or green-ish?

---

## S2 — The Platform Developer

**Emotional signal: Momentum.** Track stalls, especially silent ones. A deploy that fails with no signal is the worst moment.

### First push

```bash
# Assume platform is running at domain=example.com
git clone https://forgejo.example.com/team/my-service
cd my-service
# make a small change
git add . && git commit -m "test commit"
git push origin main
# watch Forgejo Actions at https://forgejo.example.com/team/my-service/actions
```

**Watch for friction at:**
- Forgejo authentication — SSO via Keycloak or separate account? Is it obvious?
- CI pipeline visibility — can you see what's running without prior knowledge?
- ArgoCD sync — does the change show up at https://argocd.example.com automatically?

### Finding a service / debugging

```bash
# Backstage
open https://backstage.example.com     # look for my-service in catalog

# Grafana
open https://grafana.example.com       # find logs/metrics for my-service
# Try: Explore → Loki → filter by namespace
```

**Watch for friction at:**
- Backstage catalog — is the service listed without extra configuration?
- Grafana — are there useful default dashboards, or do you start from scratch?
- Keycloak SSO — does single-sign-on actually work across Forgejo, ArgoCD, Grafana?

### Browser IDE (code-server)

```bash
open https://code.example.com
# editor should open with persistent workspace
# kubectl, helm, k9s should be available in the terminal
kubectl get pods    # should work with cluster context
```

**Watch for friction at:**
- Workspace persistence — does state survive a session close?
- Toolchain — are kubectl, helm, k9s available without manual install?

---

## S3 — The Chart Author / Contributor

**Emotional signal: Respect.** Track hazing — rules that exist only as tribal knowledge. Every gate failure should be self-explanatory.

### Writing a new chart

```bash
# Start from an existing chart as reference
ls platform/charts/                   # browse existing charts
cat platform/charts/forgejo/Chart.yaml
cat platform/charts/forgejo/values.yaml
cat platform/charts/forgejo/templates/poddisruptionbudget.yaml

# Create a new chart
mkdir -p platform/charts/my-new-service/templates

# Write Chart.yaml, values.yaml, templates/
# Conventions to follow — read these first:
cat platform/charts/CLAUDE.md
cat CLAUDE.md | grep -A20 "Quality Gates"

# Run gates
helm lint platform/charts/my-new-service/
helm template platform/charts/my-new-service/ | grep PodDisruptionBudget
helm template platform/charts/my-new-service/ | grep podAntiAffinity
helm template platform/charts/my-new-service/ | python3 scripts/check-limits.py
bash scripts/ha-gate.sh
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/my-new-service/templates/ && echo FAIL || echo PASS

# Shellcheck any scripts
shellcheck -S error scripts/my-new-script.sh
```

**Watch for friction at:**
- Gate output — does ha-gate.sh tell you which chart and which check failed?
- Convention discoverability — is the global.imageRegistry pattern clear from examples?
- check-limits.py output — does it name the specific container missing limits?
- The gap between local gate results and CI results — do they match?

### Submitting a PR

```bash
git checkout -b feat/my-new-service
git add platform/charts/my-new-service/
git commit -m "feat: add my-new-service chart"
git push origin feat/my-new-service
gh pr create --title "feat: add my-new-service chart"
# watch CI: validate.yml, ha-gate.yml
```

**Watch for friction at:**
- CI failure messages — do they name the exact file and line that failed?
- The ha-gate.yml workflow — does it run only on changed charts (not all charts)?
- The validate.yml workflow — does it give a clear summary or just raw output?

---

## S4 — The Security Auditor

**Emotional signal: Certainty.** Track unverifiable claims. Anything that can only be asserted, not proven by a command, is the signal.

### Contract verification

```bash
# Verify the cluster contract
python3 contract/validate.py cluster-values.yaml
# Expected: "CONTRACT VALID" or specific errors

# Verify autarky in chart templates
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "AUTARKY FAIL" || echo "AUTARKY PASS"

# Verify mTLS enforcement in Istio chart
helm template platform/charts/istio/ | grep -A5 "kind: PeerAuthentication"
# Must show mode: STRICT

# Run contract test suite
python3 contract/validate.py contract/v1/tests/valid.yaml
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml  # must fail

# Read constitutional gates
python3 -c "
import json
data = json.load(open('prd/constitution.json'))
for g in data['gates']:
    print(g['id'], g['title'])
    print('  Command:', g['indicator']['command'][:80])
"
```

**Watch for friction at:**
- `contract/validate.py` output — does it explain each error clearly?
- Autarky grep — does it find false positives (values.yaml refs vs. template refs)?
- Istio PeerAuthentication — does the rendered output actually show STRICT, or is it parameterized away?
- The constitution.json `_retired` section — does it explain *why* each gate was retired?

### License audit

```bash
cat platform/vendor/VENDORS.yaml | python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin)
for v in data.get('vendors', []):
    print(v['name'], v['license'], 'DEPRECATED' if v.get('deprecated') else '')
"
```

**Watch for friction at:**
- BSL/AGPL licenses — are they marked deprecated with a migration path?
- The `ha_exception` pattern — is it documented and auditable?

---

## S5 — The Delivery Machine (Ralph / Ceremony Agent)

**Emotional signal: Orientation.** Track archaeology — any moment where the agent has to read history to understand the present.

### Sprint orientation

```bash
# Each cycle: orient first
cat docs/state/agent.md             # current patterns, gotchas, state
cat prd/manifest.json | python3 -c "
import json, sys
m = json.load(sys.stdin)
active = [i for i in m['increments'] if i.get('status') == 'active']
print('Active:', active[0] if active else 'none')
"

# Find top story
cat prd/increment-N-<name>.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
pending = [s for s in data['stories'] if not s.get('passes')]
pending.sort(key=lambda s: s.get('priority', 999))
if pending:
    s = pending[0]
    print(s['id'], s['title'])
    print('ACs:', s.get('acceptanceCriteria'))
"
```

**Watch for friction at:**
- `agent.md` accuracy — does it reflect the current codebase or a past state?
- Story AC commands — do they reference flags and files that actually exist?
- Gate output — does it name the specific file and line to fix?
- The G1 gate — does it catch both syntax errors and broken imports?

### Quality gates (run before `passes: true`)

```bash
# Chart story
helm lint platform/charts/<name>/
helm template platform/charts/<name>/ | grep PodDisruptionBudget
helm template platform/charts/<name>/ | grep podAntiAffinity
grep -E 'replicaCount:[[:space:]]+[2-9]' platform/charts/<name>/values.yaml
helm template platform/charts/<name>/ | python3 scripts/check-limits.py

# Script story
shellcheck -S error <script>.sh

# Any chart story — autarky gate
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "AUTARKY FAIL" || echo "AUTARKY PASS"
```

**Watch for friction at:**
- check-limits.py — does it name the container missing limits?
- ha-gate.sh — does it tell you exactly which chart and which rule failed?
- Autarky grep — does it differentiate template refs from values refs?
