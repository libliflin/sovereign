# Retro Patch: Phase 3 — gitops-engine
Generated: 2026-03-22

## Suggested additions to CLAUDE.md (LEARNINGS section)

### New patterns discovered this sprint

- Harbor (goharbor/harbor chart) does NOT use a `global.hosts.domain` mechanism like the GitLab chart.
  Disable `expose.type: ingress` in the harbor subchart values and create a wrapper ingress template
  that uses `{{ .Values.global.domain }}`. Do NOT let the upstream chart manage ingress.

- Harbor `externalURL` is a static string in values.yaml — it cannot contain Go template expressions.
  Set a sensible default (e.g., `https://harbor.sovereign-autarky.dev`). Override at deploy time via
  ArgoCD applicationset or via `helm upgrade --set harbor.externalURL=...`. Document this in the chart.

- Stale feature branches from prior sessions may predate CI hardening changes. Before checking out
  an existing remote branch, run `git diff main...<branch> --stat` to see what it diverged from.
  If stale, force-replace with `git push --force-with-lease` after rebasing from main.

- gitlab/gitlab chart v8.x: set `global.minio.enabled: false` at top-level AND in `gitlab.global`
  (the subchart alias) to fully disable MinIO. Also disable `nginx-ingress`, `certmanager`, and
  `prometheus` sub-charts to avoid conflicts with the platform's own instances.

- Hardcoded `sovereign-autarky.dev` in values.yaml defaults is EXPECTED and CORRECT — it is the
  dogfood domain and is overridden by parent chart values or ArgoCD applicationset. Review ceremony
  should check templates/ for hardcoded domains, NOT values.yaml defaults. The AC "Ingress uses
  global.domain" is satisfied when templates use `{{ .Values.global.domain }}`, not when values.yaml
  has no default domain string.

## Stories that failed review (re-opened)

None. Both stories accepted on first review attempt.

## Quality gate improvements suggested

- Add an explicit check to review ceremony: "does the ingress template use .Values.global.domain
  rather than sovereign-autarky.dev?" — grep the templates/ directory, not values.yaml.

## Velocity note

Sprint points: 5 / 5 planned
Review pass rate: 100% (2/2 stories accepted on first review)
Sprint duration: ~1 day (phase 3 started after phase-2h retro)
