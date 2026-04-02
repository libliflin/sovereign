# Helm Chart Operations

## Kubeconfig

The loop sets `KUBECONFIG` from Lima automatically. All helm commands use it:

```bash
export KUBECONFIG=$(limactl list sovereign-0 --format 'unix://{{.Dir}}/copied-from-guest/kubeconfig.yaml')
```

## Single-Chart Upgrade

The core operation. Upgrade one chart at a time, never the whole stack:

```bash
timeout 60 helm upgrade --install <release> platform/charts/<chart>/ \
  -n <namespace> \
  --create-namespace \
  --timeout 90s \
  --wait
```

Always wrap in `timeout` to protect the cycle budget.

If the chart has dependencies (subchart in Chart.yaml):
```bash
helm dependency update platform/charts/<chart>/
```

## Deployment Order

Charts deploy in strict layer order. Never install a higher layer chart while
a lower layer has failures:

```
Layer 0: k3s + Cilium CNI (managed by Lima + k3s bootstrap)
Layer 1: cert-manager + sealed-secrets + OpenBao
Layer 2: Harbor (autarky boundary — after this, all images internal)
Layer 3: Keycloak (identity / SSO)
Layer 4: Forgejo + ArgoCD (SCM + GitOps)
Layer 5: Prometheus, VictoriaLogs, Jaeger, Perses, Thanos (observability)
Layer 6: Istio, OPA-Gatekeeper, Falco, Trivy (security mesh)
Layer 7: Backstage, mailpit (developer experience)
```

## Chart Standards

All charts in `platform/charts/` follow these conventions:

**Values:**
- Domain: `{{ .Values.global.domain }}` — never hardcoded
- StorageClass: `{{ .Values.global.storageClass }}`
- Image registry: `{{ .Values.global.imageRegistry }}/`
- No hardcoded passwords — use Sealed Secrets or OpenBao

**HA (mandatory):**
- `replicaCount: 2` minimum in values.yaml
- PodDisruptionBudget template must exist
- podAntiAffinity configured
- Resource requests AND limits on every container
- With 3 real nodes (Lima VMs), HA actually works — don't skip it

## Checking Chart Health

```bash
# Is the release deployed?
helm status <release> -n <namespace>

# Are all pods running?
kubectl get pods -n <namespace>

# Lint before deploying
helm lint platform/charts/<chart>/

# Template to inspect output
helm template platform/charts/<chart>/ | head -100
```

## Forcing Pod Restart

**Never use `kubectl rollout restart` on Helm-managed resources.** It creates
managedFields conflicts that break subsequent helm upgrades.

Instead, force a template change:
```bash
timeout 60 helm upgrade <release> platform/charts/<chart>/ \
  -n <namespace> \
  --set-string "podAnnotations.forceRestart=$(date +%s)" \
  --timeout 90s --wait
```

Note: `--set-string` not `--set` for annotation values.

## Stuck Helm Releases

If a release is stuck in `pending-install` or `pending-upgrade`:

```bash
helm history <release> -n <namespace>
helm rollback <release> 0 -n <namespace>

# Or if never successfully installed:
helm uninstall <release> -n <namespace>
```

## OPA Gatekeeper Two-Pass Install

Gatekeeper CRDs must be established before constraint resources can be applied:

```bash
# Pass 1: Controller + CRD templates only
timeout 60 helm upgrade --install opa-gatekeeper platform/charts/opa-gatekeeper/ \
  -n gatekeeper-system --create-namespace \
  --set constraintsEnabled=false --timeout 90s --wait

# Wait for CRDs
timeout 30 kubectl wait --for=condition=Established \
  crd/k8snoprivilegeescalations.constraints.gatekeeper.sh --timeout=60s

# Pass 2: Enable constraints
timeout 60 helm upgrade opa-gatekeeper platform/charts/opa-gatekeeper/ \
  -n gatekeeper-system --set constraintsEnabled=true --timeout 90s --wait
```

## Autarky Gate

No external registry references in chart templates:

```bash
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "FAIL" || echo "PASS"
```
