# Download Manager

## Rule

**Never download, pull, or transfer images inside the agent cycle.** No `docker pull`,
no `docker save`, no `ctr import`, no `curl` for large files. These block the
cycle and defeat the 5-minute budget.

Instead, write what you need to `lathe/state/downloads.json`. The fetch script
(`lathe/fetch.sh`) runs automatically at the start of each cycle, before the
snapshot is collected. Downloads from cycle N are available in cycle N+1.

## Writing a Download Request

Append to `lathe/state/downloads.json`. The file is a JSON array of requests:

```json
[
  {
    "type": "image",
    "source": "docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r8",
    "tag_as": "harbor.sovereign.local/bitnami/keycloak:24.0.5-debian-12-r8",
    "reason": "keycloak chart needs bitnami keycloak image",
    "added_by_cycle": 3
  },
  {
    "type": "helm_repo",
    "name": "bitnami",
    "url": "https://charts.bitnami.com/bitnami",
    "reason": "needed for minio chart dependency",
    "added_by_cycle": 5
  },
  {
    "type": "file",
    "url": "https://example.com/some-config.tar.gz",
    "dest": "platform/vendor/some-config/",
    "reason": "vendor recipe source archive",
    "added_by_cycle": 7
  }
]
```

## Request Types

### `image`
Container image to pull on the host, optionally re-tag, and import into all
Lima k3s nodes.

| Field | Required | Description |
|-------|----------|-------------|
| `source` | yes | Full image reference to pull |
| `tag_as` | no | Re-tag before importing (e.g., `harbor.sovereign.local/bitnami/...`) |
| `reason` | yes | Why this is needed (which chart, what error) |
| `added_by_cycle` | yes | Cycle number that requested it |

The fetch script pulls the image, re-tags if needed, saves to a tar, and imports
into every Lima node via `k3s ctr images import`.

### `helm_repo`
Helm repository to add.

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Repo name for `helm repo add` |
| `url` | yes | Repo URL |
| `reason` | yes | Why needed |
| `added_by_cycle` | yes | Cycle number |

### `file`
File to download via curl.

| Field | Required | Description |
|-------|----------|-------------|
| `url` | yes | URL to fetch |
| `dest` | yes | Local destination path |
| `reason` | yes | Why needed |
| `added_by_cycle` | yes | Cycle number |

## How to Add Requests

Read the existing file (or start with `[]`), append your entries, write it back:

```bash
if [[ ! -f lathe/state/downloads.json ]]; then
    echo '[]' > lathe/state/downloads.json
fi
```

## In Your Changelog

When you add download requests, note them:

```markdown
## Downloads Queued
- image: bitnamilegacy/keycloak:24.0.5-debian-12-r8 → k3s nodes (keycloak needs it)
```
