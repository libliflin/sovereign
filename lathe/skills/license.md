# License and Vendor Policy

## Quick Reference

| License | Status | Notes |
|---------|--------|-------|
| Apache 2.0 | **Preferred** | Includes patent grant |
| MIT | Permitted | |
| BSD-2/3-Clause | Permitted | |
| ISC | Permitted | MIT-equivalent |
| MPL 2.0 | Permitted | File-level copyleft only |
| GPL v2/v3 | Permitted for independent services | NOT for linked/bundled components |
| AGPL v3 | **Requires explicit review** | Network use clause |
| SSPL | **Prohibited** | Not OSI approved |
| BSL/BUSL | **Prohibited** | Time-delayed, vendor-controlled |
| Commons Clause | **Prohibited** | Commercial restriction |

## Sovereignty Tiers

**Tier 1 (Infrastructure):** CNI, storage, PKI, secrets, GitOps, service mesh, policy, observability.
- MUST come from CNCF Graduated/Incubating, ASF, Linux Foundation, or Cloud Foundry
- No exceptions — these are load-bearing walls
- No single company >50% of maintainers with merge rights

**Tier 2 (Application Layer):** GitLab, Zot, Backstage, etc.
- MUST have permissive license (Apache 2.0, MIT, BSD)
- Foundation governance preferred but not required
- Must have documented exit path if single-vendor steered

## VENDORS.yaml

Source of truth: `platform/vendor/VENDORS.yaml`

Every vendored component must have:
- `license_spdx` field (e.g., `Apache-2.0`, `MIT`)
- `version_pinned` (never `:latest`)
- `fetch_method` (git_tag, tarball, git_commit)

CI fails if `license_spdx` is missing.

## When Upstream Changes License

This has happened before (Vault → BSL, Redis → SSPL, Elasticsearch → SSPL).

1. Pin to last permissive release immediately
2. Search for foundation fork (CNCF, LF, OpenSSF)
3. If fork exists: schedule migration
4. If no fork: create backlog story to replace
5. Document in VENDORS.yaml with `license_change_detected: true`
6. Never upgrade past the last permissive release

**Precedent:** Vault (BSL 2023) → OpenBao (LF, Apache 2.0, same API)

## Decision Tree

```
Is license on Permitted list?
  YES → proceed
  NO  → Is it on Prohibited list?
          YES → BLOCKER. Find alternative.
          NO  → Unknown. Treat as Prohibited until verified.
                Look up SPDX at https://spdx.org/licenses/
```

## Deployment Platform Exception

Helm charts deploying GPL services are NOT combined works. Charts are YAML
references to container images. Services are separate processes communicating
over network APIs. Same basis as Linux kernel running under containers.

## Distroless Standard

All images use distroless bases:
- Go: `gcr.io/distroless/static`
- JVM: `gcr.io/distroless/java21`
- Node.js: `gcr.io/distroless/nodejs`

Non-distroless requires `deprecated: true` in VENDORS.yaml.

## Human Escalation

Escalate to human ONLY for:
- Adding a component with AGPL/BSL license
- Removing a platform component entirely
- License violation detected with no alternative
