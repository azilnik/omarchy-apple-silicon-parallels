#!/bin/bash
# omarchy-parallels-firstboot — one-time out-of-box setup for the Omarchy Parallels image.
#
# Runs on tty1 before SDDM on the first boot of a freshly imported image. Regenerates
# machine identity, then either walks a short gum-driven setup or — if the user does
# nothing for 10 seconds — applies safe defaults (YOLO mode) and boots to the desktop.
#
# Self-disables by removing its marker; sysprep re-arms it for the next image.

set -uo pipefail

MARKER=/var/lib/omarchy-parallels/firstboot-pending
DEFAULT_USER=omarchy
[[ -f $MARKER ]] || exit 0

export TERM=${TERM:-linux}
G=/usr/bin/gum

say()  { $G style --foreground 6 "$1" 2>/dev/null || echo "$1"; }
big()  { $G style --border rounded --padding "1 3" --margin "1 0" --foreground 5 "$1" 2>/dev/null || echo "== $1 =="; }

# ---------------------------------------------------------------- identity
regen_identity() {
  rm -f /etc/machine-id /var/lib/dbus/machine-id
  systemd-machine-id-setup >/dev/null 2>&1
  ln -sf /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -A >/dev/null 2>&1
}

# ---------------------------------------------------------------- apply
apply() { # apply <username> <password> <hostname> <enable_ssh:yes|no> <expire_pw:yes|no>
  local user=$1 pass=$2 host=$3 want_ssh=$4 expire=$5

  if [[ $user != "$DEFAULT_USER" ]] && id "$DEFAULT_USER" >/dev/null 2>&1; then
    usermod -l "$user" "$DEFAULT_USER"
    groupmod -n "$user" "$DEFAULT_USER" 2>/dev/null || true
    usermod -d "/home/$user" -m "$user"
  fi
  echo "$user:$pass" | chpasswd
  [[ $expire == yes ]] && passwd -e "$user" >/dev/null 2>&1

  echo "$host" > /etc/hostname
  hostnamectl set-hostname "$host" 2>/dev/null || true
  printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s\n' "$host" > /etc/hosts

  # SDDM: autologin + last-user (the Omarchy theme submits an empty username without state.conf)
  printf '[Autologin]\nUser=%s\nSession=hyprland-uwsm.desktop\nRelogin=false\n' "$user" \
    > /etc/sddm.conf.d/30-autologin.conf
  mkdir -p /var/lib/sddm
  printf '[Last]\nUser=%s\nSession=hyprland-uwsm.desktop\n' "$user" > /var/lib/sddm/state.conf
  chown -R sddm:sddm /var/lib/sddm 2>/dev/null || true

  if [[ $want_ssh == yes ]]; then systemctl enable --now sshd >/dev/null 2>&1
  else systemctl disable --now sshd >/dev/null 2>&1 || true; fi
}

# ---------------------------------------------------------------- main
clear
big "Welcome to Omarchy on Parallels"
say "First boot: creating this machine's identity..."
regen_identity

YOLO=1
if [[ -x $G ]]; then
  say ""
  say "Press any key to customize (username, password, hostname)."
  say "Doing nothing applies safe defaults in 10 seconds."
  if read -r -s -n 1 -t 10; then YOLO=0; fi
fi

if [[ $YOLO -eq 1 ]]; then
  PASS=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 10)
  apply "$DEFAULT_USER" "$PASS" omarchy no yes
  big "Defaults applied"
  say "User:     $DEFAULT_USER"
  say "Password: $PASS   (you must change it at first use)"
  say ""
  say "Write the password down — the desktop starts in 15 seconds."
  sleep 15
else
  while true; do
    USERNAME=$($G input --placeholder "$DEFAULT_USER" --prompt "Username: " --value "$DEFAULT_USER")
    [[ $USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
    say "Usernames: lowercase letters, digits, - and _, starting with a letter."
  done
  while true; do
    P1=$($G input --password --prompt "Password: ")
    P2=$($G input --password --prompt "Confirm:  ")
    [[ -n $P1 && $P1 == "$P2" ]] && break
    say "Passwords empty or mismatched — try again."
  done
  HOSTNAME_IN=$($G input --placeholder omarchy --prompt "Hostname: " --value omarchy)
  [[ $HOSTNAME_IN =~ ^[a-zA-Z0-9-]{1,63}$ ]] || HOSTNAME_IN=omarchy
  WANT_SSH=no
  $G confirm "Enable SSH server?" --default=false && WANT_SSH=yes
  apply "$USERNAME" "$P1" "$HOSTNAME_IN" "$WANT_SSH" no
  big "Setup complete"
  if $G confirm "Run a system update now? (takes a few minutes)" --default=false; then
    sudo -u "$USERNAME" -i omarchy-update -y || say "Update hit an issue — run 'omarchy-update' later."
  fi
fi

rm -f "$MARKER"
systemctl disable omarchy-parallels-firstboot.service >/dev/null 2>&1 || true
exit 0
