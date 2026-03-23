# Sovereign Platform

**A fully self-hosted, zero-trust, high-availability Kubernetes development platform. Clone, configure, run.**

Get a complete production-grade development environment — GitLab, ArgoCD, Grafana, OpenBao,
Keycloak, Harbor, Backstage, and more — on any cluster of VPS or bare-metal servers.

> **Autarky** /ˈɔːtɑːki/ — *complete economic self-sufficiency*. No SaaS. No vendor lock-in.
> No external image pulls after bootstrap. Every dependency built from vetted, patched source.

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Sovereign Platform                            │
├─────────────────────────────────────────────────────────────────────┤
│  Developer Experience                                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │ GitLab   │ │Backstage │ │  VS Code │ │SonarQube │             │
│  │ (SCM/CI) │ │ (Portal) │ │(Browser) │ │ (Quality)│             │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘             │
├─────────────────────────────────────────────────────────────────────┤
│  Security & Service Mesh                                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │  Istio   │ │ OpenBao  │ │ Keycloak │ │  OPA/GK  │             │
│  │  (mTLS)  │ │(Secrets) │ │  (SSO)   │ │(Policies)│             │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘             │
├─────────────────────────────────────────────────────────────────────┤
│  Observability                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │Prometheus│ │ Grafana  │ │   Loki   │ │  Tempo   │             │
│  │(Metrics) │ │(Dashbds) │ │  (Logs)  │ │ (Traces) │             │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘             │
├─────────────────────────────────────────────────────────────────────┤
│  Autarky Build System                                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │  Harbor  │ │  Vendor  │ │  Patch   │ │  SAST/   │             │
│  │(Registry)│ │ Recipes  │ │ Tracking │ │   SCA    │             │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘             │
├─────────────────────────────────────────────────────────────────────┤
│  GitOps Engine                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │          ArgoCD (App-of-Apps — manages everything)           │  │
│  └──────────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│  Storage Layer                              Identity & Secrets      │
│  ┌──────────────────────────────────┐      ┌────────────────────┐  │
│  │  Rook/Ceph (block, fs, object)   │      │ Sealed Secrets     │  │
│  └──────────────────────────────────┘      └────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│  Cluster Foundations (HA — 3 nodes minimum)                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │  Cilium  │ │Crossplane│ │cert-mgr  │ │K3s + VIP │             │
│  │  (CNI)   │ │(Infra)   │ │  (TLS)   │ │(kube-vip)│             │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘             │
├─────────────────────────────────────────────────────────────────────┤
│  Front Door (zero open ports — all traffic via tunnel)              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Pluggable: Cloudflare Tunnel (default) │ Custom │ None      │  │
│  └──────────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│  Infrastructure                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Hetzner / DigitalOcean / Generic VPS / Bare Metal / ...     │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Core Principles

### High Availability — non-negotiable
**Minimum 3 nodes, always.** Two independent requirements enforce this:
- **etcd quorum**: 3 nodes tolerate 1 failure. 2 nodes lose quorum on any failure. 1 node is a SPOF.
- **Ceph quorum**: Rook/Ceph requires 3 OSDs to form a healthy storage cluster.

`bootstrap.sh` will refuse to proceed with fewer than 3 nodes or an even node count.
kube-vip provides a floating API server VIP across all control plane nodes — no external
load balancer required.

### Autarky — no external dependencies at runtime
After bootstrap, the cluster never pulls from docker.io, quay.io, ghcr.io, or gcr.io.
Every image is:
1. **Fetched** from upstream at a pinned git SHA (verified post-clone)
2. **Patched** with any security fixes from `vendor/recipes/<name>/patches/`
3. **Built** from source into a distroless OCI image
4. **Pushed** to the internal Harbor registry
5. **Deployed** by ArgoCD from Harbor

