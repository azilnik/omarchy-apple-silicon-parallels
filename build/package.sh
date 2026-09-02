#!/bin/bash
# build/package.sh — clone the builder VM, sysprep the CLONE, compact, strip identity, zip.
#
# Standard-edition safe end to end: Finder-level copy, `open` to register/boot,
# prl_disk_tool compact, file edits. The daily builder VM is never modified.
#
# Two manual clicks remain on Standard (no prlctl start): choosing "Copied" if Parallels
# asks, and pressing Play on the clone. The script prompts at exactly those moments.
#
# Usage: build/package.sh <version>        e.g. build/package.sh 0.1.0

set -euo pipefail
VERSION=${1:?usage: package.sh <version>}
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HOME/Parallels/Omarchy.pvm"
WORK="$HOME/Parallels/omarchy-parallels-build"
OUT="$REPO/dist"
CLONE="$WORK/Omarchy-image.pvm"

[[ -d $SRC ]] || { echo "package: builder VM not found at $SRC" >&2; exit 1; }
if prlctl list --no-header 2>/dev/null | grep -q .; then
  echo "package: stop all running VMs first (need a consistent clone + unambiguous leases)" >&2; exit 1
fi

echo "==> [1/6] cloning builder VM"
rm -rf "$WORK"; mkdir -p "$WORK" "$OUT"
cp -c -R "$SRC" "$CLONE" 2>/dev/null || cp -R "$SRC" "$CLONE"
# distinct name inside config so the registered clone is distinguishable from the builder
sed -i '' 's|<VmName>Omarchy</VmName>|<VmName>Omarchy-image</VmName>|' "$CLONE/config.pvs"
# Blank the MAC *before* registering so Parallels auto-assigns a fresh one silently — otherwise
# it pops a modal "Duplicate MAC addresses" dialog that has to be clicked by hand.
sed -i '' -E 's|<MAC>[0-9A-Fa-f]{12}</MAC>|<MAC></MAC>|' "$CLONE/config.pvs"

echo "==> [2/6] registering + booting the clone"
BEFORE=$(prlctl list -a --no-header 2>/dev/null | awk '{print $1}' | sort)
open "$CLONE"
echo "    (On the trial edition, dismiss the 'Continue Trial' nag if it appears, and press Play"
echo "     if the clone shows a Play button instead of booting.)"
NEW_UUID=""
for _ in $(seq 1 60); do
  sleep 5
  NEW_UUID=$(comm -13 <(echo "$BEFORE") <(prlctl list -a --no-header 2>/dev/null | awk '{print $1}' | sort) | head -1)
  [[ -n $NEW_UUID ]] && break
done
[[ -n $NEW_UUID ]] || { echo "package: clone never registered" >&2; exit 1; }
CLONE_MAC=$(grep -o '<MAC>[0-9A-Fa-f]*</MAC>' "$CLONE/config.pvs" | head -1 | sed -E 's/<\/?MAC>//g' | tr 'A-F' 'a-f')
echo "    clone uuid=$NEW_UUID mac=$CLONE_MAC"

echo "==> [3/6] waiting for clone SSH, then sysprepping the clone"
export VM_MAC="$CLONE_MAC"
for _ in $(seq 1 60); do "$REPO/build/vm-ssh" 'echo up' >/dev/null 2>&1 && break; sleep 5; done
"$REPO/build/vm-ssh" 'echo up' >/dev/null || { echo "package: clone SSH never came up (press Play?)" >&2; exit 1; }
OMARCHY_SYSPREP_CONFIRM=yes OMARCHY_SSH="$REPO/build/vm-ssh" "$REPO/build/sysprep.sh"

echo "==> [4/6] waiting for clone to power off, then compacting"
for _ in $(seq 1 120); do
  prlctl list -a --no-header 2>/dev/null | grep -q "^$NEW_UUID.*stopped" && break; sleep 10
done
prl_disk_tool compact --hdd "$CLONE/Omarchy-0.hdd"

echo "==> [5/6] unregistering clone + stripping per-machine identity"
prlctl unregister "$NEW_UUID" 2>/dev/null || echo "    (unregister needs Pro — remove 'Omarchy-image' from Parallels' list by hand later; harmless)"
python3 - "$CLONE/config.pvs" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'<SourceVmUuid>\{[^}]*\}</SourceVmUuid>', '<SourceVmUuid></SourceVmUuid>', s)
s = re.sub(r'<MAC>[0-9A-Fa-f]{12}</MAC>', '<MAC></MAC>', s)
open(p, 'w').write(s)
print("    stripped SourceVmUuid + MAC")
PY
mv "$CLONE" "$WORK/Omarchy.pvm"; CLONE="$WORK/Omarchy.pvm"
sed -i '' 's|<VmName>Omarchy-image</VmName>|<VmName>Omarchy</VmName>|' "$CLONE/config.pvs"

echo "==> [6/6] packaging"
ZIP="$OUT/omarchy-parallels-v$VERSION.zip"
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
