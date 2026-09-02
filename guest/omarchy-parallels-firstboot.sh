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
say ""
say "Press any key to customize (username, password, hostname),"
say "or wait for the quick-start defaults."
for n in 10 9 8 7 6 5 4 3 2 1; do
  printf '\r  quick-start in %2d s ... ' "$n"
  if read -r -s -n 1 -t 1; then YOLO=0; break; fi
done
printf '\r%40s\r' ' '   # clear the countdown line

if [[ $YOLO -eq 1 ]]; then
  # Known default so the user can actually sudo on a zero-interaction install. Autologin is on,
  # so an expired password (passwd -e) would never prompt for a change — instead we drop a
  # first-login reminder (see reminder file below) and document the default everywhere.
  apply "$DEFAULT_USER" "$DEFAULT_USER" omarchy no no
  # Reminder to change the shipped default password. Shows on every interactive shell while the
  # marker exists; a passwd() wrapper removes the marker on a successful change. No fragile
  # password-guessing — the wrapper knows change succeeded from passwd's own exit code.
  install -d -m 755 /etc/profile.d
  install -d /var/lib/omarchy-parallels
  touch /var/lib/omarchy-parallels/default-password
  cat > /etc/profile.d/zz-omarchy-default-password.sh <<'REMIND'
if [[ -n ${PS1:-} && -f /var/lib/omarchy-parallels/default-password ]]; then
  printf '\n\033[33m⚠  This VM still uses the default password "omarchy".\033[0m\n'
  printf '   Run \033[1mpasswd\033[0m to set your own (this notice then stops).\n\n'
  passwd() { command passwd "$@" && sudo rm -f /var/lib/omarchy-parallels/default-password; }
fi
REMIND
  big "Defaults applied"
  say "User:     $DEFAULT_USER"
  say "Password: $DEFAULT_USER   (change it after first login: run 'passwd')"
  say ""
  say "Starting the desktop..."
  sleep 6
else
  # Input helpers that work with or without gum (gum could be absent; also lets an
  # accidental keypress still reach a usable flow instead of a frozen prompt).
  ask() { # ask <prompt> <default>  -> echoes the answer
    if [[ -x $G ]]; then $G input --prompt "$2 " --value "$3" 2>/dev/null || echo "$3"
    else read -r -p "$2 [$3]: " _a </dev/tty || _a=""; echo "${_a:-$3}"; fi
  }
  ask_pw() { # ask_pw <prompt> -> echoes the (hidden) answer
    if [[ -x $G ]]; then $G input --password --prompt "$1 " 2>/dev/null
    else read -r -s -p "$1 " _p </dev/tty; echo >/dev/tty; echo "$_p"; fi
  }
  yesno() { # yesno <prompt>  -> returns 0 for yes (default No)
    if [[ -x $G ]]; then $G confirm "$1" --default=false
    else read -r -p "$1 [y/N]: " _y </dev/tty || _y=""; [[ $_y =~ ^[Yy] ]]; fi
  }

  # An accidental keypress lands here — offer a one-key bail back to quick-start.
  if ! yesno "Set things up manually? (No = quick-start defaults: user 'omarchy')"; then
    apply "$DEFAULT_USER" "$DEFAULT_USER" omarchy no no
    install -d /var/lib/omarchy-parallels; touch /var/lib/omarchy-parallels/default-password
    big "Quick-start defaults applied"; say "login omarchy / omarchy — run 'passwd' to change it"; sleep 4
  else
    while true; do
      USERNAME=$(ask "" "Username:" "$DEFAULT_USER")
      [[ $USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
      say "Usernames: lowercase letters, digits, - and _, starting with a letter."
    done
    while true; do
      P1=$(ask_pw "Password:")
      P2=$(ask_pw "Confirm: ")
      [[ -n $P1 && $P1 == "$P2" ]] && break
      say "Passwords empty or mismatched — try again."
    done
    HOSTNAME_IN=$(ask "" "Hostname:" omarchy)
    [[ $HOSTNAME_IN =~ ^[a-zA-Z0-9-]{1,63}$ ]] || HOSTNAME_IN=omarchy
    WANT_SSH=no; yesno "Enable SSH server?" && WANT_SSH=yes
    apply "$USERNAME" "$P1" "$HOSTNAME_IN" "$WANT_SSH" no
    big "Setup complete"
    if yesno "Run a system update now? (takes a few minutes)"; then
      sudo -u "$USERNAME" -i omarchy-update -y || say "Update hit an issue — run 'omarchy-update' later."
    fi
  fi
fi

rm -f "$MARKER"
systemctl disable omarchy-parallels-firstboot.service >/dev/null 2>&1 || true
exit 0
