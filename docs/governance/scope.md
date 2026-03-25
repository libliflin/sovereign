# Scope Definition — What Sovereign Is and Isn't

Sovereign is a self-hosted, foundation-governed Kubernetes platform that any developer can clone, configure, and run to get a complete production-grade development environment — with zero dependency on cloud providers or commercial SaaS.

---

## In Scope

Everything that runs on the cluster as a platform service and enables a development team to operate independently:

**Foundation layer:**

- CNI (Cilium)
- Certificate management (cert-manager)
- Secret management (OpenBao)
- GitOps engine (ArgoCD)
- Distributed storage (Rook/Ceph)

**Identity and access:**

- Identity and SSO (Keycloak)

**Artifact management:**

- Container registry (Harbor)
- Source control (GitLab)

**Security:**

- Service mesh (Istio)
- Policy enforcement (OPA / Gatekeeper)
- Runtime security (Falco, Trivy)

**Observability:**

- Metrics (Prometheus, Grafana)
- Logs (Loki)
- Traces (Tempo)

**Developer experience:**

- Developer portal (Backstage)
- Browser-based IDE (code-server)
- Code quality (SonarQube)

**Testing infrastructure:**

- Browser testing (Selenium Grid)
- Load testing (k6 Operator)
- Email testing (MailHog)
- Resilience testing (Chaos Mesh)

**Bootstrap and local development:**

- Bootstrap scripts for common VPS providers (Hetzner, DigitalOcean, generic Ubuntu)
- kind-based local testing infrastructure

**Platform tooling:**

- The sovereign-pm project management tool (dogfooding: sovereign is built with sovereign)

---

## Out of Scope

The following are explicitly out of scope. Raising a story for any of these is a scope creep indicator — see the decision tree below.

- **Managed cloud services as substitutes.** No AWS S3 (use MinIO or Ceph object storage), no RDS (use PostgreSQL on Ceph), no SES (use a self-hosted SMTP relay). Cloud equivalents are not acceptable substitutes — they reintroduce vendor dependency.
- **Cloud-provider-specific primitives.** No AWS ALB Ingress Controller, no GCP Cloud Armor, no Azure Key Vault CSI driver. If a component requires a cloud provider to function, it doesn't belong here.
- **Full cluster lifecycle management at fleet scale.** Sovereign bootstraps and manages a single cluster (or a small number of clusters). Multi-cluster fleet management is the domain of Cluster API or Talos/Sidero. Sovereign is the application platform, not the cluster orchestrator.
- **Application frameworks or language-specific tooling.** Sovereign is language-agnostic. No Spring Boot starters, no Rails generators, no Django management commands. The developer portal (Backstage) catalogs what's available — it doesn't generate application code.
- **Multi-tenant SaaS hosting.** Sovereign is designed for a single organization operating its own infrastructure. Billing, tenant isolation at the business level, and SaaS-specific concerns (usage metering, sign-up flows) are out of scope.
- **Proprietary monitoring agents or APM tools.** No Datadog agent, no New Relic agent, no Splunk forwarder. Sovereign's observability stack (Prometheus + Grafana + Loki + Tempo) is complete. Adding a proprietary agent introduces license cost and vendor dependency.
- **CI/CD pipelines beyond GitLab CI and ArgoCD.** Sovereign ships GitLab CI for build pipelines and ArgoCD for deployment. Jenkins, CircleCI, GitHub Actions, Tekton, and Drone are not included. GitLab CI covers the use case without additional components.
- **Developer convenience tools that only run locally.** IDE plugins, CLI helpers, shell completions — these belong in a README as optional, not in the platform as a managed service.

---

## The "Should We Add X?" Decision Tree

Work through this in order. Stop at the first applicable answer.

1. **Is X already provided by a component in scope?** Consolidate — use the existing component's feature rather than adding a new one. Check Grafana before adding another dashboard tool. Check GitLab before adding a separate artifact store. Check Backstage before building a custom developer portal feature.

2. **Is X a CNCF Graduated or Incubating project that fills a genuine gap?** Evaluate for inclusion. A genuine gap means: a specific platform capability is missing (e.g., chaos engineering, database operator) and no in-scope component provides it.

3. **Does X replace something in scope with better sovereignty posture?** Consider replacing, not adding. If X is more foundation-governed, more permissively licensed, and equivalently capable — open a story to replace the existing component. Do not run both in parallel.

4. **Is X a developer convenience tool (IDE plugin, CLI helper, local script)?** Document it in the README as optional. Do not add it as a platform service.

5. **Does adding X require a cloud provider account or managed service to function?** This is a **BLOCKER**. Find the self-hosted alternative. If no self-hosted alternative exists, the capability is out of scope until one exists.

6. **Is X only relevant to a specific language or framework?** Out of scope. Document in the README under "language-specific tooling" if it's worth mentioning at all.

If X doesn't fit any of these criteria, it's out of scope. Add a `scopeNote` to the story and return it.

---

## Sovereign Is Not

- **Not a PaaS.** Sovereign does not manage your application's lifecycle, auto-scale your workloads, or provide application-level abstractions. Kubernetes does that. Sovereign provides the platform on which you operate Kubernetes workloads.
- **Not a managed service provider.** You deploy it. You operate it. You are responsible for it. Sovereign gives you the tools to do that effectively — it doesn't do it for you.
- **Not a multi-cloud abstraction layer.** Sovereign's goal is to eliminate cloud dependency, not to abstract it. If you want to run the same workloads on AWS and GCP simultaneously, that's a different problem. Sovereign is for teams that want to stop depending on cloud providers entirely.
- **Not an alternative to Kubernetes.** Sovereign runs ON Kubernetes. It is a platform built on top of Kubernetes, not a replacement for it.
- **Not opinionated about your application architecture.** Microservices, monoliths, event-driven, REST, gRPC — sovereign doesn't care. It provides the infrastructure. You build what you build.

---

## Scope Creep Warning Signs

A story is probably out of scope if it requires any of the following:

- **A cloud provider API key to function.** This means the feature has a cloud dependency. Find the self-hosted path.
- **A proprietary license.** Goes through the license policy gate. Proprietary software in the platform undermines the sovereignty guarantee.
- **A single-vendor SaaS account.** GitHub Actions, Snyk, PagerDuty, LaunchDarkly — these are SaaS dependencies. Sovereign equivalents exist or the feature is out of scope.
- **More than one Helm chart to be built simultaneously in a single story.** This is a complexity signal. Split the story. Each story should add or modify one chart at a time.
- **Coupling to a specific cloud region, availability zone, or provider network.** Sovereign is portable. If the feature only works on Hetzner, or only in us-east-1, it's not a platform feature — it's a provider-specific customization.

When you see these signs: stop, add `"scopeNote": "out of scope — [reason]"` to the story's `reviewNotes`, raise a BLOCKER, and escalate. Do not implement out-of-scope work even if the story explicitly asks for it. The story was written incorrectly — surface that, don't silently do the wrong thing.

See `docs/governance/sovereignty.md` for the dependency evaluation checklist.
