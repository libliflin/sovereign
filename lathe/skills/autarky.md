# Autarky — Internal Registry and Image Management

## Principle

After Harbor (Layer 2) is running, the cluster never pulls from external registries.
All images are served from `harbor.<domain>/sovereign/` (or the configured registry).

Chart templates NEVER contain external registry URLs. This is constitutional gate G6.

## Bootstrap Window

Before Harbor is deployed, Layers 0-1 may pull from upstream (k3s handles this
natively — no special loading needed). The bootstrap window closes once Harbor is
healthy and image mirroring is configured.

## Image Loading for Lima + k3s

k3s uses containerd. Images can be imported directly into each node:

```bash
# Import a tar archive into a node
limactl copy image.tar sovereign-0:/tmp/image.tar
limactl shell sovereign-0 sudo k3s ctr images import /tmp/image.tar
```

For pre-Harbor bootstrap, queue images in `lathe/state/downloads.json` (see
downloads skill). The fetch script pulls them on the host and imports into all
nodes.

Once Harbor is running, k3s pulls from Harbor like any normal registry — no
special import needed. This is the target state.

## Harbor Setup

Harbor runs inside the cluster. k3s nodes need to trust it:

```bash
# On each node, configure k3s registries
limactl shell sovereign-0 sudo tee /etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  "harbor.sovereign.local":
    endpoint:
      - "http://harbor.sovereign.local"
configs:
  "harbor.sovereign.local":
    tls:
      insecure_skip_verify: true
EOF
limactl shell sovereign-0 sudo systemctl restart k3s
```

k3s natively supports registry mirrors via `/etc/rancher/k3s/registries.yaml` —
no containerd certs.d hacking needed.

## Bitnami Images

Bitnami migrated from docker.io/bitnami. Pinned version tags remain at
`docker.io/bitnamilegacy/`. Queue these in downloads.json with the correct
`tag_as` for the harbor namespace.

## Autarky Gate

No external registry URLs in chart templates:

```bash
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" \
  platform/charts/*/templates/ && echo "FAIL: external registry reference found" || echo "PASS"
```

If this gate fails, the reference must be replaced with `{{ .Values.global.imageRegistry }}`.

## Chart Image References

All charts must use the global image registry value:

```yaml
image:
  registry: "{{ .Values.global.imageRegistry }}"
  repository: "<component>"
  tag: "<version>"
```

Never hardcode a registry URL in a template file. If an image isn't available
internally, queue it in downloads.json — never point the template externally.
