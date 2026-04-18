# Helm Chart Standards

## HA — Mandatory at Every Layer

Every chart MUST include:
- `replicaCount: 2` minimum (configurable, default >= 2)
- `podDisruptionBudget: { minAvailable: 1 }`
- `podAntiAffinity` (preferredDuringScheduling minimum, requiredDuring for critical services)
- `readinessProbe` and `livenessProbe` on every container
- `resources.requests` and `resources.limits` on every container

## Values Conventions

```yaml
global:
  domain: "sovereign-autarky.dev"   # overridden by parent
  storageClass: "ceph-block"
  imageRegistry: "harbor.{{ .Values.global.domain }}/sovereign"
```

**Never hardcode:**
- Domain names — use `{{ .Values.global.domain }}`
- Storage class — use `{{ .Values.global.storageClass }}`
- Image registry — use `{{ .Values.global.imageRegistry }}/`
- Passwords or secrets — use Sealed Secrets or OpenBao references

All ingress hostnames: `<service>.{{ .Values.global.domain }}`

## Upstream Wrapper Charts

When wrapping an upstream chart (bitnami, etc.):
1. Research the upstream's values.yaml for existing HA, PDB, and anti-affinity support
2. Use the upstream's built-in keys rather than adding templates
3. The HA gate checks the rendered output, not the values structure

## Image Tags

Format: `<upstream-version>-<source-sha>-p<patch-count>` (e.g. `v1.16.0-a3f8c2d-p3`)
Never `:latest`. Never just `:<version>`.

## Quality Gates (run before passes:true)

```bash
helm lint platform/charts/<name>/
helm template platform/charts/<name>/ | grep PodDisruptionBudget
helm template platform/charts/<name>/ | grep podAntiAffinity
grep -q "replicaCount:" platform/charts/<name>/values.yaml  # must be >= 2
bash scripts/ha-gate.sh --chart <name>   # scoped: exits 0/1 based on this chart only
```

## Autarky Gate

```bash
# No external registries in templates
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "FAIL" && exit 1 || echo "PASS"

# All images use global.imageRegistry
grep -rn "^\s*image:" platform/charts/*/templates/ \
  | grep -v "\.Values\.global\.imageRegistry\|{{" && echo "FAIL" && exit 1 || echo "PASS"
```

## ArgoCD Integration

When adding a new chart:
1. Create `platform/charts/<service>/` with Chart.yaml, values.yaml, templates/
2. Create `platform/argocd-apps/<tier>/<service>-app.yaml`
3. Add the destination namespace to `platform/charts/network-policies/values.yaml` — every non-system namespace must appear in the egress baseline or external traffic is not blocked at the workload layer
4. ArgoCD auto-syncs from the root app

ArgoCD app manifests require `spec.revisionHistoryLimit: 3`.
