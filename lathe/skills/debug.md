# Debugging Kubernetes Issues

## Pod Diagnosis

```bash
# Full pod details (scheduling, conditions, events, volumes)
kubectl describe pod -n <namespace> <pod-name> --context kind-sovereign-test

# Quick status of all pods in a namespace
kubectl get pods -n <namespace> --context kind-sovereign-test -o wide
```

## Common Failure Modes

### ImagePullBackOff
Image can't be pulled. Causes:
- Wrong image name or tag
- Registry unreachable from kind nodes
- Image not loaded into kind (use `kind load docker-image`)

**Fix:** Check the image reference in the helm values. For kind, images must be
pre-loaded or available from a registry the nodes can reach.

### CrashLoopBackOff
Container starts and immediately exits. Causes:
- Missing ConfigMap or Secret that the app expects
- Wrong command or entrypoint
- Database/dependency not ready
- Insufficient memory (OOMKilled)

**Fix:** Check `kubectl logs --previous` for the crash output. Check events for OOMKilled.

### Pending
Pod can't be scheduled. Causes:
- Insufficient CPU/memory on nodes
- PVC can't bind (wrong StorageClass)
- Node affinity/anti-affinity can't be satisfied
- Taints preventing scheduling

**Fix:** Run `kubectl describe pod` and look at the Events section for the scheduling failure reason.

### CreateContainerConfigError
Container can't start because a referenced ConfigMap or Secret doesn't exist.

**Fix:** Check what ConfigMaps/Secrets the pod references and ensure they exist:
```bash
kubectl get configmaps -n <namespace> --context kind-sovereign-test
kubectl get secrets -n <namespace> --context kind-sovereign-test
```

## Resource Availability

```bash
# Node resource usage (requires metrics-server)
kubectl top nodes --context kind-sovereign-test

# Pod resource usage
kubectl top pods -A --context kind-sovereign-test

# Node capacity and allocatable
kubectl describe nodes --context kind-sovereign-test | grep -A 5 "Allocated resources"
```

Kind nodes share the host machine's resources. If pods are Pending due to resources,
reduce `resources.requests` in chart values (not `resources.limits`).

## CRD Readiness

Some components (OPA Gatekeeper, cert-manager) need CRDs to be Established before
resources that use them can be created.

```bash
# Check CRD status
kubectl get crd --context kind-sovereign-test | grep <pattern>

# Wait for a specific CRD
kubectl wait --for=condition=Established crd/<crd-name> \
  --context kind-sovereign-test --timeout=60s
```

## Stuck Helm Releases

If helm shows a release in `pending-install` or `pending-upgrade`:

```bash
# Check current state
helm status <release> -n <namespace> --kube-context kind-sovereign-test
helm history <release> -n <namespace> --kube-context kind-sovereign-test

# Rollback to last good state
helm rollback <release> 0 -n <namespace> --kube-context kind-sovereign-test

# Nuclear: uninstall and reinstall
helm uninstall <release> -n <namespace> --kube-context kind-sovereign-test
# Then re-run helm upgrade --install
```

## Namespace Issues

```bash
# Check if namespace exists
kubectl get namespace <ns> --context kind-sovereign-test

# Create if missing (helm --create-namespace also does this)
kubectl create namespace <ns> --context kind-sovereign-test
```

## Network Debugging

```bash
# Check if a service is reachable from within the cluster
kubectl run tmp-debug --rm -i --restart=Never \
  --image=busybox --context kind-sovereign-test \
  -- wget -qO- http://<service>.<namespace>.svc:port/health

# Check DNS resolution
kubectl run tmp-debug --rm -i --restart=Never \
  --image=busybox --context kind-sovereign-test \
  -- nslookup <service>.<namespace>.svc
```

## When Nothing Else Works

If a component has been failing for 3+ cycles with the same error despite different
fix approaches:
1. Check if it's a known kind incompatibility (see kind.md skill)
2. Consider disabling for kind: `--set <component>.enabled=false`
3. Document the reason in the changelog
4. Move on to the next layer
