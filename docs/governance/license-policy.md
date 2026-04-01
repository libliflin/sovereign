# License Policy

Sovereign uses permissive licenses only; copyleft licenses are incompatible with sovereign's distribution model.

---

## Permitted Licenses

| License | OSI Approved | Copyleft Type | Distribution Compatible | Notes |
|---------|-------------|---------------|------------------------|-------|
| Apache 2.0 | Yes | None | Yes | Preferred. Includes explicit patent grant. |
| MIT | Yes | None | Yes | Acceptable. No patent clause — acceptable risk for most components. |
| BSD-2-Clause | Yes | None | Yes | Acceptable. |
| BSD-3-Clause | Yes | None | Yes | Acceptable. Non-endorsement clause is benign. |
| MPL 2.0 | Yes | File-level only | Yes | Acceptable. File-level copyleft does not propagate to the platform or other charts. |
| ISC | Yes | None | Yes | Acceptable. Functionally MIT-equivalent. Common in Node.js ecosystem. |
| GPL v2 / v3 | Yes | Strong (combined works) | Yes, with conditions | Permitted for services deployed independently — see "Deployment Platform Exception" below. Prohibited if incorporated (linked/bundled) into platform components. |

---

## Prohibited Licenses

| License | OSI Approved | Copyleft Type | Distribution Compatible | Notes |
|---------|-------------|---------------|------------------------|-------|
| GPL v2 / v3 (incorporated) | Yes | Strong | No | Prohibited if incorporated into platform components — linked, bundled, or compiled in. See "Deployment Platform Exception" for the service deployment case. |
| LGPL v2 / v3 | Yes | Weak (linking) | No | Linking requirements affect platform components. Permitted only for services deployed independently under the same exception as GPL. |
| AGPL v3 | Yes | Network (SaaS) | No | Network use clause: any operator running modified AGPL software and exposing it to users must publish source for that service. Permitted with this understanding — the obligation applies to the AGPL component only, not to the platform or users' applications. Requires explicit review before adding. |
| SSPL v1 | No | Extreme | No | MongoDB's anti-cloud license. Not OSI approved. Prohibits running the software as a service. |
| BSL / BUSL | No | Time-delayed | No | Vendor controls when (and whether) it becomes open source. Incompatible with sovereign's guarantees. See "The Vault Precedent" in sovereignty.md. |
| Commons Clause | No | Commercial restriction | No | Explicitly prohibits commercial use when appended to another license. |

---

## Deployment Platform Exception

This platform deploys software as independent services that communicate over network APIs. It does not compile, link, or bundle third-party code into its own binaries. This distinction matters for copyleft analysis.

**A Helm chart that deploys a GPL service is not a combined work with that service.** The chart is YAML referencing a container image name. The running service is a separate process. Communication happens over HTTP, git protocol, or gRPC — standard network interfaces. This is the same legal basis on which:

- Alpine Linux (which ships GPL busybox) is used as a base image without making application code GPL.
- The Linux kernel (GPL with syscall exception) runs under every container without making those containers GPL.
- Homebrew (MIT) distributes formulae for hundreds of GPL packages without becoming GPL.

**GPL v3 services deployed via this platform:**

| Obligation | Applies? | Notes |
|------------|----------|-------|
| Keep GPL license intact for that service | Yes | Always. Do not modify or strip the license. |
| Make source available for that service | Yes | Source must be vendored and accessible. The vendor system satisfies this by design. |
| Publish modifications if distributed externally | Yes, if distributing | Running internally: no obligation. Handing built images to a third party: must provide source for GPL components. |
| Platform Helm charts become GPL | No | Charts are not combined works with the services they deploy. |
| Users' applications become GPL | No | Applications communicate with services via network APIs — not combined works. |
| Publish modifications for internal use only | No | GPL does not require publication for internal deployment. |

**Right-to-repair alignment:** The vendor system (fetch.sh mirrors source, build.sh builds from source) is structurally identical to what GPL requires vendors to provide. By vendoring source for every component — including GPL ones — the platform gives operators full right to inspect, modify, and rebuild any service. This is copyleft working as intended, not a conflict with it.

**AGPL note:** AGPL adds one obligation GPL lacks — if you run modified AGPL software and expose it to users over a network, you must make the modified source available to those users. This applies to the AGPL service only. It does not propagate to the platform or to applications running alongside it. AGPL components require explicit review entry in this file before adoption.

---

## Decision Tree

```text
Is the license on the Permitted list?
  YES → proceed
  NO  → Is it on the Prohibited list?
          YES → BLOCKER. Do not add this dependency. Find an alternative.
          NO  → Unknown license.
                Treat as Prohibited until verified.
                Look up the SPDX identifier at https://spdx.org/licenses/
                If still unclear, escalate — do not assume it's safe.
```

---

## What to Do When an Upstream Changes License

This will happen again. The process is:

1. **Check if a foundation fork exists immediately.** Search CNCF, Linux Foundation, and OpenSSF project lists. Check GitHub for community forks that maintain the original license.
2. **If a fork exists:** pin to the last permissively-licensed release of the original. Schedule migration to the fork. Do not upgrade past the last clean release.
3. **If no fork exists yet:** pin to the last permissively-licensed release. Create a story in the backlog to replace the dependency. Monitor the situation weekly for a fork announcement.
4. **Do NOT upgrade past the last permissively-licensed release.** Each upgrade strengthens the vendor's position and deepens your dependency.
5. **Document in VENDORS.yaml** with a `license_change_detected` field and the date it was detected.

Known precedents already resolved in this stack:

- HashiCorp Vault (BSL 2023) → replaced with OpenBao (LF, Apache 2.0)
- Redis (SSPL 2024) → self-hosted alternative: Valkey (LF, BSD-3-Clause) if Redis is needed
- Elasticsearch (SSPL 2021) → self-hosted alternative: OpenSearch (Apache 2.0, AWS-stewarded but permissive)

---

## Dependency Scanning

Every vendored package MUST have an entry in `vendor/VENDORS.yaml` with a `license_spdx` field containing the SPDX license identifier (e.g., `Apache-2.0`, `MIT`, `BSD-3-Clause`).

CI fails if a new package appears in the vendor manifest without a `license_spdx` entry. This prevents license debt from accumulating silently.

Future automation: `trivy sbom` or equivalent CNCF-approved SBOM tooling will be integrated to automatically surface license information for all container image layers. This is tracked in the backlog. Until then, manual `license_spdx` entries in VENDORS.yaml are required.

When running `vendor/audit.sh`, any dependency with a prohibited license identifier causes a non-zero exit code. This script must pass before any vendor story can be marked complete.
