# Sovereign Platform — Distroless Compatibility Matrix

All container images in the Sovereign Platform MUST use distroless base images.
This document tracks the compatibility status of every vendored service.

## Status Legend

| Status | Meaning |
|---|---|
| `compatible` | Ships distroless today (or can be built distroless with `ko`/standard build) |
| `partial` | Requires multi-stage Dockerfile; final image is distroless but builder stage is not |
| `incompatible` | Cannot run distroless due to runtime requirements (kernel modules, browser binaries, etc.) |
| `rewrite-candidate` | Should be replaced with a distroless-native alternative |

## Base Image Reference

| Base | Runtime | Used by |
|---|---|---|
| `gcr.io/distroless/static` | Go static binaries | cilium, crossplane, cert-manager, … |
| `gcr.io/distroless/java21` | JVM 21 | keycloak, sonarqube, reportportal, wiremock |
| `gcr.io/distroless/nodejs` | Node.js | backstage, code-server |
| `none` | N/A | falco, selenium-grid, gitlab (incompatible/skip) |

---

## Compatibility Table

| Service | Language/Runtime | Distroless Base | Status | Notes |
|---|---|---|---|---|
| cilium | Go | `gcr.io/distroless/static` | compatible | All components ship as static Go binaries; built with `ko` |
| crossplane | Go | `gcr.io/distroless/static` | compatible | Static Go binary; `ko` build produces distroless image |
| cert-manager | Go | `gcr.io/distroless/static` | compatible | Official upstream already ships distroless images |
| sealed-secrets | Go | `gcr.io/distroless/static` | compatible | Kubeseal controller is a static Go binary |
| vault | Go | `gcr.io/distroless/static` | compatible | **DEPRECATED** — BUSL-1.1 license. Use `openbao` instead |
| openbao | Go | `gcr.io/distroless/static` | compatible | Apache-2.0 fork of Vault; static Go binary; built with `ko` |
| keycloak | Java (JVM 21) | `gcr.io/distroless/java21` | partial | Multi-stage build: Gradle builder → distroless/java21 final. Long-term alternative: **Kanidm** (Rust, native distroless, Apache-2.0) |
| rook-ceph | Go | `gcr.io/distroless/static` | compatible | Rook operator is a static Go binary; Ceph daemons run in their own pods (not patched by sovereign build) |
| argocd | Go | `gcr.io/distroless/static` | compatible | All ArgoCD server/controller/repo-server components are static Go binaries |
| gitlab | Ruby/Go/Node.js (mixed) | `none` | incompatible | Monolithic Rails app; hundreds of runtime dependencies. Build and deploy as upstream Docker image. Not a candidate for sovereign build. |
| harbor | Go | `gcr.io/distroless/static` | compatible | Harbor core, jobservice, registry-ctl are all static Go binaries |
| istio | Go | `gcr.io/distroless/static` | compatible | Pilot, citadel, ingress-gateway are static Go binaries; official upstream ships distroless |
| opa-gatekeeper | Go | `gcr.io/distroless/static` | compatible | Gatekeeper controller is a static Go binary |
| trivy-operator | Go | `gcr.io/distroless/static` | compatible | Static Go binary; built with `ko` |
| falco | C++/eBPF | `none` | incompatible | Requires kernel module or eBPF probes; must run in a privileged container with host PID namespace. Cannot use distroless. |
| prometheus-stack | Go | `gcr.io/distroless/static` | compatible | Prometheus, Alertmanager, and node-exporter are static Go binaries |
| loki | Go | `gcr.io/distroless/static` | compatible | **DEPRECATED** — AGPL-3.0 license. Use `victorialogs` (Apache-2.0) instead |
| thanos | Go | `gcr.io/distroless/static` | compatible | Static Go binary; extends Prometheus long-term storage |
| tempo | Go | `gcr.io/distroless/static` | compatible | **DEPRECATED** — AGPL-3.0 license. Use `jaeger` (Apache-2.0) instead |
| grafana | Go/JS | `none` | rewrite-candidate | **DEPRECATED** — AGPL-3.0 license. Frontend assets prevent pure distroless. Use `perses` (Apache-2.0) instead |
| backstage | Node.js | `gcr.io/distroless/nodejs` | partial | Multi-stage: npm ci builder → distroless/nodejs final. Plugins may require native addons — audit each plugin for distroless compatibility |
| code-server | Node.js | `gcr.io/distroless/nodejs` | partial | Multi-stage: npm ci builder → distroless/nodejs final. VS Code extensions with native binaries must be pre-compiled |
| sonarqube | Java (JVM 21) | `gcr.io/distroless/java21` | partial | Multi-stage: Maven builder → distroless/java21 final. Embedded Elasticsearch requires JVM heap tuning |
| reportportal | Java (JVM 21) | `gcr.io/distroless/java21` | partial | Multi-stage: Maven builder → distroless/java21 final. Multiple microservices each get their own distroless image |
| selenium-grid | Java + browser binaries | `none` | incompatible | Requires Chrome/Firefox browser binaries and Xvfb virtual display. Cannot run distroless. Use official Selenium Grid images. |
| k6-operator | Go | `gcr.io/distroless/static` | compatible | **DEPRECATED** — AGPL-3.0 license. Run k6 (MIT) directly as a Kubernetes Job without the operator |
| wiremock | Java (JVM 21) | `gcr.io/distroless/java21` | partial | Multi-stage: Maven builder → distroless/java21 final. Standalone JAR deployment |
| mailhog | Go | `gcr.io/distroless/static` | compatible | Pure Go SMTP server; static binary; built with `ko` |
| chaos-mesh | Go | `gcr.io/distroless/static` | compatible | Controller and dashboard are static Go binaries |

---

## Build Tool Summary

| Build Tool | Services | When to use |
|---|---|---|
| `ko` | All Go services (distroless/static) | Go binaries only; auto-selects distroless base; uses go.mod/go.sum |
| `docker` (multi-stage) | Java and Node.js services | Builder stage + distroless final layer |
| `skip` | gitlab, falco, selenium-grid | Use upstream Docker images as-is; sovereign build not applicable |

---

## Migration Roadmap

Services currently marked `partial` or `incompatible` have the following migration paths:

### Keycloak → Kanidm (long-term)
Kanidm (Rust, Apache-2.0) is a modern identity provider that:
- Compiles to a static binary → `gcr.io/distroless/static` compatible
- Supports OIDC, LDAP, and RADIUS natively
- Timeline: evaluate after Phase 5 security work is complete

### GitLab → Forgejo (long-term)
Forgejo (MIT) is a Go-based Git forge that:
- Is a clean Go binary → `gcr.io/distroless/static` compatible
- Timeline: evaluate after Phase 4 autarky pipeline is proven with simpler services

### Falco → eBPF-native alternative
Falco cannot be made distroless due to kernel-level requirements. Continue using the
official upstream image. Isolate it in a dedicated security namespace with strict RBAC.

### Selenium Grid
Browser automation inherently requires browser binaries. Use the official Selenium Grid
images pinned to a specific version. Sovereign cannot make this distroless.

---

## Policy Enforcement

Per the Sovereign Platform standard:

1. **Every new container image MUST use a distroless base.** No exceptions.
2. Any service that cannot use distroless MUST have `deprecated: true` in `vendor/VENDORS.yaml`
   with `deprecated_reason` explaining why and `alternative` naming a distroless-compatible replacement.
3. Pull requests adding a non-distroless image without a VENDORS.yaml `deprecated` entry will be rejected.
4. `vendor/audit.sh` checks this automatically — it must exit 0 before any vendor story can pass.
