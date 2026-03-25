# Retro Patch: Phase 10 — sovereign-pm-webapp
Generated: 2026-03-25T22:01:24Z

## Delivery summary

| Status | Count | Points |
|--------|-------|--------|
| Accepted | 3 | 8 pts |
| Incomplete → backlog | 0 | — |
| Killed | 0 | — |

**Full delivery sprint.** All 3 stories accepted, 8 of 8 planned points completed.

## 5 Whys: incomplete stories

None. All stories accepted this sprint.

## Flow analysis (Heijunka check)

- Sprint avg story size: **2.7 pts**
- Point distribution: `{2: 1, 3: 2}`
- Oversized (> 8 pts): 0
- Split candidates (5–8 pts): 0

Story sizing was well-calibrated. Two 3-point stories and one 2-point story reflects the
natural dependency chain (backend → frontend → Helm/Dockerfile). No flow issues.

## Patterns discovered

- **Multi-stage Dockerfile for Node.js + React monorepo** works cleanly: build frontend
  with `vite build`, build backend with `tsc`, combine in a distroless-style production
  image. This pattern should be reused for any future Node/React services.
- **Keycloak OIDC in kind**: the `keycloak-js` client and JWT middleware need explicit
  `KEYCLOAK_URL` env vars — bake these into the Helm values.yaml with clear placeholders
  so reviewers know where to wire the cluster Keycloak URL.
- **bitnami/postgresql subchart** as a Helm dependency is the preferred quick-start path
  over Crossplane XRC for in-cluster apps without a provisioned DB yet. The Crossplane XRC
  path is the production path once foundations phase is running.
- **Stories with two acceptable implementation paths** (e.g. "bitnami subchart OR Crossplane
  XRC") should have the chosen path decided in the story before implementation starts.
  Leaving it open creates scope ambiguity. Future grooming should resolve OR-choices before
  pulling a story into a sprint.

## Quality gate improvements

All gates passed cleanly (`helm lint`, `helm template | kubectl apply --dry-run`, `npm run
typecheck`, `npm run lint`, `npm run build`). No gate failures this sprint.

One observation: the `attempts` field on all stories is `1`, suggesting the convention is
"attempts = number of times the story was implemented", not "number of retries after review
failure". The first-pass rate formula in ceremonies (`attempts == 0`) would always report 0
for stories that went through at least one implementation pass. Consider whether `attempts`
should be initialised to `0` and only incremented on review failures (re-opens), or whether
the first-pass gate formula should change to `len(reviewNotes) == 0`.

## Velocity

| Increment | Points | Stories | Pass Rate |
|-----------|--------|---------|-----------|
| 0 (ceremonies) | — | — | — |
| 9 (sovereign-pm docs) | 2 | 1 | 100% |
| **10 (sovereign-pm-webapp)** | **8** | **3** | **100%** |

Sprint points accepted: **8 / 8** (100%)
First-review pass rate: **100%** (0 stories re-opened by review ceremony)

## Retro patch → prd/retro-patch-phase10.md
