# Research Before Deploy

## Rule

**Never `helm upgrade --install` a chart for the first time without a research brief.**

If `lathe/state/research/<chart-name>.md` does not exist, you MUST create it
before running any install. This is not optional — it is the same class of
gate as the autarky check. A chart installed without research is a chart
installed blind, and blind installs are how we burned 43 cycles.

Research briefs are written once per chart. After the brief exists, subsequent
upgrades of the same chart do not require re-research (unless the version changes
by a major bump — then re-research the delta).

## Why This Exists

All three agent architectures (ralph, operating-room, lathe) failed the same
way: deploy first, crash, guess fix, repeat. The answers to most crashes were
on the upstream project's website the whole time — architecture support, system
requirements, known limitations, required configuration. Reading first turns a
10-cycle crash loop into a 1-cycle clean install.

## Research Checklist

Before writing the brief, complete every item. If an item cannot be answered
from available sources, write "UNKNOWN — [what you tried]" in the brief.
Unknowns are not blockers, but they are risks.

### 1. Upstream Documentation

Read the project's official docs for:

- **Architecture support:** Does this run on arm64? Is arm64 a first-class
  target or best-effort? Check release notes, CI matrix, and GitHub issues
  for `arm64` or `aarch64`.
- **System requirements:** Minimum CPU, memory, disk. Does it need specific
  kernel features, syscalls, or capabilities?
- **Dependencies:** What CRDs, services, or operators must exist first?
  Map these to the layer model — are all dependencies in lower layers?
- **Known limitations:** What doesn't work in non-cloud environments?
  What features require cloud provider integrations?
- **HA model:** How does this component achieve high availability? Leader
  election? Shared storage? External database? Is HA the default or does
  it require explicit configuration?

Sources to check (in priority order):
1. Official docs site (e.g., cert-manager.io/docs)
2. GitHub repo README and docs/ directory
3. Helm chart README (in the upstream chart repo, not ours)
4. GitHub Issues filtered for `arm64`, `aarch64`, `kind`, `k3s`
5. ArtifactHub page for the chart

### 2. Chart Values and Configuration

Read the chart's `values.yaml` and any README:

- **Required values:** What MUST be set? What has no sensible default?
- **Default assumptions:** Does the chart assume a cloud LoadBalancer?
  A default StorageClass? An ingress controller? DNS resolution?
- **Image references:** What images does the chart pull? Are they
  multi-arch? What registry do they default to?
- **CRD installation:** Does the chart install its own CRDs or expect
  them pre-installed? Is there a `installCRDs` toggle?
- **Namespace expectations:** Does it need to run in a specific namespace?
  Does it create cluster-scoped resources?

For our charts in `platform/charts/<name>/`:
```bash
# Read our values
cat platform/charts/<name>/values.yaml

# Check what images the templates reference
helm template platform/charts/<name>/ | grep "image:"

# Check for hardcoded namespaces
helm template platform/charts/<name>/ | grep "namespace:"
```

For upstream charts (when we use them as dependencies):
```bash
# Read upstream values
helm show values <repo>/<chart> --version <version>
```

### 3. Image Manifest Inspection

Verify that images actually exist for your architecture BEFORE deploying:

```bash
# Use crane (installed via: brew install crane)
# Note: if docker-credential-desktop errors occur, use a clean config:
mkdir -p /tmp/crane-config && echo '{}' > /tmp/crane-config/config.json

DOCKER_CONFIG=/tmp/crane-config timeout 10 crane manifest <image>:<tag> | \
  python3 -c "import sys,json; m=json.load(sys.stdin); \
  [print(p['platform']['os']+'/'+p['platform']['architecture']) \
   for p in m.get('manifests',[])]"

# Expected output for multi-arch:
# linux/amd64
# linux/arm64
# ...

# If only one line or no 'linux/arm64', it's a hard blocker on Apple Silicon.
```

If the image is amd64-only, this is a **hard blocker** on arm64 Apple Silicon.
Document it and look for alternatives. Do NOT attempt to install and "see what
happens" — ImagePullBackoff is not a discovery mechanism.

### 4. VENDORS.yaml Check

Read the entry in `platform/vendor/VENDORS.yaml`:

- **License:** Is `license_allows_vendor: true`? If false, STOP.
- **Deprecated:** Is `deprecated: true`? If yes, use the `alternative`.
- **Version:** Does our pinned version match what we're about to install?
- **Distroless:** Is the image distroless-compatible?
- **HA notes:** What does HA actually require for this component?
- **Known issues:** Any `deprecated_reason` or notes about limitations?

### 5. Environment Fit

Evaluate against the specific deployment environment:

- **Lima + k3s on Apple Silicon:** arm64, no cloud LoadBalancer, local-path
  StorageClass, no external DNS, Traefik ingress (k3s default) or none.
- **Resource budget:** 3 VMs at 30GB disk, limited RAM. Will this component
  fit alongside what's already running?
- **Network:** Can the component reach its dependencies? Does it need
  external network access after bootstrap?

## Writing the Brief

Write to `lathe/state/research/<chart-name>.md`:

```markdown
# Research Brief: <chart-name>

**Version:** <version being evaluated>
**Layer:** <layer number and name from layer model>
**Date:** <YYYY-MM-DD>
**Status:** READY | BLOCKED | NEEDS_HUMAN

## Architecture Support

- arm64: <yes/no/partial — with evidence>
- amd64: <yes/no>
- Multi-arch manifest: <yes/no — from manifest inspect>

## System Requirements

- CPU: <minimum>
- Memory: <minimum per component>
- Disk: <PVC requirements>
- Kernel features: <any special requirements>

## Dependencies

| Dependency | Layer | Status |
|-----------|-------|--------|
| <dep>     | <N>   | <installed/missing/n-a> |

## Images

| Image | Tag | arm64 | Registry |
|-------|-----|-------|----------|
| <image> | <tag> | <yes/no> | <source> |

## Configuration Required

- <key>: <what to set and why>
- <key>: <what to set and why>

## Known Limitations

- <limitation and impact on our environment>

## HA Model

<how HA works, what config is needed>

## VENDORS.yaml Status

- License: <SPDX> — <allowed/blocked>
- Deprecated: <yes/no>
- Version match: <yes/no — pinned vs installing>

## Risks

- <risk and mitigation>

## Recommendation

<INSTALL / INSTALL_WITH_CONFIG / BLOCKED / NEEDS_ALTERNATIVE>

<one paragraph explaining the recommendation>
```

## After Research

Once the brief is written:

1. If Status is **READY** — proceed to install in the normal cycle flow.
2. If Status is **BLOCKED** — document the blocker, do NOT attempt install.
   Move to the next chart or fix the blocker.
3. If Status is **NEEDS_HUMAN** — the brief contains a question only a human
   can answer (license ambiguity, architectural choice). Stop and surface it.

## When to Re-Research

- Major version bump (e.g., v1.x → v2.x) — full re-research
- Architecture change (e.g., new environment) — re-check sections 3 and 5
- Upstream license change — re-check section 4 immediately
- 3+ failed cycles on the same chart — re-research, something was missed

## Anti-Patterns

- **"I'll check after it fails"** — No. Research prevents failure.
- **"The VENDORS.yaml says it's fine"** — VENDORS.yaml is policy, not ops
  reality. It says the license is OK; it doesn't say the image has arm64.
- **"It worked on the last cluster"** — Different environment, different
  constraints. Research is per-environment.
- **Skipping image manifest check** — This is the #1 cause of wasted cycles.
  An image that doesn't exist for your arch will never work, no matter how
  many times you retry the install.
