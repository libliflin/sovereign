# Download Manager

## Rule

**Never download, pull, or transfer images inside the loop.** No `docker pull`,
no `docker save`, no `kind load`, no `curl` for large files. These block the
cycle and defeat the 5-minute budget.

Instead, write what you need to `lathe/state/downloads.json`. A separate script
(`lathe/fetch.sh`) runs the queue between cycles or on-demand.

## Writing a Download Request

Append to `lathe/state/downloads.json`. The file is a JSON array of requests:

```json
[
  {
    "type": "image",
    "source": "docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r8",
    "tag_as": "harbor.sovereign.local/bitnami/keycloak:24.0.5-debian-12-r8",
    "target": "kind",
    "reason": "keycloak chart needs bitnami keycloak image, not available in kind",
    "added_by_cycle": 3
  },
  {
    "type": "image",
    "source": "docker.io/bitnamilegacy/postgresql:16.3.0-debian-12-r14",
    "tag_as": "harbor.sovereign.local/bitnami/postgresql:16",
    "target": "kind",
    "reason": "keycloak depends on postgresql, tag :16 expected by chart",
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
Container image to pull, optionally re-tag, and load into kind.

| Field | Required | Description |
|-------|----------|-------------|
| `source` | yes | Full image reference to pull (e.g., `docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r8`) |
| `tag_as` | no | Re-tag to this before loading (e.g., `harbor.sovereign.local/bitnami/keycloak:...`) |
| `target` | yes | Where to load: `kind` (kind load) or `local` (just pull to docker) |
| `reason` | yes | Why this is needed (which chart, what error) |
| `added_by_cycle` | yes | Cycle number that requested it |

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

Read the existing file (or start with `[]`), append your entries, write it back.
The fetch script handles deduplication by `source`+`tag_as` for images.

```bash
# If the file doesn't exist, start fresh
if [[ ! -f lathe/state/downloads.json ]]; then
    echo '[]' > lathe/state/downloads.json
fi
```

Then use python3 or jq to append:
```bash
python3 -c "
import json
path = 'lathe/state/downloads.json'
q = json.load(open(path))
q.append({
    'type': 'image',
    'source': 'docker.io/bitnamilegacy/keycloak:24.0.5-debian-12-r8',
    'tag_as': 'harbor.sovereign.local/bitnami/keycloak:24.0.5-debian-12-r8',
    'target': 'kind',
    'reason': 'keycloak chart needs this image',
    'added_by_cycle': CYCLE_NUMBER
})
json.dump(q, open(path, 'w'), indent=2)
"
```

## What Happens Next

The human runs `./lathe/fetch.sh` (or it runs automatically between cycles).
It processes each entry, marks it done, and the next cycle's snapshot will
reflect the newly available images.

## In Your Changelog

When you add download requests, note them:

```markdown
## Downloads Queued
- image: bitnamilegacy/keycloak:24.0.5-debian-12-r8 → kind (keycloak needs it)
- image: bitnamilegacy/postgresql:16.3.0-debian-12-r14 → kind (keycloak db)
```

This makes it visible what the cycle is waiting on.
