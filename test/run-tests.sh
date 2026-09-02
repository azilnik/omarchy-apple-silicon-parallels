#!/bin/bash
# test/run-tests.sh — Tier 2 cold-import simulation against a packaged image.
#
# Fully headless where prlctl register/start/exec/unregister are available (Parallels
# Desktop 27 trial verified). Imports the shipped zip exactly as a recipient would,
# boots it, lets the YOLO first-boot run, then asserts every sysprep + first-boot
# invariant from *inside* the guest via `prlctl exec` — no sshd needed (YOLO leaves it off).
#
# Usage: test/run-tests.sh dist/omarchy-parallels-vX.Y.Z.zip

set -uo pipefail
ZIP=${1:?usage: run-tests.sh <image.zip>}
TDIR="$HOME/Parallels/omarchy-parallels-test"
NAME="Omarchy-import-test"
BUILDER_MID="b16834904426489d87981d615bc1d70e"   # the daily builder's machine-id; the import must differ
PASS=0; FAIL=0
t_ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
t_fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
X() { prlctl exec "$NAME" "$@" 2>/dev/null; }   # run a command inside the guest as root

echo "==> Tier 2: cold-import simulation for $ZIP"
[[ -f $ZIP ]] || { echo "no such image" >&2; exit 1; }

# clean any prior test VM
prlctl stop "$NAME" --kill >/dev/null 2>&1 || true
prlctl unregister "$NAME" >/dev/null 2>&1 || true
rm -rf "$TDIR"; mkdir -p "$TDIR"
unzip -q "$ZIP" -d "$TDIR"
PVM="$TDIR/Omarchy.pvm"
[[ -d $PVM ]] || { echo "zip did not contain Omarchy.pvm" >&2; exit 1; }

# ---- sysprep invariants assertable from the host, before boot ----
CFG="$PVM/config.pvs"
grep -q '<SourceVmUuid></SourceVmUuid>' "$CFG" && t_ok "SourceVmUuid stripped" || t_fail "SourceVmUuid present"
grep -q '<MAC></MAC>' "$CFG" && t_ok "MAC blanked (import mints a fresh one)" || t_fail "MAC present in shipped config"
grep -q '<InterfaceType>2</InterfaceType>' "$CFG" && t_ok "disk on SATA (boots on Apple Silicon)" || t_fail "disk not SATA"

# give the imported VM a distinct name so it can't be confused with the builder
sed -i '' 's|<VmName>Omarchy</VmName>|<VmName>Omarchy-import-test</VmName>|' "$CFG"

echo "==> registering the image (headless import — the recipient's double-click)"
prlctl register "$PVM" >/dev/null 2>&1 || { t_fail "register failed"; echo "RESULT: $PASS/$((PASS+FAIL))"; exit 1; }
t_ok "registered headlessly"
NEW_MAC=$(prlctl list -i "$NAME" 2>/dev/null | grep -oiE 'mac=[0-9A-Fa-f]{12}' | head -1 | cut -d= -f2 | tr 'A-F' 'a-f')
[[ -n $NEW_MAC ]] && t_ok "fresh MAC assigned on import ($NEW_MAC)" || t_fail "no MAC after import"

echo "==> booting (YOLO first-boot runs its 10s countdown, then applies defaults)"
prlctl start "$NAME" >/dev/null 2>&1 || { t_fail "start failed"; }

echo "==> waiting for first-boot to finish (marker removed) ..."
FB=0
for _ in $(seq 1 60); do
  # exec becomes available once prltoolsd is up (early boot). Marker gone == firstboot done.
  if X 'test ! -f /var/lib/omarchy-parallels/firstboot-pending' >/dev/null 2>&1; then FB=1; break; fi
  sleep 5
done
[[ $FB -eq 1 ]] && t_ok "first-boot completed (marker cleared, service self-disabled)" \
                 || t_fail "first-boot never completed"

echo "==> guest-side assertions (via prlctl exec, no sshd) ..."

# fresh machine identity
MID=$(X 'cat /etc/machine-id' | tr -d '\r\n ')
[[ -n $MID && $MID != "$BUILDER_MID" ]] && t_ok "machine-id regenerated ($MID)" \
    || t_fail "machine-id NOT regenerated (== builder)"
if X 'test -s /etc/ssh/ssh_host_ed25519_key.pub' >/dev/null 2>&1; then t_ok "ssh host keys regenerated"; else t_fail "ssh host keys missing"; fi
AK=$(X 'cat /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null | wc -l' | tr -d ' ')
[[ ${AK:-0} == 0 ]] && t_ok "no authorized_keys shipped" || t_fail "authorized_keys present ($AK lines)"

# user rename ari -> omarchy
X 'id omarchy' >/dev/null 2>&1 && t_ok "user 'omarchy' exists" || t_fail "user 'omarchy' missing"
X 'id ari' >/dev/null 2>&1 && t_fail "build user 'ari' still present" || t_ok "build user 'ari' renamed away"
X 'test -d /home/omarchy' >/dev/null 2>&1 && t_ok "/home/omarchy present" || t_fail "/home/omarchy missing"
X 'test -d /home/ari' >/dev/null 2>&1 && t_fail "/home/ari still present" || t_ok "/home/ari gone"

