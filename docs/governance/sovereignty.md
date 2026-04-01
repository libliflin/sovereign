# Sovereignty Definition

"Sovereign" means the platform is free from any single vendor's ability to change terms, revoke access, alter the roadmap, or charge for continued use. This is a stronger guarantee than "open source." Open source licenses can be relicensed by a company that holds copyright, forks can be abandoned, and dual-licensing schemes can restrict usage over time. Sovereignty requires that every critical component of the platform is governed by a neutral foundation — one where no single company controls the future of the project, where governance is documented and enforced, and where the community, not a product team, decides what gets built next.

---

## The Two-Tier Policy

### Tier 1 — Platform Infrastructure

CNI, storage, PKI, secret management, GitOps engine, service mesh, policy engine, and the observability pipeline are Tier 1. These MUST come from a neutral foundation: CNCF Graduated or Incubating, Apache Software Foundation, Linux Foundation, or Cloud Foundry Foundation. No exceptions.

Rationale: if the CNI or secret store changes license, migrating is extremely painful. These components are load-bearing walls. By the time you discover the problem, you have hundreds of workloads depending on the behavior and APIs of the old component. The migration cost grows every day. The only protection is to never accept a Tier 1 component that isn't foundation-governed from day one.

### Tier 2 — Application Layer

GitLab, Keycloak, Harbor, Backstage, and similar services are Tier 2. These MUST have a permissive license (Apache 2.0, MIT, or BSD). Foundation governance is preferred but not required if the project has multiple maintainers and a track record of independence from any single company.

Any Tier 2 component where a single vendor steers the roadmap MUST be explicitly documented in this audit table with a justification. "It's the best tool for the job" is not sufficient on its own — you must also document the exit path if the vendor changes its license or terms.

---

## Foundation Neutrality Criteria (Tier 1)

A component qualifies as foundation-neutral if ALL of the following are true:

1. The project is hosted under CNCF, ASF, Linux Foundation, Cloud Foundry Foundation, or an equivalent neutral body — not under a company's GitHub org.
2. Governance is documented: MAINTAINERS.md, TOC voting process, or equivalent public governance record exists.
3. No single company employs more than 50% of maintainers with merge rights. (Check the OWNERS or MAINTAINERS file.)
4. Roadmap decisions require community consensus — not a product team's sprint planning.

If a project fails any of these criteria, it cannot be Tier 1. Find the CNCF alternative.

---

## Current Stack Audit

