# Sovereign Platform — Claude Code Agent Instructions

You are an autonomous coding agent building the **Sovereign Platform**: a fully self-hosted,
zero-trust Kubernetes infrastructure stack that any developer can clone, configure with their
domain and VPS credentials, and run to get a complete production-grade development platform.

The repo is: https://github.com/libliflin/sovereign
The dogfood domain is: sovereign-autarky.dev
Architecture: ArgoCD App-of-Apps pattern, Helm charts, Crossplane for infrastructure composition.

---

## BEFORE EVERY ITERATION

1. Read `prd/manifest.json` → find `activeSprint` field → read that file (e.g. `prd/phase-0-ceremonies.json`)
   - If `prd/manifest.json` does not exist yet, fall back to reading `prd.json` at repo root
   - The active sprint file contains only the stories for the current phase (~8 stories max)
2. Find the highest-priority story where `"passes": false` AND `"reviewed": false`
   - `passes: true` but `reviewed: false` means Ralph marked it done but the review ceremony has not run yet — do NOT re-implement it, leave it for the review ceremony
3. Read `progress.txt` — study ALL prior learnings, especially the "Codebase Patterns" section
4. Check which git branch the current story requires (`branchName` in the sprint file)
5. Check out that branch (or create from main if it doesn't exist)
6. Read any `CLAUDE.md` files in subdirectories relevant to your story

## THE SPRINT CYCLE (how phases work)

The project is split into phases. Each phase is a sprint with ~8 stories and ~15 story points.
Phases are managed by the ceremony system in `scripts/ralph/ceremonies/`.

```
prd/manifest.json          ← source of truth: which phase is active
prd/phase-N-<name>.json    ← active sprint: only stories for this phase
prd/backlog.json           ← full backlog: all future stories
prd/advance.sh             ← marks phase complete, activates next phase
```

**Story lifecycle:**
```
passes: false, reviewed: false  → needs implementation (Ralph's job)
passes: true,  reviewed: false  → implemented, awaiting review ceremony
passes: true,  reviewed: true   → accepted (done)
passes: false, reviewed: false, attempts > 0  → re-opened by review ceremony with reviewNotes
```

When re-opened, read `reviewNotes[]` carefully — they contain the exact failure from the review
ceremony. Fix only what the reviewNotes describe. Do not re-implement the whole story.

**Story points:**
1 = trivial (config file, small script change)
2 = standard (single Helm chart, medium script)
3 = complex (multi-file feature, chart with dependencies)
5 = must split before implementing

When you complete a story, mark `passes: true`. Do NOT mark `reviewed: true` — that is set
by the review ceremony only.

---

## THE STACK YOU ARE BUILDING

### Architecture Philosophy
- **ArgoCD App-of-Apps** is the GitOps engine. Everything after bootstrap is an ArgoCD Application.
- **Crossplane** manages infrastructure compositions (cloud resources, namespaces, RBAC)
- **Domain is a variable** — never hardcode a domain. Always use `{{ .Values.global.domain }}` in Helm
- **Bootstrapping** is the only manual step. After that, GitOps manages everything.
- **Namespaces are sovereign** — each service lives in its own namespace with network policies

### High Availability — MANDATORY at every layer
**bootstrap.sh MUST refuse to proceed with fewer than 3 nodes or an even node count.**
HA is not optional and is not a "phase 2" concern. It is baked in from the first commit.

```
Node layer:      3+ nodes (odd). etcd quorum + Ceph quorum both require this.
API server:      kube-vip floating VIP across all control plane nodes.
CNI:             Cilium DaemonSet — inherently HA.
Front door:      cloudflared DaemonSet on ALL nodes, not a single systemd unit.
Storage:         Rook/Ceph replication factor 3.
Applications:    replicaCount >= 2 on every Helm chart (3 for critical services).
Rollout:         maxUnavailable: 0, maxSurge: 1. Never take a service to zero replicas.
```

**Every Helm chart MUST include:**
- `replicaCount: 2` minimum (configurable, but default must be >= 2)
- `podDisruptionBudget: { minAvailable: 1 }` — prevents both replicas going down during drain
- `podAntiAffinity` — replicas must land on different nodes (preferredDuringScheduling minimum,
  requiredDuring for critical services like etcd, ArgoCD, Keycloak)
- `readinessProbe` and `livenessProbe` on every container
- `resources.requests` and `resources.limits` on every container

**Every bootstrap provider script MUST:**
- Accept `nodes.count` from config.yaml (validate: odd number, >= 3, abort otherwise)
- Provision all N nodes before proceeding
- Install kube-vip on control plane nodes for API server VIP
- Install K3s with `--cluster-init` on node 1, `--server https://<VIP>:6443` on nodes 2+
- Verify ALL nodes are Ready before returning kubeconfig

### Backup Strategy — MANDATORY
The git repo is the nuclear recovery path. Everything else makes recovery fast, not possible.

**Recovery path (worst case — all servers lost):**
1. Clone sovereign repo (backed up to at least one secondary remote)
2. `vendor/fetch.sh --all` — recreates all GitLab mirrors from upstream at pinned SHAs
3. `vendor/build.sh --all` — rebuilds all images from patched source
4. Bootstrap a new cluster from scratch
5. ArgoCD restores all services from git state

**Operational backup (day-to-day):**
- `vendor/backup.sh` runs as a Kubernetes CronJob (daily, HA by default)
- Mirrors all `gitlab.<domain>/vendor/*` repos to a secondary remote (S3 bare repo or secondary git)
- `crane copy` all `harbor.<domain>/sovereign/*` images to a backup registry
- Writes `backup-manifest.json` with {name, source_sha, image_digest, timestamp} for every artifact
- Exits non-zero on any failure so alerting triggers

**Every vendor script MUST support:**
- `--dry-run` — print actions without executing
- `--backup` — push to secondary remote/registry after primary operation
- Tagging current state before overwriting: `git tag sovereign/pre-update-<timestamp>`

### Zero Downtime Rollout — MANDATORY
No image is ever pushed directly to production. Every change goes through staging first.

```
build.sh  →  harbor.../sovereign-staging/<name>:<tag>
                ↓
deploy.sh →  apply to staging namespace
                ↓  (kubectl rollout status --timeout=5m)
             smoke-test.sh (vendor/recipes/<name>/smoke-test.sh)
                ↓  (must exit 0)
             record last-known-good SHA in ConfigMap sovereign-vendor/lkg-<name>
                ↓
             promote to production ArgoCD Application
                ↓  (kubectl rollout status --timeout=10m)
             if production rollout fails → auto-rollback via rollback.sh
```

**Image tag format:** `<upstream-version>-<source-sha>-p<patch-count>` e.g. `v1.16.0-a3f8c2d-p3`
Never `:latest`. Never just `:<version>`. The patch count makes vendor divergence visible.

**Every recipe.yaml MUST declare:**
```yaml
rollout:
  strategy: rolling        # rolling | node_by_node (CNI only) | skip (bootstrap tools)
  max_unavailable: 0
  max_surge: 1
  staging_timeout: 5m
  production_timeout: 10m
backup:
  priority: critical       # critical | standard | derived (can be rebuilt, skip backup)
```

**rollback.sh** reads `sovereign-vendor/lkg-<name>` ConfigMap and repins that image digest.
Always know the last-known-good. Rollback must complete in under 2 minutes.

### Autarky Build Philosophy (CRITICAL)
The platform must be **genuinely self-sufficient at runtime**. After bootstrap completes, the cluster
must never pull images from external registries (docker.io, quay.io, ghcr.io, gcr.io, etc.).

**Vendor everything. Build everything. Own everything.**

#### The Vendor System (Gentoo-inspired)
- Every upstream dependency has a **recipe** in `vendor/recipes/<name>/recipe.yaml`
- Recipes declare: upstream URL, pinned version, SPDX license, fetch method, distroless base, build tool
- `vendor/fetch.sh` mirrors upstream source into the internal GitLab at `gitlab.<domain>/vendor/<name>`
- `vendor/build.sh` builds OCI images via Bazel and pushes to `harbor.<domain>/sovereign/<name>:<version>`
- `vendor/update-check.sh` checks for upstream releases and opens GitLab issues
- **No git submodules.** No external dependencies at runtime. The internal GitLab is the source of truth.

#### Distroless Standard (MANDATORY)
- **All container images MUST use distroless base images.** No exceptions without an approved deprecation.
- Go binaries → `gcr.io/distroless/static` (fetched during bootstrap, cached in Harbor after)
- JVM services → `gcr.io/distroless/java21`
- Node.js services → `gcr.io/distroless/nodejs`
- Any service that cannot run distroless MUST have a `deprecated: true` entry in `vendor/VENDORS.yaml`
  with a `deprecated_reason` and an `alternative` pointing to a distroless-compatible replacement.
- When writing new code (Sovereign PM, custom operators, etc.) — **use Rust or Go**, build distroless.

#### License Policy
- Apache 2.0, MIT, BSD, LGPL → approved for vendoring
- **BSL (HashiCorp products) → BLOCKED.** Use OpenBao instead of Vault.
- AGPL → review required before adding
- SSPL → blocked
- Run `vendor/audit.sh` before marking any vendor story as passing. It must exit 0.

#### Image Registry Policy
- All Helm charts MUST use `{{ .Values.global.imageRegistry }}/` as the image repository prefix
- `global.imageRegistry` defaults to `harbor.<domain>/sovereign` (set in `charts/_globals/values.yaml`)
- During bootstrap (before Harbor is up), set `global.imageRegistry: ""` to use upstream registries temporarily
- ArgoCD Image Updater watches Harbor and auto-syncs when new images are pushed

### Bootstrap Sequence (strict ordering — dependencies must come first)
```
PHASE 0 — Cluster Provisioning (scripts, not Helm)
  └─ Hetzner Cloud API scripts (primary)
  └─ Generic VPS scripts (Vultr, DigitalOcean, Linode)
  └─ AWS EC2 scripts (free tier compatible)
  └─ Bare metal / existing cluster onboarding

PHASE 1 — Cluster Foundations (bootstrap script installs these directly)
  └─ Cilium (CNI + network policies)
  └─ Crossplane core + Helm provider + Kubernetes provider
  └─ cert-manager (self-signed initially)
  └─ Sealed Secrets controller (for GitOps-safe secret storage)

PHASE 2 — Identity & Secrets (Crossplane deploys these)
  └─ Vault (dev mode → production HA after Ceph is ready)
  └─ Keycloak (embedded DB → PostgreSQL after DB operator ready)

PHASE 3 — Storage (enables everything stateful)
  └─ Rook/Ceph operator
  └─ CephCluster (encrypted, distributed)
  └─ StorageClasses (block, filesystem, object)

PHASE 4 — GitOps Engine (becomes self-managing from here)
  └─ GitLab (self-hosted, migrates to Ceph storage)
  └─ Harbor (artifact registry, uses Ceph object storage)
  └─ ArgoCD (App-of-Apps, takes over managing all above)
  └─ GitLab CI Runners

PHASE 5 — Service Mesh & Security
  └─ Istio (mTLS everywhere)
  └─ OPA/Gatekeeper (policy enforcement)
  └─ Trivy Operator (vulnerability scanning)
  └─ OWASP ZAP (web security scanning)
  └─ Falco (runtime security)

PHASE 6 — Observability
  └─ Prometheus + Alertmanager
  └─ Grafana + dashboards
  └─ Loki (log aggregation)
  └─ Thanos (long-term Prometheus storage)
  └─ Tempo (distributed tracing)

PHASE 7 — Developer Experience
  └─ Backstage (developer portal + service catalog)
  └─ code-server (VS Code in browser — primary interface for Claude Code agents)
  └─ SonarQube (code quality history)
  └─ ReportPortal (test result history)

PHASE 8 — Testing Infrastructure
  └─ Selenium Grid (persistent browser testing)
  └─ k6 Operator (load testing)
  └─ Wiremock (API mocking)
  └─ MailHog (email testing)
  └─ Chaos Mesh (resilience testing)

PHASE 9 — AI-Native Project Management
  └─ Sovereign PM (custom lightweight web app)
      - Create epics and user stories through a web UI
      - Generates prd.json compatible with Ralph
      - Tracks agent run history and pass/fail per story
      - Keycloak SSO integration
      - Deployed as a Kubernetes service in `sovereign-pm` namespace
```

---

## REPO STRUCTURE YOU ARE BUILDING

```
sovereign/
├── CLAUDE.md                    ← this file
├── README.md                    ← human-readable setup guide
├── prd.json                     ← Ralph task queue
├── progress.txt                 ← Ralph learnings log
│
├── bootstrap/                   ← Phase 0-1: manual/scripted setup
│   ├── providers/
│   │   ├── hetzner.sh           ← Hetzner Cloud provisioning
│   │   ├── generic-vps.sh       ← Generic VPS (Ubuntu 22.04+)
│   │   ├── aws-ec2.sh           ← AWS free tier compatible
│   │   └── existing-cluster.sh ← Onboard existing K8s cluster
│   ├── frontdoor/               ← Pluggable security front door (tunnel/firewall)
│   │   ├── interface.sh         ← 5-hook contract all providers must implement
│   │   ├── cloudflare.sh        ← Cloudflare Tunnel + Zero Trust (default)
│   │   ├── none.sh              ← Baseline (prompt for caller IP, UFW only)
│   │   └── custom.sh.example   ← Template for custom implementations
│   ├── hardening/               ← Always-on VPS hardening (runs before front door)
│   │   ├── base.sh              ← unattended-upgrades, fail2ban, auditd
│   │   ├── ssh.sh               ← pubkey-only, no root password login
│   │   ├── kernel.sh            ← CIS benchmark sysctl settings
│   │   └── firewall.sh          ← UFW default-deny + front door CIDRs
│   ├── bootstrap.sh             ← Main entry point
│   ├── config.yaml.example      ← User fills this in (domain, provider, creds)
│   └── verify.sh                ← Post-bootstrap health check
│
├── vendor/                      ← Autarky build system (Gentoo-inspired)
│   ├── VENDORS.yaml             ← Manifest: every upstream with license + distroless status
│   ├── DISTROLESS.md            ← Compatibility matrix: which services use which base
│   ├── audit.sh                 ← License + distroless audit (must exit 0 before passing)
│   ├── fetch.sh                 ← Mirror upstream repos into internal GitLab
│   ├── build.sh                 ← Bazel build all recipes → push to Harbor
│   ├── update-check.sh          ← Check for new upstream releases
│   ├── pin.sh                   ← Pin a service to a specific version
│   ├── verify-distroless.sh     ← Confirm built images have no shell
│   ├── gitlab-ci-template.yml   ← CI template included by all mirrored repos
│   └── recipes/                 ← One recipe per vendored service
│       ├── cilium/
│       │   ├── recipe.yaml      ← upstream, version, license, fetch_method, distroless_base
│       │   └── BUILD.bazel      ← Bazel build + distroless OCI image target
│       ├── cert-manager/
│       ├── crossplane/
│       ├── argocd/
│       └── ...                  ← One per service in VENDORS.yaml
│
├── platform/                    ← Crossplane XRDs and Compositions
│   ├── xrds/
│   └── compositions/
│
├── charts/                      ← Helm charts (one per service)
│   ├── _globals/                ← Shared values and helpers
│   ├── cilium/
│   ├── crossplane/
│   ├── cert-manager/
│   ├── sealed-secrets/
│   ├── openbao/                 ← OpenBao (Apache 2.0 fork of Vault — BSL blocked)
│   ├── keycloak/
│   ├── rook-ceph/
│   ├── gitlab/
│   ├── harbor/
│   ├── argocd/
│   ├── istio/
│   ├── opa-gatekeeper/
│   ├── prometheus-stack/
│   ├── loki/
│   ├── thanos/
│   ├── tempo/
│   ├── backstage/
│   ├── code-server/
│   ├── sonarqube/
│   ├── reportportal/
│   ├── selenium-grid/
│   ├── k6-operator/
│   ├── wiremock/
│   ├── mailhog/
│   ├── chaos-mesh/
│   ├── trivy-operator/
│   ├── falco/
│   └── sovereign-pm/            ← Custom AI-native PM tool
│
├── argocd-apps/                 ← ArgoCD Application manifests (App-of-Apps)
│   ├── root-app.yaml            ← The root ArgoCD app that manages all others
│   ├── platform/
│   ├── security/
│   ├── observability/
│   ├── devex/
│   └── testing/
│
├── docs/                        ← Setup documentation
│   ├── quickstart.md
│   ├── providers/
│   │   ├── hetzner.md
│   │   ├── aws-ec2-free-tier.md
│   │   ├── digitalocean.md
│   │   ├── vultr.md
│   │   └── bare-metal.md
│   ├── architecture.md
│   └── day-2-operations.md
│
└── sovereign-pm/                ← Source code for the AI-native PM web app
    ├── src/
    ├── Dockerfile
    └── helm/                    ← Also mirrored in charts/sovereign-pm/
```

---

## HELM CHART STANDARDS

Every chart MUST follow these conventions:

```yaml
# charts/<name>/values.yaml — always include:
global:
  domain: "sovereign-autarky.dev"   # overridden by parent values
  storageClass: "ceph-block"
  keycloak:
    url: "https://auth.{{ .Values.global.domain }}"
    realm: "sovereign"

# All ingress hostnames must be:
#   <service>.{{ .Values.global.domain }}
# Examples:
#   gitlab.sovereign-autarky.dev
#   argocd.sovereign-autarky.dev
#   grafana.sovereign-autarky.dev
```

**Never hardcode:**
- Domain names
- IP addresses
- Passwords or secrets (use Vault references or Sealed Secrets)
- Storage class names (use `{{ .Values.global.storageClass }}`)

---

## ARGOCD APP-OF-APPS PATTERN

The root ArgoCD application (`argocd-apps/root-app.yaml`) watches the `argocd-apps/` directory.
Each subdirectory contains Application manifests for a tier of the stack.
ArgoCD auto-syncs all of them.

When you add a new service:
1. Create `charts/<service>/` with Chart.yaml, values.yaml, templates/
2. Create `argocd-apps/<tier>/<service>-app.yaml`
3. ArgoCD picks it up automatically

---

## SOVEREIGN PM — AI-NATIVE PROJECT MANAGEMENT

This is a custom web application (Node.js + React, simple and deployable) that:
- Provides a web UI for creating Epics and User Stories
- Each story has: title, description, acceptance criteria, priority, phase
- Has a "Generate PRD" button that outputs a valid `prd.json` for Ralph consumption
- Tracks agent run history (which Ralph iteration ran which story, pass/fail, logs)
- Has a "Run Ralph" button that triggers the ralph.sh loop via a Kubernetes Job
- Secured by Keycloak SSO (OIDC)
- Stores data in PostgreSQL (managed by Crossplane)

The `prd.json` schema it generates:
```json
{
  "branchName": "feature/story-slug",
  "stories": [
    {
      "id": "story-001",
      "title": "Human readable title",
      "description": "What to build",
      "acceptanceCriteria": ["criterion 1", "criterion 2"],
      "phase": 1,
      "priority": 1,
      "passes": false
    }
  ]
}
```

---

## VPS PROVIDER DOCUMENTATION REQUIREMENTS

Every provider script (`bootstrap/providers/*.sh`) must:
1. Accept `config.yaml` as input (domain, SSH key, `nodes.count`, `nodes.serverType`)
2. **Validate `nodes.count` is odd and >= 3 — abort with clear error if not**
3. Provision all N nodes (loop, not single-server)
4. Install kube-vip on control plane nodes for a floating API server VIP
5. Install K3s with `--cluster-init` + embedded etcd on node 1; join nodes 2+ via the VIP
6. Verify ALL nodes are `Ready` before outputting kubeconfig
7. Output a valid `kubeconfig` pointing at the kube-vip VIP (not a single node IP)
8. Print estimated **3-node monthly cost** (single-node cost is not shown — it is not supported)
9. Print Cloudflare wildcard DNS setup instructions (`*.domain.com → kube-vip VIP`)

Provider docs (`docs/providers/*.md`) must include:
- Estimated cost for **3-node HA cluster** (minimum) and **recommended spec**
- Note if the provider's free tier is viable (most aren't — be honest)
- Prerequisites (CLI tools, accounts needed)
- Step-by-step with copy-pasteable commands
- How to add nodes later (scale out)
- How to replace a failed node without downtime

