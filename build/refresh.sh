#!/bin/bash
# shellcheck disable=SC2016  # remote-side expressions are meant to expand on the guest, not the host
# build/refresh.sh — bring the builder VM current and install the guest payload, then gate on verify.
#
# Runs on the Mac host against the builder VM over SSH (the omarchy-ssh wrapper).
# Aborts on any failure; a green verify is the precondition for sysprep + package.

set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SSH="${OMARCHY_SSH:-$HOME/Parallels/omarchy-ssh}"

[[ -x $SSH ]] || { echo "refresh: missing ssh wrapper at $SSH" >&2; exit 1; }
$SSH 'echo ok' >/dev/null || { echo "refresh: builder VM unreachable" >&2; exit 1; }

BUILD_USER=$($SSH 'loginctl list-sessions --no-legend | awk "\$4==\"seat0\"{print \$3; exit}"')
BUILD_USER=${BUILD_USER:-omarchy}
echo "==> builder user: $BUILD_USER"

echo "==> system update (omarchy-update -y with known ARM workarounds)"
# Workaround 1: sudo -v prompts even under NOPASSWD when a passworded wheel rule also matches.
# (Pipe the file over stdin — inline printf through the ssh arg layer mangles the content.)
printf 'Defaults:%s !authenticate\n%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$BUILD_USER" "$BUILD_USER" \
  | $SSH 'cat > /etc/sudoers.d/90-build-temp; chmod 440 /etc/sudoers.d/90-build-temp; visudo -cf /etc/sudoers.d/90-build-temp'
# Workaround 2: omarchy-update-restart runs a gum reboot prompt despite -y; run detached and reap.
$SSH "setsid nohup sudo -u $BUILD_USER -i bash -c 'omarchy-update -y > /tmp/build-update.log 2>&1; echo DONE-\$? >> /tmp/build-update.log' >/dev/null 2>&1 < /dev/null & echo launched"
for _ in $(seq 1 240); do
  $SSH 'grep -q "^DONE-" /tmp/build-update.log 2>/dev/null' && break
  # Reap ONLY the final reboot confirm: a gum prompt with the log quiet for 60s+.
  # (Never match on log content — pacman prints "nothing to do" early in every run.)
  if $SSH 'pgrep -f "gum confirm" >/dev/null && [ $(( $(date +%s) - $(stat -c %Y /tmp/build-update.log) )) -ge 60 ]'; then
    $SSH 'pkill -f "gum confirm"' || true
    sleep 5
  fi
  sleep 15
done
$SSH 'tail -2 /tmp/build-update.log' || true

echo "==> installing guest payload"
for f in omarchy-parallels-verify omarchy-parallels-autoresize omarchy-parallels-firstboot; do
  $SSH "cat > /usr/local/bin/$f && chmod 755 /usr/local/bin/$f" < "$REPO/guest/$f.sh"
done
$SSH 'cat > /etc/systemd/system/omarchy-parallels-firstboot.service' < "$REPO/guest/omarchy-parallels-firstboot.service"
BUILD_HOME=$($SSH "getent passwd $BUILD_USER | cut -d: -f6")
$SSH "install -d -o $BUILD_USER -g $BUILD_USER $BUILD_HOME/.config/systemd/user"
$SSH "cat > $BUILD_HOME/.config/systemd/user/parallels-autoresize.service && chown $BUILD_USER:$BUILD_USER $BUILD_HOME/.config/systemd/user/parallels-autoresize.service" < "$REPO/guest/parallels-autoresize.service"
# retire the pre-repo prototype paths if present
$SSH "rm -f $BUILD_HOME/.local/bin/omarchy-parallels-autoresize; systemctl daemon-reload
BUID=\$(id -u $BUILD_USER)
sudo -u $BUILD_USER XDG_RUNTIME_DIR=/run/user/\$BUID systemctl --user daemon-reload
sudo -u $BUILD_USER XDG_RUNTIME_DIR=/run/user/\$BUID systemctl --user enable --now parallels-autoresize.service"

