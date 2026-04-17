# Research Brief: cert-manager

**Version:** v1.14.0
**Layer:** 1 — PKI + Secrets
**Date:** 2026-04-03
**Status:** READY

## Architecture Support

- arm64: **yes** — verified via `crane manifest quay.io/jetstack/cert-manager-controller:v1.14.0`
  which returns: linux/amd64, linux/arm, linux/arm64, linux/ppc64le, linux/s390x.
- amd64: yes
- Multi-arch manifest: yes — OCI index with per-platform layers

Evidence: cert-manager CI builds with `ko` which produces multi-arch by default.
The Makefile targets `linux/amd64,linux/arm64` explicitly. GitHub releases page
lists multi-arch container images. The `distroless_base: gcr.io/distroless/static`
in VENDORS.yaml is consistent — `ko` + distroless/static is the standard Go
multi-arch pipeline.

## System Requirements

- CPU: 10m request per component (controller, webhook, cainjector) — very lightweight
- Memory: 32Mi request per component, 128-256Mi limits. Total ~96Mi baseline, ~512Mi ceiling
- Disk: No PVCs required. cert-manager is stateless — all state lives in Kubernetes
  API objects (Certificate, CertificateRequest, Issuer, ClusterIssuer CRDs).
- Kernel features: None special. Standard Kubernetes API access only.
- Network: Needs to reach the Kubernetes API server. For ACME/Let's Encrypt it
  needs outbound HTTPS (port 443) — but we're using self-signed issuers initially,
  so no external network access required at bootstrap.

## Dependencies

| Dependency | Layer | Status |
|-----------|-------|--------|
| Kubernetes API (1.25+) | 0 | provided by k3s |
| CRDs (self-installed) | 1 | chart handles via `installCRDs: true` |
| No external dependencies | — | n/a |

cert-manager is a leaf dependency — it depends only on the Kubernetes API.
This makes it ideal as the first chart to install in Layer 1.

## Images

| Image | Tag | arm64 | Registry |
|-------|-----|-------|----------|
| quay.io/jetstack/cert-manager-controller | v1.14.0 | yes | quay.io |
| quay.io/jetstack/cert-manager-webhook | v1.14.0 | yes | quay.io |
| quay.io/jetstack/cert-manager-cainjector | v1.14.0 | yes | quay.io |
| quay.io/jetstack/cert-manager-startupapicheck | v1.14.0 | yes | quay.io |

Note: startupapicheck is a Job that runs at install time to verify API server
connectivity. It completes and the pod is cleaned up.

All images are built with `ko` on `gcr.io/distroless/static` — no shell,
no package manager, minimal attack surface.

## Configuration Required

Our chart (`cluster/kind/charts/cert-manager/`) wraps the upstream Jetstack chart
as a dependency and adds:

- `cert-manager.installCRDs: true` — installs CRDs as part of the Helm release.
  This is the simplest approach but means `helm uninstall` will also remove CRDs
  (and all Certificate resources). For production, consider `--set installCRDs=false`
  and managing CRDs separately. For our use case, this is fine.
- `cert-manager.replicaCount: 2` — HA for the controller.
- `selfSigned.enabled: true` — creates a self-signed ClusterIssuer for bootstrap.
  This is the right default — we don't have Vault/OpenBao yet at Layer 1.
- `vault.enabled: false` — Vault/OpenBao issuer disabled until Layer 1 secrets
  engine is running.
- Resource limits set for all three components (controller, webhook, cainjector).
- podAntiAffinity configured (preferred, not required — works with 1 node, prefers spreading on 3+).

**What needs to be set for Lima+k3s:**
- `global.storageClass` is set to `ceph-block` but k3s uses `local-path` by default.
  cert-manager doesn't need storage, so this doesn't matter for this chart.
- `global.imageRegistry` is empty — images will pull from quay.io directly during
  bootstrap (before Zot is running). This is acceptable for Layer 1 — the autarky
  boundary is Layer 2 (Zot).

## Known Limitations

- **CRD lifecycle:** `installCRDs: true` ties CRD lifecycle to the Helm release.
  An accidental `helm uninstall` deletes all Certificate CRs cluster-wide.
  Mitigation: don't uninstall, use `helm upgrade` for changes.
- **Webhook ordering:** The cert-manager webhook must be ready before any
  Certificate resources can be created. If the webhook isn't ready, kubectl
  commands that create Certificates will fail with admission errors. The
  `startupapicheck` Job handles this — it waits for the webhook to be ready.
- **cainjector memory:** On large clusters with many webhooks, cainjector can
  use significant memory. Our 128Mi limit is fine for a small cluster.
- **No external CA integration at bootstrap:** Self-signed only until OpenBao
  is running. This means TLS certificates won't be trusted by browsers without
  manual trust store configuration. Expected for a development/bootstrap cluster.

## HA Model

cert-manager controller uses **leader election** via Kubernetes Lease objects.
Only one replica is active at a time; the other is hot standby. This means:

- `replicaCount: 2` gives failover, not throughput scaling
- No shared storage needed
- No external coordination service needed
- Controller failover takes ~15 seconds (lease renewal period)
- Webhook runs active-active (all replicas serve admission requests)
- cainjector uses its own leader election (same model as controller)

Our chart sets `replicaCount: 2` with preferred podAntiAffinity — this is
correct for our 3-node Lima cluster.

## VENDORS.yaml Status

- License: Apache-2.0 — allowed
- Deprecated: false
- Version match: yes — VENDORS.yaml pins v1.14.0, chart appVersion is 1.14.0
- Distroless: yes — `gcr.io/distroless/static`
- HA notes: "stateless controller with leader election; scale replicas — deferred"
  (deferred means the HA chart config exists but wasn't validated — our chart
  already has replicaCount: 2 and antiAffinity)

## Risks

- **Low risk:** quay.io availability during bootstrap. If quay.io is down,
  the install fails. Mitigation: pre-pull images via downloads.json before
  the install cycle.
- **Low risk:** CRD version skew if we upgrade cert-manager later. The
  `installCRDs` approach means Helm manages the CRDs. If a future upgrade
  changes CRD schemas, Helm handles it. This is actually simpler than
  manual CRD management for our use case.
- **No risk from arm64:** Multi-arch confirmed. This will not be a Harbor
  situation (Harbor was amd64-only, causing cycles of ImagePullBackoff).

## Recommendation

**INSTALL**

cert-manager is the ideal first chart: no dependencies beyond the Kubernetes API,
multi-arch images confirmed, stateless with built-in leader election for HA,
minimal resource requirements, and a well-structured wrapper chart already exists
in the repo. The self-signed ClusterIssuer provides immediate value for TLS
bootstrapping of higher-layer services. Install with the existing chart as-is.
