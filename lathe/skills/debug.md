# Debugging Kubernetes Issues

## Pod Diagnosis

```bash
# Full pod details (scheduling, conditions, events, volumes)
timeout 10 kubectl describe pod -n <namespace> <pod-name>

# Quick status of all pods in a namespace
timeout 10 kubectl get pods -n <namespace> -o wide
```

## Common Failure Modes

### ImagePullBackOff
Image can't be pulled. Causes:
- Wrong image name or tag
- Registry unreachable from nodes
- Image not imported into k3s nodes (pre-Harbor)

**Fix:** Check the image reference in helm values. Pre-Harbor: queue the image in
downloads.json. Post-Harbor: ensure the image is in Harbor and nodes can reach it.
Never point templates at external registries.

### CrashLoopBackOff
Container starts and immediately exits. Causes:
- Missing ConfigMap or Secret
- Wrong command or entrypoint
- Database/dependency not ready
- Insufficient memory (OOMKilled)

**Fix:** Check `kubectl logs --previous` for crash output. Check events for OOMKilled.

### Pending
Pod can't be scheduled. Causes:
- Insufficient CPU/memory on nodes
- PVC can't bind (wrong StorageClass)
- Anti-affinity can't be satisfied
- Taints preventing scheduling

**Fix:** `kubectl describe pod` — Events section shows scheduling failure reason.

### CreateContainerConfigError
Referenced ConfigMap or Secret doesn't exist.

**Fix:**
```bash
timeout 10 kubectl get configmaps -n <namespace>
timeout 10 kubectl get secrets -n <namespace>
```

## Resource Availability

```bash
# Node resource usage
timeout 10 kubectl top nodes

# Pod resource usage
timeout 10 kubectl top pods -A

# Node capacity
timeout 10 kubectl describe nodes | grep -A 5 "Allocated resources"
```

Lima VMs have dedicated resources (CPU/memory configured at creation). If pods are
Pending, either reduce resource requests or increase VM resources.

## CRD Readiness

```bash
# Check CRD status
timeout 10 kubectl get crd | grep <pattern>

# Wait for a specific CRD
timeout 30 kubectl wait --for=condition=Established crd/<crd-name> --timeout=60s
```

## VM-Level Debugging

When k8s-level debugging isn't enough, check the node directly:

```bash
# k3s service status
limactl shell sovereign-0 systemctl status k3s

# k3s logs
limactl shell sovereign-0 journalctl -u k3s --tail=30

# Agent node logs
limactl shell sovereign-1 journalctl -u k3s-agent --tail=30

# containerd images on a node
limactl shell sovereign-0 sudo k3s ctr images list | grep <image>

# Disk usage
limactl shell sovereign-0 df -h
```

## Stuck Helm Releases

```bash
helm status <release> -n <namespace>
helm history <release> -n <namespace>
helm rollback <release> 0 -n <namespace>

# Nuclear: uninstall and reinstall
helm uninstall <release> -n <namespace>
```

## Network Debugging

```bash
# Check service reachability from inside cluster
timeout 10 kubectl run tmp-debug --rm -i --restart=Never \
  --image=busybox -- wget -qO- http://<service>.<namespace>.svc:port/health

# DNS resolution
timeout 10 kubectl run tmp-debug --rm -i --restart=Never \
  --image=busybox -- nslookup <service>.<namespace>.svc
```

## When Nothing Else Works

If a component fails 3+ cycles with the same error:
1. Check if it's a known limitation (see lima.md skill)
2. Consider disabling: `--set <component>.enabled=false`
3. Document the reason in changelog
4. Move on to the next layer
