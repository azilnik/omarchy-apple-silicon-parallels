#!/bin/bash
# test/run-tests.sh — Tier 2 import simulation against a packaged image.
#
# Unzips the dist image to a temp location, imports it, boots it, waits for the YOLO
# first-boot to land at a desktop, and asserts the sysprep + health invariants.
#
# Two moments may need a human (or the driving agent) on Standard edition:
# choosing "Copied" if Parallels asks, and pressing Play. The script polls and
# announces exactly when. Console-driven assertions (password entry) are left to
# the driving agent; everything assertable without credentials is automated here.
#
# Usage: test/run-tests.sh dist/omarchy-parallels-vX.Y.Z.zip

set -uo pipefail
ZIP=${1:?usage: run-tests.sh <image.zip>}
TDIR="$HOME/Parallels/omarchy-parallels-test"
PASS=0; FAIL=0
t_ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
t_fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "==> Tier 2: import simulation for $ZIP"
[[ -f $ZIP ]] || { echo "no such image" >&2; exit 1; }
rm -rf "$TDIR"; mkdir -p "$TDIR"
unzip -q "$ZIP" -d "$TDIR"
PVM="$TDIR/Omarchy.pvm"
[[ -d $PVM ]] || { echo "zip did not contain Omarchy.pvm" >&2; exit 1; }

# ---- sysprep invariants, assertable from the host before boot ----
CFG="$PVM/config.pvs"
grep -q '<SourceVmUuid></SourceVmUuid>' "$CFG" && t_ok "SourceVmUuid stripped" || t_fail "SourceVmUuid present"
grep -q '<MAC></MAC>' "$CFG" && t_ok "MAC stripped" || t_fail "MAC present"
grep -q '<InterfaceType>2</InterfaceType>' "$CFG" && t_ok "disk on SATA" || t_fail "disk not SATA"

echo "==> registering (watch for a 'Copied or Moved?' dialog — choose Copied)"
BEFORE=$(prlctl list -a --no-header 2>/dev/null | awk '{print $1}' | sort)
open "$PVM"
NEW_UUID=""
for _ in $(seq 1 36); do
  sleep 5
  NEW_UUID=$(comm -13 <(echo "$BEFORE") <(prlctl list -a --no-header 2>/dev/null | awk '{print $1}' | sort) | head -1)
  [[ -n $NEW_UUID ]] && break
done
[[ -n $NEW_UUID ]] && t_ok "registered as $NEW_UUID" || { t_fail "never registered"; exit 1; }

NEW_MAC=$(grep -o '<MAC>[0-9A-Fa-f]\{12\}</MAC>' "$CFG" | head -1 | sed -E 's/<\/?MAC>//g' | tr 'A-F' 'a-f')
[[ -n $NEW_MAC ]] && t_ok "fresh MAC assigned ($NEW_MAC)" || t_fail "no MAC after registration"

echo "==> booting (press Play if it doesn't start; YOLO countdown runs on its own)"
open "$PVM" 2>/dev/null || true
BOOTED=0
for _ in $(seq 1 60); do
  prlctl list --no-header 2>/dev/null | grep -q "$NEW_UUID" && { BOOTED=1; break; }; sleep 5
done
[[ $BOOTED -eq 1 ]] && t_ok "VM running" || t_fail "VM never started"

if [[ $BOOTED -eq 1 && -n $NEW_MAC ]]; then
  echo "==> waiting for YOLO first-boot to finish (desktop = DHCP lease + no ssh, since YOLO disables it)"
  LEASE=0
  for _ in $(seq 1 60); do
    grep -qi "$NEW_MAC" /Library/Preferences/Parallels/parallels_dhcp_leases 2>/dev/null && { LEASE=1; break; }
    sleep 10
  done
  [[ $LEASE -eq 1 ]] && t_ok "guest obtained DHCP lease (network up)" || t_fail "no DHCP lease"
  IP=$(awk -F'[="]' -v mac="$NEW_MAC" '$0 ~ mac {split($3,a,","); print a[1]" "$1}' \
       /Library/Preferences/Parallels/parallels_dhcp_leases | sort -rn | head -1 | awk '{print $2}')
  if [[ -n $IP ]]; then
    sleep 60  # give firstboot + sddm time
    if nc -z -w 3 "$IP" 22 2>/dev/null; then t_fail "sshd is ON after YOLO (should be off)"
    else t_ok "sshd off after YOLO (as shipped)"; fi
  fi
  echo "==> console assertions (OOBE screen, desktop, crispness) are the driving agent's job:"
  echo "    screenshot the VM window at countdown, at defaults-applied, and at the desktop."
fi

echo
echo "==> RESULT: $PASS passed, $FAIL failed"
echo "    teardown when done:  prlctl unregister $NEW_UUID  (Pro) or remove in UI; rm -rf $TDIR"
exit $((FAIL > 0 ? 1 : 0))
