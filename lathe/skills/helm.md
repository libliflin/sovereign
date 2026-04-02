# Helm Chart Operations

## Single-Chart Upgrade

The core operation. Upgrade one chart at a time, never the whole stack:

```bash
helm upgrade --install <release> platform/charts/<chart>/ \
  -n <namespace> \
  --kube-context kind-sovereign-test \
  --create-namespace \
  --timeout 90s \
  --wait
```

If the chart has dependencies (subchart in Chart.yaml):
```bash
helm dependency update platform/charts/<chart>/
helm upgrade --install ...
```

## Deployment Order

Charts deploy in strict layer order. Never install a higher layer chart while
a lower layer has failures:

```
Layer 0: (managed by install-foundations.sh — cilium, cert-manager, sealed-secrets, minio)
Layer 1: openbao
Layer 2: harbor
Layer 3: keycloak
Layer 4: forgejo, argocd
Layer 5: prometheus-stack, victorialogs, jaeger, perses, thanos
Layer 6: istio, opa-gatekeeper, falco, trivy-operator
Layer 7: backstage, mailpit
```

## Chart Standards

All charts in `platform/charts/` follow these conventions:

**Values:**
- Domain: `{{ .Values.global.domain }}` — never hardcoded
- StorageClass: `{{ .Values.global.storageClass }}`
- Image registry: `{{ .Values.global.imageRegistry }}/`
- No hardcoded passwords — use Sealed Secrets or OpenBao

**HA (mandatory but deferred for kind):**
- `replicaCount: 2` minimum in values.yaml
- PodDisruptionBudget template must exist
- podAntiAffinity configured
- Resource requests AND limits on every container

**Do NOT remove HA properties to fix kind issues.** They're there for production.
If kind can't schedule due to anti-affinity or resource limits, that's a kind
limitation to work around (e.g., reduce resource requests), not a reason to
strip HA.

## Checking Chart Health

```bash
# Is the release deployed?
helm status <release> -n <namespace> --kube-context kind-sovereign-test

# Are all pods running?
kubectl get pods -n <namespace> --context kind-sovereign-test

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
helm upgrade <release> platform/charts/<chart>/ \
  -n <namespace> \
  --kube-context kind-sovereign-test \
  --set-string "podAnnotations.forceRestart=$(date +%s)" \
  --timeout 90s --wait
```

Note: `--set-string` not `--set` for annotation values (Kubernetes requires strings).

## Stuck Helm Releases

If a release is stuck in `pending-install` or `pending-upgrade` (from a previous
crash or timeout):

```bash
# Check status
helm status <release> -n <namespace> --kube-context kind-sovereign-test

# If stuck, rollback to last good revision
helm rollback <release> 0 -n <namespace> --kube-context kind-sovereign-test

# Or if never successfully installed, uninstall and retry
helm uninstall <release> -n <namespace> --kube-context kind-sovereign-test
```

## OPA Gatekeeper Two-Pass Install

Gatekeeper CRDs must be established before constraint resources can be applied.

```bash
# Pass 1: Install controller + CRD templates only
helm upgrade --install opa-gatekeeper platform/charts/opa-gatekeeper/ \
  -n gatekeeper-system \
  --kube-context kind-sovereign-test \
  --create-namespace \
  --set constraintsEnabled=false \
  --timeout 90s --wait

# Wait for CRDs
kubectl wait --for=condition=Established crd/k8snoprivilegeescalations.constraints.gatekeeper.sh \
  --context kind-sovereign-test --timeout=60s

# Pass 2: Enable constraints
helm upgrade opa-gatekeeper platform/charts/opa-gatekeeper/ \
  -n gatekeeper-system \
  --kube-context kind-sovereign-test \
  --set constraintsEnabled=true \
  --timeout 90s --wait
```

## Autarky Gate

No external registry references in chart templates:

```bash
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "FAIL" || echo "PASS"
```

All image references must use `{{ .Values.global.imageRegistry }}`.
