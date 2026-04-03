# Autarky — Internal Registry and Image Management

## Principle

After Zot (Layer 2) is running, the cluster never pulls from external registries.
Zot acts as a pull-through proxy + cache — upstream images are fetched on demand
and cached locally. All chart image references go through Zot.

Chart templates NEVER contain external registry URLs. This is constitutional gate G6.

## Zot as Layer 2

Zot replaces Harbor. Harbor is amd64-only and cannot run on arm64 Lima VMs.
This is a permanent decision (see decisions.md D1). Never install Harbor.

Zot provides:
- OCI v2 registry API (same as Harbor, Docker Hub, etc.)
- Pull-through proxy with `sync.onDemand: true` for docker.io, ghcr.io, quay.io, gcr.io, registry.k8s.io
- Single binary, no database, no redis
- CNCF Sandbox, Apache 2.0, multi-arch (arm64 native)

## Bootstrap Window

Before Zot is deployed, Layers 0-1 may pull from upstream (k3s handles this
natively). The bootstrap window closes once Zot is healthy and k3s registry
mirrors are configured.

## Image Loading for Pre-Zot Bootstrap

For images needed before Zot is running, queue them in `lathe/state/downloads.json`
(see downloads skill). The fetch script pulls them on the host or directly on
nodes and imports via `k3s ctr images import`.

Once Zot is running with pull-through proxy, k3s pulls through Zot automatically —
no manual image loading needed. This is the target state.

## k3s Registry Mirror Setup

k3s nodes route all image pulls through Zot via `/etc/rancher/k3s/registries.yaml`:

```yaml
mirrors:
  "docker.io":
    endpoint:
      - "http://<zot-clusterip>:5000"
  "ghcr.io":
    endpoint:
      - "http://<zot-clusterip>:5000"
  "quay.io":
    endpoint:
      - "http://<zot-clusterip>:5000"
  "gcr.io":
    endpoint:
      - "http://<zot-clusterip>:5000"
  "registry.k8s.io":
    endpoint:
      - "http://<zot-clusterip>:5000"
```

After writing this config, restart k3s on each node for it to take effect.

## Bitnami Images

Bitnami migrated from docker.io/bitnami. Pinned version tags remain at
`docker.io/bitnamilegacy/`. Queue these in downloads.json with the correct
`tag_as` so they appear as `docker.io/bitnami/<name>:<tag>` when imported.

Zot's pull-through proxy will NOT find these at docker.io/bitnami (they're gone).
They must be manually pulled from bitnamilegacy and re-tagged.

## Autarky Gate

No external registry URLs in chart templates:

```bash
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "FAIL: external registry reference found" || echo "PASS"
```

## Chart Image References

All charts must use the global image registry value:

```yaml
image:
  registry: "{{ .Values.global.imageRegistry }}"
  repository: "<component>"
  tag: "<version>"
```

Never hardcode a registry URL in a template file. If an image isn't available
through Zot's proxy, queue it in downloads.json — never point the template externally.