# THE wallpaper bug: no symlink under the renamed home may still point at /home/ari
DANGLE=$(X 'find /home/omarchy -xtype l 2>/dev/null | wc -l' | tr -d ' ')
[[ ${DANGLE:-1} == 0 ]] && t_ok "no dangling symlinks in /home/omarchy" || t_fail "$DANGLE dangling symlinks (wallpaper/nvim/mise?)"
ARILINK=$(X 'find /home/omarchy -type l -lname "/home/ari/*" 2>/dev/null | wc -l' | tr -d ' ')
[[ ${ARILINK:-1} == 0 ]] && t_ok "no symlink still targets /home/ari" || t_fail "$ARILINK symlinks still point at /home/ari"
# wallpaper: omarchy 4 keeps the current background at ~/.local/state/omarchy/current/background;
# after the rename+repoint it must resolve to a real image (quickshell paints from it).
if X 'test -e "$(readlink -f /home/omarchy/.local/state/omarchy/current/background)"' >/dev/null 2>&1; then
  t_ok "wallpaper link resolves to a real file"
else t_fail "wallpaper link broken (desktop would render black)"; fi

# THE crash-toast bug: notification queue + coredumps must be empty
NQ=$(X 'ls /home/omarchy/.local/state/omarchy/notifications/*.json 2>/dev/null | wc -l' | tr -d ' ')
[[ ${NQ:-0} == 0 ]] && t_ok "notification queue empty (no replayed crash toasts)" || t_fail "$NQ queued notifications shipped"
CD=$(X 'ls /var/lib/systemd/coredump/* 2>/dev/null | wc -l' | tr -d ' ')
[[ ${CD:-0} == 0 ]] && t_ok "no coredumps shipped" || t_fail "$CD coredumps shipped"
JCRASH=$(X 'journalctl -b -1 -q 2>/dev/null | grep -c "Process.*dumped core" 2>/dev/null' | tr -d ' ')
[[ ${JCRASH:-0} == 0 ]] && t_ok "no crash records in prior-boot journal" || echo "  · $JCRASH crash records in old journal (pre-regen boot; cosmetic)"

# ARM-built apps present
MISS=""
for p in omacalc omawrite omacut obsidian ttfx tobi-try hyprland-preview-share-picker; do
  X "pacman -Q $p" >/dev/null 2>&1 || MISS="$MISS $p"
done
[[ -z $MISS ]] && t_ok "all 7 ARM-built apps installed" || t_fail "missing apps:$MISS"

# login flow + shipped defaults
X 'grep -q "User=omarchy" /etc/sddm.conf.d/30-autologin.conf' >/dev/null 2>&1 \
    && t_ok "SDDM autologin points at omarchy" || t_fail "autologin not set to omarchy"
X 'test -f /var/lib/omarchy-parallels/default-password' >/dev/null 2>&1 \
    && t_ok "default-password reminder armed" || t_fail "default-password marker missing"
if X 'systemctl is-enabled sshd' 2>/dev/null | grep -q enabled; then t_fail "sshd enabled after YOLO (should be off)"
else t_ok "sshd off after YOLO (as shipped)"; fi

# mac keybinding payload present (refresh.sh appends it into bindings.lua, not a standalone file)
if X 'grep -qi parallels /home/omarchy/.config/hypr/bindings.lua' >/dev/null 2>&1; then t_ok "mac keybinding drop-in present in bindings.lua"
else t_fail "mac keybinding drop-in missing from bindings.lua"; fi

# the shipped verify tool's own verdict. Call by full path (prlctl exec uses a minimal PATH) and
# read the JSON verdict rather than the exit code (prlctl exec mangles exit codes intermittently).
VERD=$(X '/usr/local/bin/omarchy-parallels-verify 2>/dev/null')
if echo "$VERD" | grep -q '"verdict": "pass"'; then t_ok "omarchy-parallels-verify verdict=pass (all checks)"
else t_fail "omarchy-parallels-verify not pass (run: prlctl exec $NAME /usr/local/bin/omarchy-parallels-verify)"; fi

# ---- desktop actually paints (the real black-wallpaper guard) ----
# Force a fresh autologin session and grab the host-side framebuffer BEFORE the desktop idles into
# a lock/DPMS state. A painted Omarchy desktop (wallpaper + bar) is a busy image that compresses to
# hundreds of KB; a black/near-black frame is a few KB. Threshold well between the two.
echo "==> desktop paint check (fresh session, host-side capture) ..."
X 'systemctl restart sddm' >/dev/null 2>&1
SHOT="${TDIR}/desktop.png"; PAINT=0
for _ in $(seq 1 20); do
  sleep 4
  hp=$(X 'pgrep -x Hyprland | head -1' | tr -d '\r\n ')
  qs=$(X 'pgrep -x quickshell | head -1' | tr -d '\r\n ')
  [[ -n $hp && -n $qs ]] || continue
  sleep 5   # let quickshell paint the wallpaper
  prlctl capture "$NAME" --file "$SHOT" >/dev/null 2>&1 || true
  SZ=$(stat -f%z "$SHOT" 2>/dev/null || echo 0)
  [[ ${SZ:-0} -gt 100000 ]] && { PAINT=1; break; }
done
if [[ $PAINT -eq 1 ]]; then t_ok "desktop paints wallpaper+bar (frame ${SZ} bytes) → $SHOT"
else t_fail "desktop frame is near-black (${SZ:-0} bytes) — wallpaper not painting"; fi

echo
echo "==> RESULT: $PASS passed, $FAIL failed"
echo "    teardown:  prlctl stop $NAME --kill; prlctl unregister $NAME; rm -rf $TDIR"
exit $((FAIL > 0 ? 1 : 0))
