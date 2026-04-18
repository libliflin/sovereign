# Ambition

## Destination

Sovereign is the self-hosted platform stack a developer can clone on a Friday, run `bootstrap.sh` on real VPS nodes, and have every service URL live — ArgoCD, Forgejo, Grafana, Keycloak, OpenBao, Harbor, Backstage, code-server — by Sunday evening, with no cloud account, no tribal knowledge, and no manual `kubectl` after bootstrap.

*Sources: README.md:1–3 "Clone, configure, run." · README.md:7–9 autarky definition · docs/governance/scope.md:1 "any developer can clone, configure, and run" · docs/state/architecture.md:11 "deployable by any developer from a single bootstrap.sh invocation" · CLAUDE.md T3 "under 30 minutes — with no cloud account required"*

The bar is not static analysis passing or charts rendering correctly. The bar is `./bootstrap/verify.sh` printing green on a real 3-node VPS cluster — every service reachable, SSO working, ArgoCD synced, a commit pushed to Forgejo showing up in ArgoCD within minutes.

---

## The Gap

**1. The end-to-end VPS bootstrap is unwalked.**
`bootstrap/config.yaml.example` was added only recently (commit `942b1d7`) and marked a "stub" in the commit message. The config fields are documented but the actual `bootstrap.sh` provisioning path on real Hetzner/DigitalOcean nodes has no verified walkthrough. `platform/deploy.sh` is confirmed as a scaffold (`RESTRUCTURE-001b-2 platform/deploy.sh scaffold` — docs/state/agent.md increment 34). The alignment-summary notes explicitly: "The self-hoster first encounter is untested end-to-end."

**2. The Backstage developer portal is incomplete behind SSO.**
E11 has 3 stories still pending: full Keycloak OIDC/plugin config (027a), and two others. Backstage's ArgoCD app exists and charts pass G6, but a self-hoster arriving at `https://backstage.<domain>` hits an unconfigured Keycloak OIDC integration. The portal — the place where the platform explains itself — is a shell. (docs/state/agent.md: "stories 027a full Keycloak OIDC/plugin config, 027b, 049 still pending")

**3. The AI Agent (code-server) toolchain isn't autarky-complete.**
DEVEX-015 (code-server pre-installs extensions from Harbor) is `passes: true` but `reviewed: false` with the install mechanism still unclear (alignment-summary.md). The AI Agent stakeholder's primary dead-end — `extension install tries marketplace.visualstudio.com and fails` — is not closed. An agent who can't install extensions from Harbor can't do real work without leaving the zero-trust perimeter.

**4. The HA gate still has failures across the chart corpus.**
The alignment-summary notes: "G9 was added in the constitution as a goal, not yet reached." cert-manager, cilium, trivy, and others are missing replicaCount or resource limits. `ha-gate.sh` extended its coverage to 25+ charts but check-limits.py violations still exist (docs/state/agent.md increment 40 added `check-limits.py` — implying prior charts haven't all been re-validated against it). The platform claims HA-mandatory but the gate it enforces is not yet uniformly green.

---

## What Winning Fixes Look Like

**The self-hoster path closes when `./bootstrap/verify.sh` passes on real nodes — not when individual scripts exist.**
Adding another scaffold, stub, or doc update to quickstart.md is not on-ambition. On-ambition is: `bootstrap.sh --confirm-charges` runs to completion on 3 Hetzner nodes, ArgoCD syncs, and every service URL in the README is reachable. Until that path is walka­ble end-to-end, every polish fix elsewhere is deferred ambition.

**The developer portal closes when a self-hoster can log into Backstage with their Keycloak credentials on first boot — no manual OIDC config required.**
An ArgoCD application that deploys a Backstage pod with unconfigured SSO is off-ambition. On-ambition is: Backstage's Keycloak OIDC config is injected at deploy time from the same `config.yaml` values the self-hoster already filled in.

**The code-server environment closes when an agent opens a terminal and has `kubectl`, `helm`, and a working VS Code extension set — from Harbor, not the internet.**
A `toolchainInit` initContainer that copies binaries is on-ambition. A post-start lifecycle hook that calls `marketplace.visualstudio.com` is off-ambition. Any extension install that requires an internet call breaks the zero-trust perimeter and breaks the AI Agent stakeholder's autonomy signal.

---

## Velocity Signal

The recent commit pattern shows the project is in late assembly: individual components exist and pass static gates, but the delivery focus is shifting toward closing the end-to-end self-hoster loop. Commits `942b1d7` (add bootstrap/config.yaml.example), `cb97c37` (surface service URLs in deploy.sh), `91d5626` (surface platform deploy step in kind quick start), and `7393d1a` (add CONTRIBUTING.md) all land in sequence — a cluster of "make the entry path visible" changes. The platform is not in MVP mode. It is in final-assembly mode: the parts exist, the wiring is being completed.
