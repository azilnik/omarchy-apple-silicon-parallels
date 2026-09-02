#!/bin/bash
# build/package.sh — clone the builder VM, sysprep the CLONE, compact, strip identity, zip.
#
# Fully headless on any edition where prlctl clone/start/stop/unregister are available
# (verified on Parallels Desktop 27 trial). No GUI dialogs: `prlctl clone` mints a fresh
# UUID + MAC with no "duplicate MAC" prompt, `prlctl start` boots with no Play button.
# The daily builder VM is never modified — we operate only on the clone.
#
# Usage: build/package.sh <version>        e.g. build/package.sh 0.1.0

set -euo pipefail
VERSION=${1:?usage: package.sh <version>}
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HOME/Parallels/Omarchy.pvm"
WORK="$HOME/Parallels/omarchy-parallels-build"
OUT="$REPO/dist"
CLONE_NAME="Omarchy-image"

[[ -d $SRC ]] || { echo "package: builder VM not found at $SRC" >&2; exit 1; }
if prlctl list --no-header 2>/dev/null | grep -q .; then
  echo "package: stop all running VMs first (need a consistent clone + unambiguous leases)" >&2; exit 1
fi

# Clean any leftover clone from a previous run (registered or on disk).
prlctl stop "$CLONE_NAME" --kill >/dev/null 2>&1 || true
prlctl unregister "$CLONE_NAME" >/dev/null 2>&1 || true
rm -rf "$WORK"; mkdir -p "$WORK" "$OUT"

echo "==> [1/6] cloning builder VM (fresh UUID + MAC, headless)"
prlctl clone "Omarchy" --name "$CLONE_NAME" >/dev/null
CLONE_HOME=$(prlctl list -i "$CLONE_NAME" | awk -F': ' '/^Home:/{print $2; exit}' | sed 's/[[:space:]]*$//')
[[ -d $CLONE_HOME ]] || { echo "package: clone home not found ($CLONE_HOME)" >&2; exit 1; }
CLONE_UUID=$(prlctl list -i "$CLONE_NAME" | awk -F'[{}]' '/^ID:/{print $2; exit}')
CLONE_MAC=$(prlctl list -i "$CLONE_NAME" | grep -oiE 'mac=[0-9A-Fa-f]{12}' | head -1 | cut -d= -f2 | tr 'A-F' 'a-f')
echo "    clone name=$CLONE_NAME uuid={$CLONE_UUID} mac=$CLONE_MAC"
echo "    home=$CLONE_HOME"

echo "==> [2/6] booting the clone + waiting for SSH (headless)"
prlctl start "$CLONE_NAME" >/dev/null
export VM_MAC="$CLONE_MAC"
for _ in $(seq 1 72); do "$REPO/build/vm-ssh" 'echo up' >/dev/null 2>&1 && break; sleep 5; done
"$REPO/build/vm-ssh" 'echo up' >/dev/null || { echo "package: clone SSH never came up" >&2; exit 1; }

echo "==> [3/6] sysprepping the clone (over SSH; guest powers off at the end)"
OMARCHY_SYSPREP_CONFIRM=yes OMARCHY_SSH="$REPO/build/vm-ssh" "$REPO/build/sysprep.sh"

echo "==> [4/6] waiting for clone to power off, then compacting"
for _ in $(seq 1 120); do
  prlctl list -a --no-header 2>/dev/null | grep -q "{$CLONE_UUID}.*stopped" && break; sleep 5
done
prlctl list -a --no-header 2>/dev/null | grep -q "{$CLONE_UUID}.*stopped" \
  || { prlctl stop "$CLONE_NAME" --kill >/dev/null 2>&1 || true; sleep 5; }
HDD=$(find "$CLONE_HOME" -maxdepth 1 -name '*.hdd' | head -1)
prl_disk_tool compact --hdd "$HDD" || echo "    (compact reported an issue — continuing)"

echo "==> [5/6] unregistering clone + stripping per-machine identity"
prlctl unregister "$CLONE_NAME" >/dev/null
python3 - "$CLONE_HOME/config.pvs" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'<SourceVmUuid>\{[^}]*\}</SourceVmUuid>', '<SourceVmUuid></SourceVmUuid>', s)
s = re.sub(r'<MAC>[0-9A-Fa-f]{12}</MAC>', '<MAC></MAC>', s)
s = s.replace('<VmName>Omarchy-image</VmName>', '<VmName>Omarchy</VmName>')
open(p, 'w').write(s)
print("    stripped SourceVmUuid + MAC, reset VmName -> Omarchy")
PY
# Move the bundle into the build workdir under its shipped name.
mv "$CLONE_HOME" "$WORK/Omarchy.pvm"

echo "==> [6/6] packaging"
ZIP="$OUT/omarchy-apple-silicon-parallels-v$VERSION.zip"
rm -f "$ZIP"
( cd "$WORK" && zip -qry "$ZIP" Omarchy.pvm )
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
if command -v minisign >/dev/null && [[ -n ${MINISIGN_KEY:-} ]]; then
  minisign -Sm "$ZIP" -s "$MINISIGN_KEY" -t "omarchy-parallels v$VERSION"
  echo "==> signed: $ZIP.minisig"
else
  echo "==> NOTE: unsigned (set MINISIGN_KEY to sign)"
fi
echo "==> done: $ZIP ($(du -h "$ZIP" | cut -f1))"
