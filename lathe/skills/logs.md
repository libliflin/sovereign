# Log Reading and Debugging

## Pod Logs

```bash
# Tail recent logs from a specific pod
timeout 10 kubectl logs -n <namespace> <pod-name> --tail=50

# Logs from a specific container (multi-container pods)
timeout 10 kubectl logs -n <namespace> <pod-name> -c <container> --tail=50

# Previous container logs (after a crash)
timeout 10 kubectl logs -n <namespace> <pod-name> --previous --tail=50

# Follow logs live
kubectl logs -n <namespace> <pod-name> -f
```

Note: KUBECONFIG is set by the loop from Lima. No `--context` needed.

## Events

Events are the first place to look for scheduling failures, pull errors, and crash reasons:

```bash
# All events, most recent last
timeout 10 kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Events for a specific namespace
timeout 10 kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Events for a specific pod
timeout 10 kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>
```

## Common Log Visibility Issues

**Container not started yet:**
- Logs will be empty. Check events instead.
- Look for: `FailedScheduling`, `FailedMount`, `ImagePullBackOff`

**Init container stuck:**
- Main container logs won't exist until all init containers complete.
- Check init container logs: `kubectl logs <pod> -c <init-container-name>`

**CrashLoopBackOff:**
- Container starts, crashes, restarts. Use `--previous` to see the crash output.
- Common causes: missing ConfigMap/Secret, wrong command, database not ready.

**OOMKilled:**
- Check events for `OOMKilled` reason.
- Fix: increase `resources.limits.memory` in chart values.

## Helm Install/Upgrade Output

When a helm upgrade fails, the error usually appears in:
1. The helm command's stderr (template rendering errors)
2. The events for the namespace (runtime failures)
3. The pod logs (application-level crashes)

Check in that order.

```bash
# See what helm thinks the release status is
timeout 10 helm status <release> -n <namespace>

# See the helm history (shows failed upgrades)
timeout 10 helm history <release> -n <namespace>
```

## Aggregating Logs

To quickly see what's failing across the cluster:

```bash
# All non-Running pods with their status
timeout 10 kubectl get pods -A --no-headers | grep -v -E 'Running|Completed'

# Quick scan of recent warnings
timeout 10 kubectl get events -A --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -20
```
