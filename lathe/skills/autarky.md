# Autarky — Internal Registry and Image Management

## Principle

After Harbor (Layer 2) is running, the cluster never pulls from external registries.
All images are served from `harbor.sovereign.local/sovereign/` (or the configured domain).

## Bootstrap Window

Before Harbor is deployed, Layers 0-1 may pull from upstream. This is the
"bootstrap window" — it closes once Harbor is healthy.

## Image Seeding for Kind

Kind nodes can't pull from localhost registries. Images must be loaded via kind commands.

### Loading from Docker

```bash
# Pull on host, then load into kind
docker pull <image:tag>
kind load docker-image <image:tag> --name sovereign-test
```

### Loading via Archive

```bash
# Save from docker, load into kind
docker save <image:tag> -o /tmp/image.tar
kind load image-archive /tmp/image.tar --name sovereign-test
```

### Bitnami Images

Bitnami migrated from docker.io/bitnami to a new structure. Pinned version tags
remain at `docker.io/bitnamilegacy/`:

```bash
# Pull pinned tag from bitnamilegacy
docker pull bitnamilegacy/keycloak:24.0.5-debian-12-r8

# Tag for harbor namespace
docker tag bitnamilegacy/keycloak:24.0.5-debian-12-r8 \
  harbor.sovereign.local/bitnami/keycloak:24.0.5-debian-12-r8

# Load into kind
kind load docker-image harbor.sovereign.local/bitnami/keycloak:24.0.5-debian-12-r8 \
  --name sovereign-test
```

### Known Images to Seed

These images are needed by platform charts and must be pre-loaded into kind:

| Image | Source | Tag |
|-------|--------|-----|
| keycloak | bitnamilegacy | 24.0.5-debian-12-r8 |
| postgresql | bitnamilegacy | 16.3.0-debian-12-r14 (tag as :16) |
| redis | bitnamilegacy | 6.2.7-debian-11-r11 |
| redis-exporter | bitnamilegacy | 1.43.0-debian-11-r4 |
| thanos | bitnamilegacy | 0.36.0-debian-12-r1 |
| falcoctl | falcosecurity | 0.12.2 |

## Harbor DNS in Kind

Kind nodes use Docker's bridge DNS which doesn't know about harbor.sovereign.local.
After Harbor is deployed, inject its service IP into kind node /etc/hosts:

```bash
HARBOR_IP=$(kubectl get svc harbor -n harbor --context kind-sovereign-test \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
for node in $(kind get nodes --name sovereign-test); do
    docker exec "$node" bash -c \
      "grep -q 'harbor.sovereign.local' /etc/hosts || echo '$HARBOR_IP harbor.sovereign.local' >> /etc/hosts"
done
```

Also configure containerd to trust Harbor's self-signed cert:
```bash
for node in $(kind get nodes --name sovereign-test); do
    docker exec "$node" mkdir -p /etc/containerd/certs.d/harbor.sovereign.local
    docker exec "$node" bash -c 'cat > /etc/containerd/certs.d/harbor.sovereign.local/hosts.toml <<EOF
server = "http://harbor.sovereign.local"
[host."http://harbor.sovereign.local"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF'
done
```

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

Never hardcode a registry URL in a template file.
