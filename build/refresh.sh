#!/bin/bash
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
$SSH "printf 'Defaults:%s !authenticate\n%s ALL=(ALL:ALL) NOPASSWD: ALL\n' '$BUILD_USER' '$BUILD_USER' > /etc/sudoers.d/90-build-temp; chmod 440 /etc/sudoers.d/90-build-temp"
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
