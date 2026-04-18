# Stakeholder Journeys

Concrete walkthroughs the customer champion uses each cycle. Pick a stakeholder, run these steps, and report what you felt. The steps are what to try; what to watch for is what to notice when you do.

---

## Alex — The Self-Hosting Developer

**Emotional signal: excitement.** "I want to tell someone this exists."

**First-encounter journey (kind path):**

```bash
# Step 1: Prerequisites check
docker info                         # Is Docker Desktop running?
kind version && kubectl version --client && helm version && gh --version

# Step 2: Clone
git clone https://github.com/libliflin/sovereign
cd sovereign

# Step 3: Bootstrap the kind cluster
./cluster/kind/bootstrap.sh         # watch narration — does it say what it's doing?
# ./cluster/kind/bootstrap.sh --dry-run  # preview (does this work?)

# Step 4: Verify the cluster came up
kubectl --context kind-sovereign-test get nodes
kubectl --context kind-sovereign-test get pods -A | grep -v Running | grep -v Completed

# Step 5: Install a chart
helm install test-release platform/charts/sealed-secrets/ \
  --namespace sealed-secrets --create-namespace \
  --kube-context kind-sovereign-test --wait

# Step 6: Verify it
kubectl --context kind-sovereign-test get pods -n sealed-secrets

# Step 7: Explore what else is there
ls platform/charts/
# Does the README explain what each chart does and how they fit together?

# Step 8: Clean up
kind delete cluster --name sovereign-test
```

**What to watch for:**
- Does `bootstrap.sh` fail silently if Docker Desktop isn't running?
- Does `--dry-run` exist and preview what will happen?
- Does each bootstrap step narrate what it's doing, or is it silent until success or failure?
- Do the pods come up clean, or are there CrashLoopBackOffs to diagnose?
- Is there a clear "what's next?" path from the kind quick start to a real deployment?
- How long does the bootstrap take? Does it feel like progress is happening?

---

## Morgan — The Production Operator

**Emotional signal: trust and transparency.** "I know what it did and why."

**First-encounter journey (VPS deployment):**

```bash
# Step 1: Pre-flight cost check
cp bootstrap/config.yaml.example bootstrap/config.yaml
# Edit: domain, provider (hetzner), nodes.count (3), nodes.type (cx32)
cp .env.example .env
# Does .env.example tell you exactly where to get each credential?
source .env

./bootstrap/bootstrap.sh --estimated-cost
# Is the output clear? Does it break down cost per node and per service?

# Step 2: Provision
./bootstrap/bootstrap.sh --confirm-charges
# Does it narrate each step? Does it say which node is being provisioned?
# If it fails, does the error point to the cause?

# Step 3: Verify
./bootstrap/verify.sh
# Does it check every service? Does it name anything that isn't ready?

# Step 4: Observe
# Open https://grafana.<domain>
# Is there a cluster overview dashboard by default?
# Can you see all nodes without configuration?
# Are the other services (Forgejo, ArgoCD, Keycloak) listed somewhere?

# Step 5: Push a change and watch ArgoCD
# Make a change in a chart, push it, watch ArgoCD sync
# Does ArgoCD narrate the sync? Does Grafana show the rollout?

# Step 6: 3am scenario
# Something is wrong. Can you identify the broken service from Grafana in < 2 min?
# Is the error correlated in Loki (logs) and Tempo (traces)?
# Does a Falco alert produce a readable description?
```

**What to watch for:**
- Does `.env.example` explain every field and where to get it?
- Does `bootstrap.sh` output tell you what it's doing at each step?
- Does `verify.sh` list what passed and what failed (not just exit 0 or 1)?
- Are Grafana dashboards present out of the box for services deployed by bootstrap?
- Are log queries pre-configured in Loki for common services?
- Does ArgoCD Application sync status surface clearly in Grafana?
- Are Falco alerts visible in Grafana with readable descriptions?

---

## Jordan — The Platform Contributor

**Emotional signal: clarity and confidence.** "The rules are stated, I know what passing looks like before I submit."

**First-encounter journey (adding a new chart):**

```bash
# Step 1: Read the rules
# Read CLAUDE.md top to bottom
# Read platform/charts/CLAUDE.md
# Look at an existing chart for reference:
ls platform/charts/sealed-secrets/
cat platform/charts/sealed-secrets/Chart.yaml
cat platform/charts/sealed-secrets/values.yaml

# Step 2: Create the chart
mkdir -p platform/charts/myservice/templates
# Write Chart.yaml, values.yaml, templates/deployment.yaml, etc.

# Step 3: Local quality gates (should match CI exactly)
helm dependency update platform/charts/myservice/ 2>/dev/null || true
helm lint platform/charts/myservice/

helm template sovereign platform/charts/myservice/ \
  --set global.domain=sovereign-autarky.dev \
  > /tmp/rendered.yaml

grep "kind: PodDisruptionBudget" /tmp/rendered.yaml || echo "MISSING: PodDisruptionBudget"
grep "podAntiAffinity" /tmp/rendered.yaml || echo "MISSING: podAntiAffinity"
grep "replicaCount" platform/charts/myservice/values.yaml  # must be >= 2

python3 scripts/check-limits.py < /tmp/rendered.yaml     # every container needs requests+limits

grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/myservice/templates/ && echo "FAIL: external registry" || echo "PASS: autarky"

# Step 4: Submit
git push
# Open PR, watch validate.yml and ha-gate.yml run
# If CI fails — is the failure message actionable?
```

