# Changelog — Cycle 21

## Observed

- Layer: 2 (internal registry — autarky boundary)
- Service: Zot — pull-through proxy configured (cycle 20) but k3s nodes had no mirror configuration; all pulls still went directly to external registries
- Category: CONFIG_ERROR — `/etc/rancher/k3s/registries.yaml` absent on all 3 nodes; containerd had no instruction to route through Zot
- Evidence: Cycle 20 expected next: "configure k3s registry mirrors on all 3 nodes"; ClusterIP 10.43.32.173:5000 confirmed reachable from node level

## Applied

- Wrote `/etc/rancher/k3s/registries.yaml` to sovereign-0, sovereign-1, sovereign-2 — mirrors all 5 external registries (`docker.io`, `ghcr.io`, `quay.io`, `gcr.io`, `registry.k8s.io`) to `http://10.43.32.173:5000` (Zot ClusterIP)
- Restarted k3s-agent on sovereign-1, sovereign-2; restarted k3s on sovereign-0
- Files: `/etc/rancher/k3s/registries.yaml` on each node (runtime config, not in repo)

## Validated

```
# All nodes Ready after restart
kubectl wait --for=condition=Ready node/lima-sovereign-0 node/lima-sovereign-1 node/lima-sovereign-2
→ node/lima-sovereign-0 condition met
→ node/lima-sovereign-1 condition met
→ node/lima-sovereign-2 condition met

# Test pull: ghcr.io image on sovereign-2 (not previously present)
kubectl run zot-mirror-test --image=ghcr.io/project-zot/zot-linux-amd64:v2.1.1 ...
→ Successfully pulled image in 3.927s

# Zot logs confirm mirror routing (ns=ghcr.io parameter on all blob requests)
→ GET /v2/project-zot/zot-linux-amd64/manifests/v2.1.1?ns=ghcr.io  200
→ GET /v2/project-zot/zot-linux-amd64/blobs/sha256:...?ns=ghcr.io  200 (×14 blobs)

# Autarky gate
grep -rn "docker.io|quay.io|ghcr.io|gcr.io|registry.k8s.io" platform/charts/*/templates/
→ PASS
```

## Expect Next Cycle

Layer 2 autarky boundary is now complete: Zot is a pull-through proxy AND k3s nodes route all external pulls through it. Next cycle: install the first Layer 3 component — **Keycloak** (identity / SSO). Check the Keycloak chart in `platform/charts/keycloak/` and deploy it.