### Distroless — no shells in production
All container images use [distroless](https://github.com/GoogleContainerTools/distroless) base
images. No shell, no package manager, minimal attack surface. Any service that cannot run
distroless is marked deprecated in `vendor/VENDORS.yaml` with a migration path.

### Zero downtime rollouts
Every image change goes through: `build → staging → smoke test → promote → production`.
`vendor/rollback.sh <name>` always has a last-known-good SHA to revert to. Rollout strategy
is declared per-service in `recipe.yaml` (`rolling`, `node_by_node` for CNI, etc.).

### Zero open ports
The default front door is Cloudflare Tunnel + Zero Trust Access (free tier). The VPS firewall
drops everything except Cloudflare's published IP ranges. Port 22 is never open.
SSH goes through `cloudflare access ssh`. Swap in your own front door by implementing the
5-hook interface in `bootstrap/frontdoor/`.

---

## Prerequisites

### For local development and testing (kind — no cloud account needed)
- Docker Desktop (running)
- `brew install kind kubectl helm gh shellcheck`
- That's it. No cloud account, no domain, no credentials.

### For live production deployment (real VPS)
- A domain name you control, DNS managed by Cloudflare
- **3+ VPS nodes** running Ubuntu 22.04+ (odd number, minimum 3 — see [why](#high-availability--non-negotiable))
- A local machine with: `bash`, `ssh`, `kubectl`, `helm` v3+, provider CLI
- Cloud credentials: see `.env.example` for what each provider needs

---

## Quick Start

### Option A — Local testing with kind (start here)

```bash
# 1. Clone
git clone https://github.com/libliflin/sovereign
cd sovereign

# 2. Start Docker Desktop, then:
./kind/setup.sh              # creates sovereign-test cluster (~4 minutes)
./kind/setup.sh --status     # verify it's healthy

# 3. Smoke test a chart
helm install test-release charts/sealed-secrets/ \
  --namespace sealed-secrets --create-namespace \
  --kube-context kind-sovereign-test --wait
kubectl --context kind-sovereign-test get pods -n sealed-secrets

# 4. Tear down when done
./kind/setup.sh --destroy
```

See [kind/README.md](kind/README.md) for full kind documentation.

### Option B — Live provisioning on real VPS

```bash
# 1. Clone and configure
git clone https://github.com/libliflin/sovereign
cd sovereign
cp bootstrap/config.yaml.example bootstrap/config.yaml
# Edit: domain, provider, frontDoor, nodes.count (must be odd, >= 3)

# 2. Set credentials (Hetzner + Cloudflare minimum)
cp .env.example .env
# Edit .env with your tokens — see .env.example for where to get each one
source .env

# 3. Check estimated cost before spending anything
./bootstrap/bootstrap.sh --estimated-cost

# 4. Provision (requires --confirm-charges — this creates real servers)
./bootstrap/bootstrap.sh --confirm-charges

# 5. Verify
./bootstrap/verify.sh
```

See [docs/quickstart.md](docs/quickstart.md) for the full walkthrough.

---

## Provider Cost Comparison (3-node HA minimum)

This table reflects the **minimum viable HA cluster** (3 nodes). Single-node setups are not
supported — see [Core Principles](#high-availability--non-negotiable) for why.

| Provider | Node spec | Monthly cost | Notes |
|---|---|---|---|
| **Hetzner CX22** | 2 vCPU / 4 GB | **~$15/mo** | Bare minimum. Tight but functional. |
| **Hetzner CX32** ⭐ | 4 vCPU / 8 GB | **~$25/mo** | Recommended. Comfortable for full stack. |
| DigitalOcean Basic | 2 vCPU / 4 GB | ~$18/mo | Solid. Good EU/US coverage. |
| Vultr | 2 vCPU / 4 GB | ~$18/mo | Good global edge locations. |
| AWS t3.medium | 2 vCPU / 4 GB | ~$90/mo | Reliable but expensive for HA. |
| AWS t3.small | 2 vCPU / 2 GB | ~$45/mo | Minimum viable on AWS. Tight. |
| Bare metal (owned) | Your hardware | $0/mo | Best value long-term. |

> **AWS free tier is not viable.** t2.micro/t3.micro (1 GB RAM) cannot run a k3s server
> node with embedded etcd. Minimum AWS instance for this stack is t3.small.

> **Community note:** These costs are best-effort estimates as of early 2026. Prices change.
> Provider performance varies by region. See [Contributing Providers](#contributing-providers)
> to add or correct entries.

---

## Contributing Providers

Know a provider that belongs in this table? Have real-world numbers that differ from the
estimates above? PRs welcome.

To add or update a provider entry:

1. Add or update `docs/providers/<provider>.md` following the existing template
   (see [docs/providers/hetzner.md](docs/providers/hetzner.md) for reference)
2. Add or update `bootstrap/providers/<provider>.sh` implementing the provisioning interface
   (see [bootstrap/providers/hetzner.sh](bootstrap/providers/hetzner.sh) for reference)
3. Update the table above in this README
4. Submit a PR — CI will validate the shell script with `shellcheck`

**Provider script interface** (what your script must do):
- Read `bootstrap/config.yaml` (domain, node count, node spec, SSH key)
- Provision `nodes.count` servers at the requested spec
- Output `~/.kube/config` pointing at the kube-vip VIP
- Print estimated monthly cost
- Print Cloudflare wildcard DNS setup instructions (`*.domain → VIP`)

See `bootstrap/providers/hetzner.sh` for a complete reference implementation.

Providers people have asked about (PRs welcome):
- [ ] Vultr
- [ ] Linode / Akamai Cloud
- [ ] OVHcloud
- [ ] Oracle Cloud (free tier — 4 OCPU / 24 GB ARM, actually viable!)
- [ ] Scaleway
- [ ] Fly.io Machines
- [ ] Proxmox (bare metal hypervisor)
- [ ] Raspberry Pi cluster

---

## Service URLs

Once deployed, services are at:

| Service | URL | Notes |
|---|---|---|
| ArgoCD | `https://argocd.<domain>` | GitOps dashboard |
| GitLab | `https://gitlab.<domain>` | SCM + CI + vendor mirrors |
| Grafana | `https://grafana.<domain>` | Metrics + logs + traces |
| Keycloak | `https://auth.<domain>` | SSO for all services |
| OpenBao | `https://vault.<domain>` | Secrets (Apache 2.0 Vault fork) |
| Harbor | `https://harbor.<domain>` | Internal image registry |
| Backstage | `https://backstage.<domain>` | Developer portal |
| VS Code | `https://code.<domain>` | Browser IDE for agents |
| Sovereign PM | `https://pm.<domain>` | AI-native project management |

---

## Architecture

Sovereign uses the **ArgoCD App-of-Apps** pattern. After the initial bootstrap:
1. ArgoCD is installed and watches this repo
2. The root app (`argocd-apps/root-app.yaml`) deploys all service apps
3. Every service is self-healing and GitOps-managed

No manual `kubectl apply` after bootstrap. All changes go through Git.

**Build pipeline** (`vendor/`):
1. `vendor/fetch.sh` — SHA-verified mirror of upstream source into internal GitLab
2. `vendor/build.sh` — builds distroless OCI images from patched source
3. `vendor/deploy.sh` — stages, smoke tests, promotes to production
4. `vendor/rollback.sh` — reverts to last-known-good image SHA
5. `vendor/backup.sh` — mirrors repos + images to secondary storage (runs as CronJob)

**Security scanning** runs continuously against all mirrored source in GitLab CI:
SAST (Semgrep), SCA (Trivy), license audit, secret detection.
CVE findings create GitLab issues. Patches land in `vendor/recipes/<name>/patches/`.

---

## Documentation

- [Quickstart Guide](docs/quickstart.md)
- [Architecture](docs/architecture.md)
- [Day-2 Operations](docs/day-2-operations.md)
- **Providers**: [Hetzner](docs/providers/hetzner.md) · [AWS EC2](docs/providers/aws-ec2-free-tier.md) · [DigitalOcean](docs/providers/digitalocean.md)
- **Security**: [Front Door Setup](docs/providers/cloudflare-setup.md) · [Custom Front Door](docs/providers/front-door-custom.md)

---

## Contributing

1. Fork the repo
2. Create a feature branch
3. All charts must pass `helm lint` and `helm template | kubectl apply --dry-run=client`
4. All shell scripts must pass `shellcheck`
5. HA requirements: every chart must have `replicaCount`, `podDisruptionBudget`, and `podAntiAffinity`
6. Submit a PR — CI validates everything automatically

See [CONTRIBUTING.md](CONTRIBUTING.md) for full guidelines.

## License

MIT — see [LICENSE](LICENSE)
