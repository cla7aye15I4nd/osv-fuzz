#!/bin/bash
# Download native (non-oss-fuzz) lost-bug PoC seeds from R2.
# These live under the `native-seeds/<project>/` prefix (namespaced so they do
# not collide with oss-fuzz project names like radare2/file/lua).
set -euo pipefail

PROJECT="${1:?Usage: download_native_seeds.sh <project> [dest]}"
DEST="${2:-seeds/${PROJECT}}"
BUCKET="${R2_BUCKET:-osv-fuzz-seeds}"
PREFIX="native-seeds/${PROJECT}/"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

mkdir -p "$DEST"

if [ -z "$API_TOKEN" ] || [ -z "$ACCOUNT_ID" ]; then
    echo "[!] CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID not set — skipping seed download"
    echo "[+] Downloaded 0 seeds to $DEST"
    exit 0
fi

echo "[+] Downloading native seeds for $PROJECT from R2 ($PREFIX)..."
seed_count=0

objects=$(curl -sf -H "Authorization: Bearer $API_TOKEN" \
    "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/r2/buckets/$BUCKET/objects?prefix=${PREFIX}&limit=1000" 2>/dev/null) || {
    echo "[!] Failed to list seeds from R2 — check API token permissions"
    echo "[+] Downloaded 0 seeds to $DEST"
    exit 0
}

for key in $(echo "$objects" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for obj in data.get('result', []):
    k = obj['key']
    if k.endswith('.bin'):
        print(k)
" 2>/dev/null); do
    filename=$(basename "$key")
    if npx wrangler r2 object get "$BUCKET/$key" --remote --file "$DEST/$filename" 2>/dev/null; then
        seed_count=$((seed_count + 1))
    fi
done

echo "[+] Downloaded $seed_count native seeds to $DEST"
