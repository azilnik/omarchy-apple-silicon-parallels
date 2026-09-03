#!/bin/bash
# build/release.sh — publish a packaged image to Cloudflare R2 and update the manifest.
#
# Needs: aws CLI configured with an R2 access key, or env AWS_ACCESS_KEY_ID/SECRET.
#   R2_ENDPOINT   https://<account-id>.r2.cloudflarestorage.com
#   R2_BUCKET     e.g. omarchy-apple-silicon-parallels
#   PUBLIC_BASE   e.g. https://dl.omarchy-apple-silicon.zilnik.me
#
# Usage: build/release.sh <version>

set -euo pipefail
VERSION=${1:?usage: release.sh <version>}
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="$REPO/dist/omarchy-apple-silicon-parallels-v$VERSION.zip"
: "${R2_ENDPOINT:?set R2_ENDPOINT}"; : "${R2_BUCKET:?set R2_BUCKET}"; : "${PUBLIC_BASE:?set PUBLIC_BASE}"

[[ -f $ZIP && -f $ZIP.sha256 ]] || { echo "release: run package.sh $VERSION first" >&2; exit 1; }
SHA=$(awk '{print $1}' "$ZIP.sha256")
SIZE=$(stat -f %z "$ZIP")
SIZE_H=$(du -h "$ZIP" | cut -f1 | tr -d ' ')
# omarchy version for the manifest. Only ssh the builder if it's actually running — a stopped VM
# leaves a stale DHCP lease, and ssh to that dead IP can hang past ConnectTimeout. Override with
# OMARCHY_VER=x.y.z to skip the fetch entirely (e.g. when packaging from a known image).
OMARCHY_VER="${OMARCHY_VER:-}"
if [[ -z $OMARCHY_VER ]]; then
  if prlctl list --no-header 2>/dev/null | grep -qi omarchy; then
    OMARCHY_VER=$("${OMARCHY_SSH:-$HOME/Parallels/omarchy-ssh}" 'cat /usr/share/omarchy/version' 2>/dev/null || echo unknown)
  else
    OMARCHY_VER=unknown
  fi
fi

echo "==> uploading v$VERSION ($SIZE_H) to r2://$R2_BUCKET"
aws s3 cp "$ZIP" "s3://$R2_BUCKET/omarchy-apple-silicon-parallels-v$VERSION.zip" --endpoint-url "$R2_ENDPOINT"
aws s3 cp "$ZIP.sha256" "s3://$R2_BUCKET/omarchy-apple-silicon-parallels-v$VERSION.zip.sha256" --endpoint-url "$R2_ENDPOINT"
[[ -f $ZIP.minisig ]] && aws s3 cp "$ZIP.minisig" "s3://$R2_BUCKET/omarchy-apple-silicon-parallels-v$VERSION.zip.minisig" --endpoint-url "$R2_ENDPOINT"

echo "==> writing latest.json"
cat > /tmp/latest.json <<EOF
{
  "version": "$VERSION",
  "url": "$PUBLIC_BASE/omarchy-apple-silicon-parallels-v$VERSION.zip",
  "sha256": "$SHA",
  "size": $SIZE,
  "size_human": "$SIZE_H",
  "omarchy_version": "$OMARCHY_VER",
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
aws s3 cp /tmp/latest.json "s3://$R2_BUCKET/latest.json" --endpoint-url "$R2_ENDPOINT" \
  --content-type application/json --cache-control "max-age=300"
aws s3 cp "$REPO/host/post-import.sh" "s3://$R2_BUCKET/post-import.sh" --endpoint-url "$R2_ENDPOINT" \
  --content-type text/x-shellscript --cache-control "max-age=300"

echo "==> tagging repo v$VERSION"
git -C "$REPO" tag -f "v$VERSION"
echo "==> released: $PUBLIC_BASE/omarchy-apple-silicon-parallels-v$VERSION.zip"
echo "    (push the tag when ready: git push origin v$VERSION)"
