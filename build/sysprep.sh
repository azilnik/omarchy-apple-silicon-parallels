#!/bin/bash
# shellcheck disable=SC2016  # remote-side expressions expand on the guest
# build/sysprep.sh — strip identity/secrets/caches from the builder VM and arm first-boot.
#
# DESTRUCTIVE to the running guest's identity: intended to run against a THROWAWAY CLONE
# of the builder VM (package.sh clones first), never the daily builder. It refuses unless
# OMARCHY_SYSPREP_CONFIRM=yes to make that hard to get wrong.
#
# Ends by powering the guest off; package.sh takes over on the host.

set -euo pipefail
SSH="${OMARCHY_SSH:-$HOME/Parallels/omarchy-ssh}"
[[ ${OMARCHY_SYSPREP_CONFIRM:-} == yes ]] || { echo "sysprep: set OMARCHY_SYSPREP_CONFIRM=yes (run only against a clone!)" >&2; exit 1; }

BUILD_USER=$($SSH 'loginctl list-sessions --no-legend | awk "\$4==\"seat0\"{print \$3; exit}"')
BUILD_USER=${BUILD_USER:-omarchy}
BUILD_HOME=$($SSH "getent passwd $BUILD_USER | cut -d: -f6")
echo "==> sysprep of user '$BUILD_USER' ($BUILD_HOME)"

$SSH 'bash -s' <<EOF
set -uo pipefail

# ---- secrets & identity ----
rm -f /root/.ssh/authorized_keys $BUILD_HOME/.ssh/authorized_keys
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# ---- credentials: lock accounts; OOBE sets real ones ----
passwd -l root >/dev/null
passwd -l "$BUILD_USER" >/dev/null 2>&1 || true

# ---- record the build user for first-boot to rename ----
# We can't rename the build user here: it's logged in via autologin, so usermod -l fails
# ("user is currently used by process"). Instead, first-boot does the rename — it runs
# BEFORE sddm, when no one is logged in. Just record who to rename.
install -d /var/lib/omarchy-parallels
echo "$BUILD_USER" > /var/lib/omarchy-parallels/build-user

# ---- login flow: no autologin, no remembered user; OOBE rewrites both ----
rm -f /etc/sddm.conf.d/30-autologin.conf /var/lib/sddm/state.conf

# ---- strip build-only toolchain (the ARM-built apps are installed; their build deps aren't
#      needed at runtime). Saves ~500 MB. Runtime deps (qt6, gtk4, ffmpeg) are kept as real
#      dependencies of the apps, so pacman won't remove them. ----
pacman -Rns --noconfirm rust >/dev/null 2>&1 || true
rm -rf /home/omarchy/armbuild "/home/$BUILD_USER/armbuild" 2>/dev/null || true
rm -f /etc/sudoers.d/95-build 2>/dev/null || true
pacman -Qtdq 2>/dev/null | pacman -Rns --noconfirm - >/dev/null 2>&1 || true   # orphaned makedeps

# ---- caches, logs, history, leftovers ----
pacman -Scc --noconfirm >/dev/null 2>&1 || true
rm -rf /var/cache/pacman/pkg/* /root/prl-tools.iso /root/inside.sh /tmp/* 2>/dev/null || true
journalctl --rotate >/dev/null 2>&1; journalctl --vacuum-time=1s >/dev/null 2>&1
# Coredumps from build-time app crashes ship in the image otherwise, and omarchy-crash-watch
# surfaces them as "Process crashed" notifications on the recipient's first boot. Clear them.
rm -rf /var/lib/systemd/coredump/* 2>/dev/null || true
# Build-user app caches/state that accumulated during the build (test launches of the GUI apps).
# ~/.cache is hundreds of MB and pure churn; app state (obsidian etc.) is our test pollution.
for h in /root "/home/$BUILD_USER" /home/omarchy; do
  rm -rf "$h/.cache" "$h/.config/obsidian" "$h/.local/share/obsidian" 2>/dev/null || true
  rm -f  "$h/.bash_history" "$h/lazy.log" "$h/health.txt" 2>/dev/null || true
done
rm -f /etc/NetworkManager/system-connections/* 2>/dev/null || true
rm -f /etc/sudoers.d/90-build-temp /etc/sudoers.d/20-omarchy-install 2>/dev/null || true

# ---- arm first boot ----
install -d /var/lib/omarchy-parallels
touch /var/lib/omarchy-parallels/firstboot-pending
systemctl enable omarchy-parallels-firstboot.service >/dev/null 2>&1
systemctl disable --now sshd >/dev/null 2>&1 || true

# ---- zero-fill free space so prl_disk_tool compact can reclaim it ----
echo "==> zero-filling free space (takes a while)"
dd if=/dev/zero of=/zero.fill bs=8M status=none 2>/dev/null || true
sync; rm -f /zero.fill; sync
echo "==> sysprep done; powering off"
systemctl poweroff
EOF
echo "==> guest powering off"
