# Sovereign Platform

**A fully self-hosted, zero-trust Kubernetes development platform. Clone, configure, run.**

Get a complete production-grade development environment — GitLab, ArgoCD, Grafana, Vault,
Keycloak, Harbor, Backstage, and more — on any VPS or bare-metal server in under 15 minutes.

## What is Sovereign?

Sovereign is an opinionated, batteries-included Kubernetes platform stack that any developer
can own entirely. No SaaS dependencies. No vendor lock-in. Everything runs on your infrastructure,
secured by zero-trust principles.

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
│  │  Istio   │ │  Vault   │ │ Keycloak │ │  OPA/GK  │             │
│  │  (mTLS)  │ │(Secrets) │ │  (SSO)   │ │(Policies)│             │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘             │
├─────────────────────────────────────────────────────────────────────┤
│  Observability                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │Prometheus│ │ Grafana  │ │   Loki   │ │  Tempo   │             │
│  │(Metrics) │ │(Dashbds) │ │  (Logs)  │ │ (Traces) │             │
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
│  Cluster Foundations                                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐             │
│  │  Cilium  │ │Crossplane│ │cert-mgr  │ │   K3s    │             │
│  │  (CNI)   │ │(Infra)   │ │  (TLS)   │ │(Cluster) │             │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘             │
├─────────────────────────────────────────────────────────────────────┤
│  Infrastructure                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Hetzner / AWS EC2 / DigitalOcean / Generic VPS / Bare Metal │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- A domain name you control (e.g., `example.com`)
- A VPS or bare-metal server with Ubuntu 22.04+ (or a supported cloud account)
- A local machine with:
  - `bash` and `ssh`
  - `kubectl` ([install](https://kubernetes.io/docs/tasks/tools/))
  - `helm` v3+ ([install](https://helm.sh/docs/intro/install/))
  - One of: `hcloud` CLI, `aws` CLI, `doctl` CLI (depends on your provider)
- DNS access to create a wildcard record: `*.your-domain.com → server IP`

## Quick Start (15 minutes)

```bash
# 1. Clone the repo
git clone https://github.com/libliflin/sovereign
cd sovereign

# 2. Configure
cp bootstrap/config.yaml.example bootstrap/config.yaml
# Edit bootstrap/config.yaml with your domain, provider, and credentials

# 3. Bootstrap
./bootstrap/bootstrap.sh

# 4. Verify
./bootstrap/verify.sh
```

See [docs/quickstart.md](docs/quickstart.md) for the full walkthrough.

## Provider Guides

| Provider | Cost | Guide |
|---|---|---|
| Hetzner Cloud | ~€4/mo | [docs/providers/hetzner.md](docs/providers/hetzner.md) |
| AWS EC2 (free tier) | $0-15/mo | [docs/providers/aws-ec2-free-tier.md](docs/providers/aws-ec2-free-tier.md) |
| DigitalOcean | ~$6/mo | [docs/providers/digitalocean.md](docs/providers/digitalocean.md) |
| Vultr | ~$6/mo | [docs/providers/vultr.md](docs/providers/vultr.md) |
| Bare metal / existing cluster | Free | [docs/providers/bare-metal.md](docs/providers/bare-metal.md) |

## Service URLs

Once deployed, your services are available at:

| Service | URL |
|---|---|
| ArgoCD | `https://argocd.<your-domain>` |
| GitLab | `https://gitlab.<your-domain>` |
| Grafana | `https://grafana.<your-domain>` |
| Keycloak | `https://auth.<your-domain>` |
| Vault | `https://vault.<your-domain>` |
| Harbor | `https://harbor.<your-domain>` |
| Backstage | `https://backstage.<your-domain>` |
| VS Code | `https://code.<your-domain>` |
| Sovereign PM | `https://pm.<your-domain>` |

## Documentation

- [Quickstart Guide](docs/quickstart.md)
- [Architecture](docs/architecture.md)
- [Day-2 Operations](docs/day-2-operations.md)

## Architecture

Sovereign uses the **ArgoCD App-of-Apps** pattern. After the initial bootstrap:
1. ArgoCD is installed and configured to watch this repo
2. ArgoCD reads `argocd-apps/root-app.yaml`
3. The root app deploys all service apps from `argocd-apps/`
4. Every service is self-healing and GitOps-managed

No manual `kubectl apply` after bootstrap. All changes go through Git.

## Use as a Helm Repository

```bash
helm repo add sovereign https://libliflin.github.io/sovereign
helm repo update
helm search repo sovereign
```

## Contributing

1. Fork the repo
2. Create a feature branch
3. Make changes (all charts must pass `helm lint`)
4. Submit a PR — CI validates all charts automatically

## License

MIT — see [LICENSE](LICENSE)