# Mac/Parallels keybinding compatibility — append the drop-in to the user's bindings.lua,
# idempotently (remove any prior block between our markers first, then re-append).
BINDS="$BUILD_HOME/.config/hypr/bindings.lua"
$SSH "sed -i '/── BEGIN omarchy-parallels mac keybinds ──/,/── END omarchy-parallels mac keybinds ──/d' '$BINDS' 2>/dev/null; true"
$SSH "cat >> '$BINDS'" < "$REPO/guest/hypr/parallels-mac.bindings.lua"
$SSH "chown $BUILD_USER:$BUILD_USER '$BINDS'"

# Parallels double-cursor fix — render the cursor in software (see the drop-in for why).
# hyprland.lua require()s this module, so it MUST exist and hold omarchy's template. Reseed
# from the pristine default (the user copy is just a commented template — no user config to
# lose in a fresh build), then append our cursor block. Deterministic; never clobbers.
LNF="$BUILD_HOME/.config/hypr/looknfeel.lua"
$SSH "install -Dm644 /usr/share/omarchy/config/hypr/looknfeel.lua '$LNF'"
$SSH "cat >> '$LNF'" < "$REPO/guest/hypr/parallels-cursor.looknfeel.lua"
$SSH "chown $BUILD_USER:$BUILD_USER '$LNF'"

# one reload picks up both drop-ins
$SSH "BUID=\$(id -u $BUILD_USER)
SIG=\$(ls -1t /run/user/\$BUID/hypr 2>/dev/null | head -1)
[ -n \"\$SIG\" ] && sudo -u $BUILD_USER env HOME=$BUILD_HOME XDG_RUNTIME_DIR=/run/user/\$BUID HYPRLAND_INSTANCE_SIGNATURE=\$SIG hyprctl reload >/dev/null 2>&1 || true"

# Build the aarch64 packages Omarchy ships x86_64-only and install them, so the image is
# feature-complete. Toolchains are stripped later by sysprep. Skip with OMARCHY_SKIP_EXTRA_PKGS=1.
if [[ -z ${OMARCHY_SKIP_EXTRA_PKGS:-} ]]; then
  echo "==> building ARM packages (Omarchy's x86-only apps)"
  $SSH "sudo -u $BUILD_USER mkdir -p $BUILD_HOME/armbuild/packages"
  tar -C "$REPO" -czf - packages | $SSH "sudo -u $BUILD_USER tar -C $BUILD_HOME/armbuild -xzf - && chown -R $BUILD_USER:$BUILD_USER $BUILD_HOME/armbuild"
  # base-devel is already present; build-all installs each pkg via makepkg -si
  $SSH "printf '%s ALL=(ALL) NOPASSWD: ALL\n' $BUILD_USER > /etc/sudoers.d/95-build; chmod 440 /etc/sudoers.d/95-build"
  $SSH "sudo -u $BUILD_USER bash -lc 'cd ~/armbuild/packages && bash build-all.sh 2>&1 | tail -3'" || echo "   (some ARM packages failed — non-fatal; see status)"
  # install everything that built
  $SSH "sudo -u $BUILD_USER bash -lc 'for p in ~/armbuild/packages/*/*.pkg.tar.*; do sudo pacman -U --noconfirm --needed \"\$p\" >/dev/null 2>&1; done; echo installed extras'"
  $SSH 'rm -f /etc/sudoers.d/95-build'
fi

echo "==> revoking temporary sudo grant"
$SSH 'rm -f /etc/sudoers.d/90-build-temp'

echo "==> Tier 1 gate: omarchy-parallels-verify"
if $SSH 'omarchy-parallels-verify' > /tmp/verify.json; then
  echo "==> VERIFY PASS"
  cat /tmp/verify.json
else
  echo "==> VERIFY FAIL — aborting" >&2
  cat /tmp/verify.json >&2
  exit 1
fi
