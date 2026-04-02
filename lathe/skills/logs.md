# Log Reading and Debugging

## Pod Logs

```bash
# Tail recent logs from a specific pod
kubectl logs -n <namespace> <pod-name> --context kind-sovereign-test --tail=50

# Logs from a specific container (multi-container pods)
kubectl logs -n <namespace> <pod-name> -c <container> --context kind-sovereign-test --tail=50

# Previous container logs (after a crash)
kubectl logs -n <namespace> <pod-name> --previous --context kind-sovereign-test --tail=50

# Follow logs live
kubectl logs -n <namespace> <pod-name> --context kind-sovereign-test -f
```

## Events

Events are the first place to look for scheduling failures, pull errors, and crash reasons:

```bash
# All events, most recent last
kubectl get events -A --sort-by='.lastTimestamp' --context kind-sovereign-test | tail -30

# Events for a specific namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp' --context kind-sovereign-test

# Events for a specific pod
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name> \
  --context kind-sovereign-test
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
helm status <release> -n <namespace> --kube-context kind-sovereign-test

# See the helm history (shows failed upgrades)
helm history <release> -n <namespace> --kube-context kind-sovereign-test
```

## Aggregating Logs

To quickly see what's failing across the cluster:

```bash
# All non-Running pods with their status
kubectl get pods -A --context kind-sovereign-test --no-headers | grep -v -E 'Running|Completed'

# Quick scan of recent warnings
kubectl get events -A --context kind-sovereign-test --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -20
```