---

## PROOF OF WORK — MANDATORY BEFORE passes:true

**Every completed story MUST do all of the following before setting `passes: true`.**
There are no exceptions. "It should work" is not proof. Showing output is proof.

### 1. Commit and push to remote
```bash
git add <specific files>          # never git add -A blindly
git commit -m "story-NNN: <description>"
git push origin <branchName>      # NON-NEGOTIABLE — if push fails, fix it
```

If `git push` fails for any reason, DO NOT mark the story done. Fix the push problem.

### 2. Create or verify a PR exists
```bash
gh pr create --title "story-NNN: <title>" --base main --head <branchName>
# or if PR already exists:
gh pr view --head <branchName>
```

If `gh` is not authenticated, note it as a blocker but still push the branch.

### 3. Show actual command output
Every quality gate run MUST be shown verbatim in your response:
```
$ helm lint charts/cert-manager/
==> Linting charts/cert-manager/
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
exit code: 0
```

Do NOT write "helm lint passes ✓" without showing the actual output.
Do NOT write "I ran shellcheck and it passed" — show the command and output.

### 4. The response must contain a Proof of Work block
End every story completion response with:
```
## Proof of Work — story-NNN

git push:  pushed to origin/<branchName> ✓
PR:        https://github.com/libliflin/sovereign/pull/<N>
helm lint: exit 0 (output above)
shellcheck: exit 0 (output above)
HA gate:   PDB ✓ | anti-affinity ✓ | replicaCount=2 ✓
```

