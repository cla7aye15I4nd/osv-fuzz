#!/bin/bash
set -euo pipefail

PROJECT="${1:?Usage: download_seeds.sh <project>}"
DEST="${2:-seeds/${PROJECT}}"
BUCKET="${R2_BUCKET:-osv-fuzz-seeds}"

mkdir -p "$DEST"

echo "[+] Downloading seeds for $PROJECT from R2 bucket $BUCKET..."

# Download manifest first
npx wrangler r2 object get "$BUCKET/seeds/${PROJECT}/manifest.json" \
    --remote --file "$DEST/manifest.json" 2>/dev/null

# Parse manifest and download each seed
python3 -c "
import json, subprocess, sys
manifest = json.load(open('$DEST/manifest.json'))
seeds = [s for s in manifest.get('seeds', []) if s.get('poc_downloaded')]
print(f'[+] Manifest has {len(seeds)} seeds with POC')
for s in seeds:
    osv_id = s['osv_id']
    filename = f'{osv_id}.bin'
    dest = '$DEST/' + filename
    key = '$BUCKET/seeds/$PROJECT/' + filename
    result = subprocess.run(
        ['npx', 'wrangler', 'r2', 'object', 'get', key, '--remote', '--file', dest],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f'  Downloaded {filename}')
    else:
        print(f'  Failed: {filename}', file=sys.stderr)
"

seed_count=$(find "$DEST" -name "*.bin" -type f 2>/dev/null | wc -l)
echo "[+] Downloaded $seed_count seeds to $DEST"