| Component | Tier | Foundation | License | Sovereignty Status | Notes |
|-----------|------|------------|---------|-------------------|-------|
| Kubernetes | 1 | CNCF / Linux Foundation | Apache 2.0 | Sovereign | Reference compute layer |
| Cilium | 1 | CNCF Graduated | Apache 2.0 | Sovereign | Reference CNI |
| ArgoCD | 1 | CNCF | Apache 2.0 | Sovereign | GitOps engine |
| Crossplane | 1 | CNCF | Apache 2.0 | Sovereign | Infrastructure composition |
| cert-manager | 1 | CNCF | Apache 2.0 | Sovereign | PKI |
| OpenBao | 1 | Linux Foundation | Apache 2.0 | Sovereign | Vault fork after BSL change — see "The Vault Precedent" |
| Prometheus | 1 | CNCF | Apache 2.0 | Sovereign | Metrics collection |
| Grafana | 1 | Apache 2.0 | Apache 2.0 | Acceptable | Grafana Labs is dominant maintainer but foundation-adjacent; AGPL-licensed enterprise features not used |
| Loki | 1 | Apache 2.0 | Apache 2.0 | Acceptable | Grafana Labs; same note as Grafana; OSS version only |
| Tempo | 1 | Apache 2.0 | Apache 2.0 | Acceptable | Grafana Labs; same note |
| Falco | 1 | CNCF | Apache 2.0 | Sovereign | Runtime security |
| Trivy | 2 | Apache 2.0 | Apache 2.0 | Tier 2 exception | Aqua Security is primary maintainer; no CNCF home yet; acceptable at Tier 2, not Tier 1 |
| OPA / Gatekeeper | 1 | CNCF | Apache 2.0 | Sovereign | Policy engine |
| Keycloak | 2 | Apache 2.0 | Apache 2.0 | Tier 2 exception | Red Hat steers the project; documented exit: Zitadel (Apache 2.0, Go, ZITADEL GmbH) or Kanidm (Apache 2.0, Rust, community). Note: Dex (CNCF) is NOT a valid exit — it is a federation connector, not a full IdP; it has no user store, admin UI, or role management. |
| GitLab | 2 | MIT (CE) | MIT | Acceptable | GitLab Inc. controls roadmap; exit path: Forgejo (GPL v3, Codeberg e.V.) or Gitea (MIT, Gitea Limited); CE edition only. Forgejo is preferred exit — community-governed non-profit, GPL v3 acceptable under the Deployment Platform Exception in license-policy.md. |
| Forgejo | 2 | GPL v3 | GPL v3 | Acceptable under exception | Community-governed (Codeberg e.V., German non-profit); GPL v3 acceptable for service deployment — see license-policy.md Deployment Platform Exception. Preferred GitLab exit. Source vendored per right-to-repair model. |
| Harbor | 2 | CNCF Graduated | Apache 2.0 | Sovereign | Container registry |
| Rook / Ceph | 1 | CNCF Graduated | Apache 2.0 | Sovereign | Distributed storage |
| K3s | Bootstrap | Apache 2.0 | Apache 2.0 | Bootstrap convenience | SUSE/Rancher maintains; used in bootstrap scripts only — not a runtime platform dependency |
| Sealed Secrets | 1 | Apache 2.0 | Apache 2.0 | Acceptable | Bitnami/VMware heritage; no CNCF home; low migration cost if license changes |
| Backstage | 2 | CNCF | Apache 2.0 | Sovereign | Developer portal |

---

## Evaluating a New Dependency

Run through this checklist before adding any new chart, library, tool, or upstream dependency. This is a governance gate, not a guideline.

1. **What tier is this?** Is it platform infrastructure (CNI, storage, PKI, secret management, GitOps engine, service mesh, policy engine, observability pipeline) or application layer?
2. **What is the license?** Run it through `docs/governance/license-policy.md`. If it's on the Prohibited list, stop here.
3. **If Tier 1:** is it in a neutral foundation (CNCF, ASF, LF)? If not — **BLOCKER**. Do not add it. Find the CNCF project that does the same thing.
4. **If Tier 2:** is it Apache 2.0, MIT, or BSD? If not — **BLOCKER**. Find an alternative.
5. **Is there a CNCF Graduated or Incubating project that does the same thing?** If so, use that instead. Do not add a non-CNCF project when a CNCF one exists and is mature.
6. **Could the vendor change the license tomorrow and leave us stranded?** If yes — find the fork or alternative now, document it in VENDORS.yaml as `alternative_if_relicensed`, and evaluate your timeline for switching.

---

## The Vault Precedent

In August 2023, HashiCorp changed Vault's license from Mozilla Public License 2.0 to the Business Source License (BSL). BSL is not OSI-approved. It restricts competitive use and gives HashiCorp unilateral control over what "competitive" means. This happened to a Tier 1 component — secret management — that is deeply embedded in every service's startup path.

Sovereign's response: replace Vault with OpenBao, a Linux Foundation fork that maintains the Apache 2.0 license and the same API surface. See `charts/openbao/` and `vendor/recipes/openbao/`.

The lesson: do not wait for the official "community fork" announcement before acting. When a vendor changes a license on a Tier 1 component, start tracking the situation immediately. Adopt the community fork as soon as it has its first stable release. The cost of migration grows every week you stay on the vendor-controlled version.

When this happens again — and it will — the response is:

1. Check if a foundation fork exists.
2. If yes: pin to the last permissive release of the original, schedule migration, adopt the fork.
3. If no fork yet: pin to the last permissive release, open a story to evaluate alternatives, and monitor the situation weekly.
4. Document in VENDORS.yaml with `license_change_detected: true` and the date.
5. This is a P0 item, higher priority than any feature work.