---

## BLOCKER PROTOCOL

When you cannot complete or test a story due to a missing prerequisite, **do not fake it**.

Missing prerequisites include:
- Cloud provider API tokens (HETZNER_TOKEN, CLOUDFLARE_API_TOKEN, DO_TOKEN, AWS keys)
- A running Kubernetes cluster
- An external service that must be live
- A tool that is not installed

**What to do instead:**
1. Implement the code as completely as possible — write everything that can be written
2. Add a `blocker` field to the story in the sprint JSON:
```json
"blocker": {
  "type": "missing_credential",
  "name": "HETZNER_TOKEN",
  "description": "Cannot live-test node provisioning without a Hetzner Cloud account. Code is complete and dry-tested. Set HETZNER_TOKEN and re-run the smoke-test ceremony to verify."
}
```
3. Set `passes: false` — a story with an honest blocker is NOT a failure, it is parked
4. Push what you have anyway (`git push` is still required — partial work on remote beats nothing)
5. In your response, clearly state: `BLOCKER: <specific thing missing>`

**A story with a clear blocker and pushed code is better than a story marked passes:true
that was never actually tested.** The next engineer (or the next sprint after credentials
are obtained) can pick it up immediately.

### Things that are NOT valid blockers
- "I can't run kubectl because there's no cluster" → `kubectl apply --dry-run=client -f -`
  works without a cluster for manifest validation. Use it.