**What to watch for:**
- Is the gap between local gates and CI gates exactly zero?
- Do the CLAUDE.md quality gate commands produce the same output as CI?
- Is `check-limits.py` usage documented clearly enough to run without reading the source?
- Are there CI checks with no local equivalent (requiring a secret, a running cluster, etc.)?
- If CI fails on a valid chart (false positive), is the error message diagnostic enough to tell you why?

**Ceremony script contribution journey:**

```bash
# Read the ceremony system
cat scripts/ralph/ceremonies.py   # or relevant ceremony script
ls scripts/ralph/tests/           # what tests exist?

# Run existing tests
for tf in scripts/ralph/tests/test_*.py; do python3 "$tf" && echo "PASS: $tf" || echo "FAIL: $tf"; done

# Make a change, run tests, check shellcheck
shellcheck -S error scripts/ralph/<changed_script>.sh

git push && open PR
```

---

## Sam — The Security Evaluator

**Emotional signal: paranoia satisfied.** "I verified it myself. I don't have to take it on faith."

**First-encounter journey (security audit):**

```bash
# Step 1: Read the governance claims
cat docs/governance/sovereignty.md
cat docs/governance/license-policy.md
cat docs/governance/cluster-contract.md

# Step 2: Verify license compliance
cat platform/vendor/VENDORS.yaml
# Does every entry have license, distroless, and upstream fields?
# Any BSL or SSPL entries not marked deprecated?

# Step 3: Autarky audit
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/
# Expect: no output. Any output is a violation.

# Step 4: Contract validation
cat contract/v1/
python3 contract/validate.py contract/v1/tests/valid.yaml
echo "Exit: $?"   # Must be 0

python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml
echo "Exit: $?"   # Must be 1, with a readable error message naming the field

# Are there other invalid-*.yaml test fixtures? Run them all:
for f in contract/v1/tests/invalid-*.yaml; do
  result=$(python3 contract/validate.py "$f" 2>&1)
  [[ $? -ne 0 ]] && echo "PASS (rejected): $f" || echo "FAIL (accepted): $f"
done

# Step 5: CI workflow audit
cat .github/workflows/validate.yml
# Look for: pull_request_target (dangerous), issue_comment (dangerous)
# Confirm triggers are only: pull_request, push

cat .github/workflows/ha-gate.yml
# Same check

# Step 6: Istio mTLS enforcement
grep -r "STRICT\|PERMISSIVE\|PeerAuthentication" platform/charts/istio/
# STRICT should be the default — is it enforced in the chart or just documented?

# Step 7: Network policy
grep -r "NetworkPolicy" platform/charts/*/templates/
# Are there deny-all default policies?
```

**What to watch for:**
- Are the governance doc claims (sovereignty, autarky, zero-trust) machine-verifiable from CI?
- Is there any gap between what `platform/vendor/VENDORS.yaml` claims and what CI enforces?
- Do the contract validator tests cover the autarky invariants comprehensively?
- Are the CI workflow triggers safe (`pull_request`, not `pull_request_target`)?
- Is Istio mTLS STRICT enforced in chart templates, not just documented?
- Are NetworkPolicy deny-all defaults in place for all service namespaces?

---

## Casey — The Contract Consumer

**Emotional signal: confidence and predictability.** "The contract is a stable API I can depend on."

**First-encounter journey (integrating the validator):**

```bash
# Step 1: Read the schema
ls contract/v1/
cat contract/v1/schema.yaml    # or equivalent — understand the fields

# Step 2: Write a minimal valid config
cat > /tmp/test-values.yaml << 'EOF'
apiVersion: sovereign.dev/cluster/v1
runtime:
  domain: myplatform.example.com
  imageRegistry:
    internal: harbor.myplatform.example.com/sovereign
storage:
  block:
    storageClassName: ceph-block
  file:
    storageClassName: ceph-filesystem
  object:
    endpoint: https://minio.myplatform.example.com
    credentialsSecret: minio-credentials
network:
  networkPolicyEnforced: true
  ingressClass: nginx
pki:
  clusterIssuer: letsencrypt-prod
autarky:
  externalEgressBlocked: true
  imagesFromInternalRegistryOnly: true
EOF

python3 contract/validate.py /tmp/test-values.yaml
echo "Exit: $?"   # Expect 0

# Step 3: Test error messages
# Remove a required field
python3 -c "
import re
with open('/tmp/test-values.yaml') as f:
    c = f.read()
with open('/tmp/test-invalid.yaml', 'w') as f:
    f.write(re.sub(r'.*externalEgressBlocked.*\n', '', c))
"
python3 contract/validate.py /tmp/test-invalid.yaml
# Does the error say *which field* is missing and *why it's required*?

# Test autarky enforcement
python3 contract/validate.py contract/v1/tests/invalid-egress-not-blocked.yaml
# Does the error say exactly which field is wrong and what value is required?

# Step 4: Scripting integration
python3 contract/validate.py /tmp/test-values.yaml && echo "VALID" || echo "INVALID: see above"
# Does this work cleanly in a CI pipeline without extra dependencies?

# Step 5: Check for external dependencies
head -20 contract/validate.py
# Should use stdlib only — no pip installs required
```

**What to watch for:**
- Does the validator use stdlib only (no external dependencies that require pip)?
- Do error messages name the exact field, not just "validation failed"?
- Does the schema version appear in the file and in error output?
- Is there a clear way to tell which version of the contract a given values file targets?
- Does exit code 0/1 behave predictably for scripting?
