#!/usr/bin/env bash
# lathe/fetch.sh — Process the download queue.
#
# Runs outside the loop. Pulls images, adds helm repos, downloads files.
# Marks entries as completed so they aren't re-processed.
#
# Usage:
#   ./lathe/fetch.sh           # process all pending downloads
#   ./lathe/fetch.sh --dry-run # show what would be done
#   ./lathe/fetch.sh --status  # show queue status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE="$SCRIPT_DIR/state/downloads.json"
CLUSTER_NAME="sovereign-test"

log() { echo "  [fetch] $*"; }

if [[ ! -f "$QUEUE" ]]; then
    echo "No downloads queued."
    exit 0
fi

cmd_status() {
    python3 -c "
import json, sys
q = json.load(open('$QUEUE'))
pending = [e for e in q if not e.get('done')]
done = [e for e in q if e.get('done')]
print(f'  Pending: {len(pending)}  Done: {len(done)}')
for e in pending:
    t = e.get('type', '?')
    src = e.get('source', e.get('url', e.get('name', '?')))
    reason = e.get('reason', '')
    cycle = e.get('added_by_cycle', '?')
    print(f'    [{t}] {src}  (cycle {cycle}: {reason})')
"
}

cmd_fetch() {
    local dry_run="${1:-false}"

    python3 -c "
import json, subprocess, sys

queue_path = '$QUEUE'
dry_run = '$dry_run' == 'true'
cluster = '$CLUSTER_NAME'
q = json.load(open(queue_path))
processed = 0

for i, entry in enumerate(q):
    if entry.get('done'):
        continue

    etype = entry.get('type', '')
    print(f'\\n  [{i+1}/{len(q)}] {etype}: {entry.get(\"source\", entry.get(\"url\", entry.get(\"name\", \"?\")))}')

    if dry_run:
        print('    (dry run — skipping)')
        continue

    try:
        if etype == 'image':
            source = entry['source']
            tag_as = entry.get('tag_as', '')

            # Pull (single-platform to avoid kind load digest issues with multi-arch)
            import platform as plat
            arch = 'arm64' if plat.machine() == 'arm64' else 'amd64'
            print(f'    Pulling {source} (linux/{arch}) ...')
            subprocess.run(['docker', 'pull', '--platform', f'linux/{arch}', source], check=True)

            # Re-tag if needed
            if tag_as:
                print(f'    Tagging as {tag_as} ...')
                subprocess.run(['docker', 'tag', source, tag_as], check=True)

            # Always load into kind via archive (avoids content digest mismatches)
            load_image = tag_as if tag_as else source
            print(f'    Loading {load_image} into kind ...')
            import tempfile, os
            with tempfile.NamedTemporaryFile(suffix='.tar', delete=False) as tf:
                tar_path = tf.name
            try:
                subprocess.run(['docker', 'save', load_image, '-o', tar_path], check=True)
                subprocess.run(['kind', 'load', 'image-archive', tar_path, '--name', cluster], check=True)
            finally:
                if os.path.exists(tar_path):
                    os.unlink(tar_path)

            entry['done'] = True
            entry['result'] = 'ok'
            processed += 1

        elif etype == 'helm_repo':
            name = entry['name']
            url = entry['url']
            print(f'    Adding helm repo {name} = {url} ...')
            subprocess.run(['helm', 'repo', 'add', name, url], check=False)
            subprocess.run(['helm', 'repo', 'update', name], check=True)
            entry['done'] = True
            entry['result'] = 'ok'
            processed += 1

        elif etype == 'file':
            url = entry['url']
            dest = entry['dest']
            print(f'    Downloading {url} → {dest} ...')
            subprocess.run(['curl', '-fsSL', '-o', dest, url], check=True)
            entry['done'] = True
            entry['result'] = 'ok'
            processed += 1

        else:
            print(f'    Unknown type: {etype} — skipping')

    except subprocess.CalledProcessError as e:
        print(f'    FAILED: {e}')
        entry['result'] = f'failed: {e}'

# Write back
json.dump(q, open(queue_path, 'w'), indent=2)
print(f'\\n  Done. Processed {processed} entries.')
"
}

case "${1:-fetch}" in
    --status) cmd_status ;;
    --dry-run) cmd_fetch true ;;
    fetch|"") cmd_fetch false ;;
    *)
        echo "Usage: $0 [--status | --dry-run]"
        exit 1
        ;;
esac
