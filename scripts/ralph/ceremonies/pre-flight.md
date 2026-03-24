# Pre-flight Ceremony — Environment Assessment

You are running the **pre-flight ceremony** for the Sovereign Platform. This ceremony runs
**before sprint execution** to honestly assess what the environment can and cannot do. It
annotates stories with any capability gaps so Ralph can code confidently without being
surprised mid-sprint.

**This ceremony is informational, not blocking.** Missing cloud credentials are expected.
Missing tools may limit integration testing but rarely prevent coding and dry-run validation.
The goal is honesty, not gatekeeping.

**This ceremony is idempotent.** Running it multiple times is safe — it re-evaluates and
overwrites any existing `preFlightNotes` on stories that have not yet been started.

---

## Your task

### Step 1 — Check tool availability

Run the following command for each tool in the list below. Collect every result.

```bash
for tool in helm kubectl shellcheck gh kind act docker ko crane jq yq python3; do
  command -v "$tool" && "$tool" version 2>&1 | head -1 || echo "MISSING"
done
```

If the one-liner does not give clean output for a tool, probe it individually:

```bash
command -v helm     && helm version --short 2>&1 | head -1   || echo "MISSING"
command -v kubectl  && kubectl version --client --short 2>&1 | head -1 || echo "MISSING"
command -v shellcheck && shellcheck --version 2>&1 | head -2 | tail -1 || echo "MISSING"
command -v gh       && gh --version 2>&1 | head -1           || echo "MISSING"
command -v kind     && kind version 2>&1 | head -1           || echo "MISSING"
command -v act      && act --version 2>&1 | head -1          || echo "MISSING"
command -v docker   && docker version --format '{{.Client.Version}}' 2>&1 | head -1 || echo "MISSING"
command -v ko       && ko version 2>&1 | head -1             || echo "MISSING"
command -v crane    && crane version 2>&1 | head -1          || echo "MISSING"
command -v jq       && jq --version 2>&1 | head -1           || echo "MISSING"
command -v yq       && yq --version 2>&1 | head -1           || echo "MISSING"
command -v python3  && python3 --version 2>&1 | head -1      || echo "MISSING"
```

Record the result for each tool as either:
- `AVAILABLE <version-string>` — the tool responded
- `MISSING` — `command -v` returned non-zero

Build a **tool capability map**: `{ "helm": "AVAILABLE 3.14.0", "kind": "MISSING", ... }`

Install hints for common missing tools (include these in the printed report):
- `kind`      → `brew install kind`
- `act`       → `brew install act`
- `ko`        → `brew install ko`
- `crane`     → `brew install crane`
- `helm`      → `brew install helm`
- `shellcheck`→ `brew install shellcheck`
- `yq`        → `brew install yq`
- `jq`        → `brew install jq`
- `docker`    → `https://docs.docker.com/desktop/`

### Step 2 — Check credential / environment variable availability

Run the following for each variable. Do not print the values themselves.

```bash
for var in HETZNER_TOKEN CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID GITHUB_TOKEN DIGITALOCEAN_TOKEN AWS_ACCESS_KEY_ID; do
  [[ -n "${!var}" ]] && echo "$var: SET (${#!var} chars)" || echo "$var: NOT SET"
done
```

If the brace-expansion form `${!var}` is not supported in your shell invocation, probe each
variable individually:

```bash
[[ -n "${HETZNER_TOKEN}" ]]        && echo "SET (${#HETZNER_TOKEN} chars)"        || echo "NOT SET"
[[ -n "${CLOUDFLARE_API_TOKEN}" ]] && echo "SET (${#CLOUDFLARE_API_TOKEN} chars)" || echo "NOT SET"
[[ -n "${CLOUDFLARE_ACCOUNT_ID}" ]]&& echo "SET (${#CLOUDFLARE_ACCOUNT_ID} chars)"|| echo "NOT SET"
[[ -n "${GITHUB_TOKEN}" ]]         && echo "SET (${#GITHUB_TOKEN} chars)"         || echo "NOT SET"
[[ -n "${DIGITALOCEAN_TOKEN}" ]]   && echo "SET (${#DIGITALOCEAN_TOKEN} chars)"   || echo "NOT SET"
[[ -n "${AWS_ACCESS_KEY_ID}" ]]    && echo "SET (${#AWS_ACCESS_KEY_ID} chars)"    || echo "NOT SET"
```

Record the result for each variable as either `SET` or `NOT SET`.

Build a **credential capability map**: `{ "HETZNER_TOKEN": "NOT SET", "GITHUB_TOKEN": "SET", ... }`

### Step 3 — Check GitHub CLI authentication

```bash
gh auth status 2>&1 | head -3
```

If gh is MISSING, skip this step and record `gh_auth: "UNAVAILABLE (gh not installed)"`.

Otherwise record:
- `gh_auth: "authenticated as: <username>"` if the output contains "Logged in to"
- `gh_auth: "NOT AUTHENTICATED"` if gh is installed but not logged in

### Step 4 — Check local Kubernetes cluster availability

Run both commands and record the output:

```bash
kubectl cluster-info 2>&1 | head -2
kind get clusters 2>&1
```

If kubectl is MISSING, record `kubectl_cluster: "UNAVAILABLE (kubectl not installed)"`.

Otherwise classify the cluster state as one of:
- `REACHABLE` — `cluster-info` returned a control plane URL without error
- `UNREACHABLE` — `cluster-info` returned a connection error
- `NO_KIND_CLUSTERS` — kind is available but `kind get clusters` returned nothing or "No kind clusters found"
- `KIND_CLUSTERS_AVAILABLE <names>` — kind returned one or more cluster names

### Step 5 — Read the active sprint and identify work to be done