- "I can't test helm install" → `helm template` + `helm lint` works without a cluster. Use it.
- "shellcheck isn't installed" → `brew install shellcheck`. It takes 10 seconds.

---

## NEVER SELF-CERTIFY

You are not allowed to mark a criterion verified if you did not actually run a command that
proves it. The following are **prohibited**:

❌ "The helm chart should pass lint" → must run `helm lint` and show output
❌ "This follows the HA pattern" → must run `helm template | grep PodDisruptionBudget`
❌ "The script will work correctly" → must run with `--dry-run` and show output
❌ "I verified all acceptance criteria" → must show each one with actual command + output
❌ "The PR/CI will confirm this" → CI is not a substitute for running checks locally first

If you cannot verify a criterion because a tool is unavailable:
- State it explicitly: `UNVERIFIABLE: helm not installed`
- Add it to `reviewNotes` in the sprint file
- Do NOT write ✓ next to it
- Do NOT mark the story `passes: true` if critical criteria are unverifiable

The review ceremony will catch self-certification. Stories re-opened by review with
`reviewNotes` about unverified criteria count as wasted iterations against the sprint budget.

---

## QUALITY GATES

Before marking any story `passes: true`, you MUST:
1. `helm lint charts/<name>/` — no errors
2. `helm template charts/<name>/ | kubectl apply --dry-run=client -f -` — no errors
3. For bootstrap scripts: `shellcheck bootstrap/**/*.sh` — no errors
4. For vendor scripts: `shellcheck vendor/*.sh` — no errors
5. For any JS/TS code: `npm run typecheck && npm run lint` — clean
6. For ArgoCD apps: validate YAML with `kubectl apply --dry-run=client`

**HA gate — every Helm chart story MUST also verify:**
7. `helm template` output contains a `PodDisruptionBudget` resource
8. `helm template` output contains `podAntiAffinity` in the Deployment/StatefulSet
9. Default `replicaCount` in values.yaml is >= 2
10. Every container spec has `readinessProbe`, `livenessProbe`, `resources.requests`, `resources.limits`

**Vendor/build gate — every vendor story MUST also verify:**
11. `vendor/audit.sh` exits 0 (no license violations, no missing alternatives)
12. All new recipe.yaml files have `rollout` and `backup` sections
13. All new vendor/*.sh scripts support `--dry-run` flag

---

## RATE LIMIT / TOKEN AWARENESS

This project uses Ralph on a Claude Pro subscription. The loop will pause when daily token
limits are hit and resume the next day. Design each story to be completable in ~2000 tokens
of output. If a task is getting complex, split it into sub-stories before starting.

The loop command to run this project:
```bash
./scripts/ralph/ralph.sh --tool claude 10
```

To resume after a token limit pause, just re-run the same command. Ralph reads `prd.json`
and continues from the first story where `passes: false`.

---

## LEARNINGS FROM PRIOR SESSIONS

(This section is updated by Ralph after each iteration. Check progress.txt for details.)
