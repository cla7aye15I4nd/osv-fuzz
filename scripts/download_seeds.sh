#!/bin/bash
# Download a project's PoC seeds from R2 (seeds/<project>/<id>.bin) via the S3 API.
#
# Uses `aws s3 sync` against R2's S3 endpoint — one bulk, parallel transfer that
# scales to hundreds of concurrent CI jobs (unlike the Cloudflare REST API, which
# rate-limits the whole account). Credentials come from the environment:
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY  (R2 S3 token, from repo secrets)
#   R2_S3_ENDPOINT (optional; defaults to this account's endpoint)
set -uo pipefail

PROJECT="${1:?Usage: download_seeds.sh <project> [dest]}"
DEST="${2:-seeds/${PROJECT}}"
BUCKET="${R2_BUCKET:-osv-fuzz-seeds}"
ENDPOINT="${R2_S3_ENDPOINT:-https://168a3590e273619898344706b02f2311.r2.cloudflarestorage.com}"

mkdir -p "$DEST"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "[!] R2 S3 credentials not set (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY) — skipping seed download"
    echo "[+] Downloaded 0 seeds to $DEST"
    exit 0
fi

echo "[+] Syncing seeds for $PROJECT from R2 (s3://$BUCKET/seeds/$PROJECT/)..."
AWS_EC2_METADATA_DISABLED=true \
aws s3 sync "s3://${BUCKET}/seeds/${PROJECT}/" "$DEST/" \
    --endpoint-url "$ENDPOINT" --region auto --only-show-errors || {
    echo "[!] aws s3 sync failed"; }

count=$(find "$DEST" -name '*.bin' -type f 2>/dev/null | wc -l)
echo "[+] Downloaded $count seeds to $DEST"