```bash
cat prd/manifest.json
```

Read the `activeSprint` field to get the sprint file path (e.g. `prd/increment-0-ceremonies.json`).

If `activeSprint` is null or the file does not exist, print:
`No active sprint found. Run the plan ceremony first: claude < scripts/ralph/ceremonies/plan.md`
and exit.

```bash
cat <activeSprint file>
```

Load all stories where **both** `passes: false` AND `reviewed: false`. These are the stories
to be assessed. Stories where `passes: true` or `reviewed: true` are already done and skipped.

If no such stories exist, print:
`All stories in the active sprint are complete or under review. Nothing to pre-flight.`
and exit.

### Step 6 — Cross-reference story requiredCapabilities against the capability matrix

For each story loaded in Step 5, read its `requiredCapabilities` array. This field may be
absent — if it is missing or empty, the story has no special requirements and is READY.

The `requiredCapabilities` array may contain any combination of:
- Tool names: `helm`, `kubectl`, `shellcheck`, `gh`, `kind`, `act`, `docker`, `ko`, `crane`, `jq`, `yq`, `python3`
- Credential names: `HETZNER_TOKEN`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `GITHUB_TOKEN`, `DIGITALOCEAN_TOKEN`, `AWS_ACCESS_KEY_ID`
- Cluster states: `CLUSTER_REACHABLE`, `KIND_AVAILABLE`

For each required capability, check the capability maps built in Steps 1–4:
- A tool is satisfied if its map entry is `AVAILABLE <...>`
- A credential is satisfied if its map entry is `SET`
- `CLUSTER_REACHABLE` is satisfied if `kubectl_cluster` is `REACHABLE`
- `KIND_AVAILABLE` is satisfied if `kind` is `AVAILABLE <...>` AND `kubectl_cluster` includes `KIND_CLUSTERS_AVAILABLE`

For each **unsatisfied** required capability, annotate the story using Python:

```python
story.setdefault('preFlightNotes', []).append(
    f"PRE-FLIGHT: '{capability}' is not available. "
    f"Story can be coded but cannot be integration-tested. "
    f"Will be marked with blocker on completion."
)
```

For each **satisfied** required capability, no annotation is needed.

After annotating, write the updated sprint file back in place:

```python
import json

sprint_file = "<activeSprint file>"  # from manifest.json
with open(sprint_file) as f:
    sprint = json.load(f)

for story in sprint['stories']:
    if story.get('passes') or story.get('reviewed'):
        continue  # skip completed stories
    # ... apply annotations as above ...

with open(sprint_file, 'w') as f:
    json.dump(sprint, f, indent=2)
```

Only write the file if at least one annotation was added. If all stories are READY, no write
is necessary (but writing an identical file is also harmless).

### Step 7 — Print the capability matrix and sprint readiness report

Print the following to stdout. Fill in real values from Steps 1–4 and 6.

```
=== Pre-flight Capability Matrix ===

Tools:
  ✓ helm        3.14.0
  ✓ kubectl     v1.29.0
  ✓ shellcheck  0.9.0
  ✗ kind        MISSING — install: brew install kind
  ✗ act         MISSING — install: brew install act
  ✓ gh          2.45.0 (authenticated as: <user>)
  ✓ docker      25.0.3
  ✗ ko          MISSING — install: brew install ko
  ✗ crane       MISSING — install: brew install crane
  ✓ jq          jq-1.7.1
  ✓ yq          4.40.5
  ✓ python3     Python 3.12.2

Credentials:
  ✗ HETZNER_TOKEN        NOT SET
  ✗ CLOUDFLARE_API_TOKEN NOT SET
  ✗ CLOUDFLARE_ACCOUNT_ID NOT SET
  ✓ GITHUB_TOKEN         SET (40 chars)
  ✗ DIGITALOCEAN_TOKEN   NOT SET
  ✗ AWS_ACCESS_KEY_ID    NOT SET

Cluster:
  ✗ No reachable cluster (kubectl: error connecting to server)
  ✗ No kind clusters running

Sprint readiness: <activeSprint file>
  <id> ✓ READY   — <title> (no special capabilities required)
  <id> ✓ READY   — <title>
  <id> ⚠ PARTIAL — <title>
               requiredCapabilities: [HETZNER_TOKEN] NOT SET
               Story will be coded and dry-run tested but cannot be live-tested.

Smoke testing available:
  ✓ helm dry-run   (helm template / helm lint)
  ✓ shellcheck
  ✓ kubectl dry-run (--dry-run=client)
  ✗ kind cluster   (kind not installed — cannot spin up local cluster)
  ✗ live cloud     (no provider tokens set)

Run: ./scripts/ralph/ceremonies.sh to continue with sprint execution.
```

Tone guidance for the report:
- ✓ for available / set / ready
- ✗ for missing / not set / unavailable
- ⚠ for partial (story has capabilities it can't fully exercise, but can still be coded)
- Missing cloud credentials are **expected and normal**. Do not flag them as problems —
  note them matter-of-factly.
- Missing tools like `kind` or `act` limit integration testing but do not prevent coding
  or helm/shellcheck dry-run validation.
- Only flag something as a genuine blocker if the story literally cannot be coded without it
  (e.g. a story whose sole deliverable is a running kind cluster, and kind is not installed).

---

## Idempotency guarantee

- Stories with `passes: true` or `reviewed: true` are always skipped.
- `preFlightNotes` entries are appended, not replaced. Running twice may produce duplicate
  notes. To reset, manually clear the `preFlightNotes` array on a story before re-running.
- The capability matrix is always re-evaluated from scratch — it reflects the current
  environment state at the time the ceremony runs.
- If the environment has changed since the last run (e.g. a token was set, kind was installed),
  the new run reflects the updated state.
