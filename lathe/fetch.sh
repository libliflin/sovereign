#!/usr/bin/env bash
# lathe/fetch.sh — Process the download queue.
#
# Pulls images, imports into Lima k3s nodes, adds helm repos, downloads files.
# Marks entries as completed so they aren't re-processed.
#
# Usage:
#   ./lathe/fetch.sh           # process all pending downloads
#   ./lathe/fetch.sh --dry-run # show what would be done
#   ./lathe/fetch.sh --status  # show queue status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE="$SCRIPT_DIR/state/downloads.json"
VM_NODES=("sovereign-0" "sovereign-1" "sovereign-2")

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
import json, subprocess, sys, tempfile, os, platform as plat

queue_path = '$QUEUE'
dry_run = '$dry_run' == 'true'
vm_nodes = $( printf '['; for n in "${VM_NODES[@]}"; do printf '"%s",' "$n"; done | sed 's/,$//' ; printf ']' )
q = json.load(open(queue_path))
processed = 0

# Detect platform for single-arch pull
arch = 'arm64' if plat.machine() == 'arm64' else 'amd64'

# Find running Lima VMs
running_vms = []
for vm in vm_nodes:
    try:
        r = subprocess.run(['limactl', 'list', vm, '--format', '{{.Status}}'],
                           capture_output=True, text=True)
        if 'Running' in r.stdout:
            running_vms.append(vm)
    except Exception:
        pass

if not running_vms and not dry_run:
    print('  WARN: No running Lima VMs found. Image imports will be skipped.')

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

            # Pull single-platform to avoid multi-arch issues
            print(f'    Pulling {source} (linux/{arch}) ...')
            subprocess.run(['docker', 'pull', '--platform', f'linux/{arch}', source], check=True)

            # Re-tag if needed
            if tag_as:
                print(f'    Tagging as {tag_as} ...')
                subprocess.run(['docker', 'tag', source, tag_as], check=True)

            # Save to tar and import into each running Lima VM
            load_image = tag_as if tag_as else source
            with tempfile.NamedTemporaryFile(suffix='.tar', delete=False) as tf:
                tar_path = tf.name
            try:
                print(f'    Saving {load_image} to tar ...')
                subprocess.run(['docker', 'save', load_image, '-o', tar_path], check=True)

                for vm in running_vms:
                    print(f'    Importing into {vm} ...')
                    remote_path = f'/tmp/{os.path.basename(tar_path)}'
                    subprocess.run(['limactl', 'copy', tar_path, f'{vm}:{remote_path}'], check=True)
                    subprocess.run(['limactl', 'shell', vm, 'sudo', 'k3s', 'ctr', 'images', 'import', remote_path], check=True)
                    subprocess.run(['limactl', 'shell', vm, 'rm', '-f', remote_path], check=True)
            finally:
                if os.path.exists(tar_path):
                    os.unlink(tar_path)

            entry['done'] = True
            entry['result'] = f'ok — imported into {len(running_vms)} nodes'
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
            print(f'    Downloading {url} -> {dest} ...')
            subprocess.run(['curl', '-fsSL', '-o', dest, '--max-time', '60', url], check=True)
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
