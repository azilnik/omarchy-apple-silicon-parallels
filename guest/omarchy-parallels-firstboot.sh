#!/bin/bash
# omarchy-parallels-firstboot — one-time out-of-box setup for the Omarchy Parallels image.
#
# Runs on tty1 before SDDM on the first boot of a freshly imported image. Regenerates machine
# identity, then either walks a short setup or — if the user does nothing — applies safe
# defaults and boots to the desktop.
#
# This is the first thing anyone sees of the VM, so it uses the same terminal UI as the macOS
# installer (lib/tui.sh, installed here as tui.sh). tty1 is TERM=linux: eight colours and a
# 256-glyph console font, so the library drops to its "basic" tier — block bars, ● instead of
# ✓, a quadrant spinner. Everything degrades; nothing is assumed.
#
# Self-disables by removing its marker; sysprep re-arms it for the next image.

set -uo pipefail

MARKER=/var/lib/omarchy-parallels/firstboot-pending
DEFAULT_USER=omarchy
[[ -f $MARKER ]] || exit 0

# The user the image was built with (sysprep couldn't rename it — it was logged in). We rename
# it here, before sddm, when it isn't. Fall back to the sole human UID-1000 account.
SRC_USER=$(cat /var/lib/omarchy-parallels/build-user 2>/dev/null)
[[ -z ${SRC_USER:-} ]] && SRC_USER=$(getent passwd 1000 | cut -d: -f1)
SRC_USER=${SRC_USER:-omarchy}

export TERM=${TERM:-linux}
# tty1 has no locale set at this point, and without a UTF-8 LC_CTYPE bash counts bytes instead
# of characters — which shreds every box-drawing glyph the UI slices. The library repairs this
# itself, but setting it here means the value is also inherited by anything we shell out to.
export LC_CTYPE=${LC_CTYPE:-C.UTF-8}

# ---------------------------------------------------------------- identity
regen_identity() {
  # DO NOT regenerate the machine-id here. sysprep leaves /etc/machine-id empty, so systemd
  # already generated a fresh, unique one very early in first boot — and the system dbus daemon
  # started with it. Re-generating it now (systemd-machine-id-setup) changes it out from under
  # the running dbus daemon, so dbus_get_local_machine_id()'s consistency check aborts in every
  # Qt client (fcitx5's Qt plugin → quickshell crash-loops ~10x before the session settles).
  # Just make sure dbus's pointer to the id exists; never touch the id's value.
  [[ -e /var/lib/dbus/machine-id ]] || ln -sf /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
  # SSH host keys are safe to regenerate (nothing has cached them yet).
  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -A >/dev/null 2>&1
}

# ---------------------------------------------------------------- apply
# Kept as one function on purpose: the symlink repointing below is subtle and order-dependent,
# so it reports progress through STEP rather than being split into separately callable pieces.
STEP() { :; }   # replaced with a live task-line updater once the UI is up

apply() { # apply <username> <password> <hostname> <enable_ssh:yes|no> <expire_pw:yes|no>
  local user=$1 pass=$2 host=$3 want_ssh=$4 expire=$5

  # Rename the build user to the chosen name (no one is logged in yet at first-boot time).
  if [[ $user != "$SRC_USER" ]] && id "$SRC_USER" >/dev/null 2>&1 && ! id "$user" >/dev/null 2>&1; then
    STEP "renaming the account to $user"
    usermod -l "$user" "$SRC_USER"
    groupmod -n "$user" "$SRC_USER" 2>/dev/null || true
    usermod -d "/home/$user" -m "$user"
    # usermod -m moves the home but leaves ABSOLUTE symlinks pointing at the old path
    # (wallpaper, nvim treesitter queries, mise configs, gtk bookmarks…). Repoint them,
    # else e.g. the desktop background is a dangling link and renders black.
    STEP "repointing home-directory links"
    while IFS= read -r link; do
      target=$(readlink "$link")
      case "$target" in
        "/home/$SRC_USER")     ln -sf "/home/$user" "$link" ;;                               # bare home target
        "/home/$SRC_USER/"*)   ln -sf "/home/$user/${target#"/home/$SRC_USER/"}" "$link" ;;   # under old home
      esac
    done < <(find "/home/$user" -xtype l 2>/dev/null)
    # Sweep any links that are STILL dangling after repointing — these point at build-session
    # ephemera (/tmp sockets, old-machine-id runtime, PIDs) that the owning app regenerates.
    find "/home/$user" -xtype l -delete 2>/dev/null || true
  fi

  STEP "setting the password"
  echo "$user:$pass" | chpasswd
  [[ $expire == yes ]] && passwd -e "$user" >/dev/null 2>&1

  STEP "setting the hostname to $host"
  echo "$host" > /etc/hostname
  hostnamectl set-hostname "$host" 2>/dev/null || true
  printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s\n' "$host" > /etc/hosts

  # SDDM: autologin + last-user (the Omarchy theme submits an empty username without state.conf)
  STEP "configuring the login screen"
  printf '[Autologin]\nUser=%s\nSession=hyprland-uwsm.desktop\nRelogin=false\n' "$user" \
    > /etc/sddm.conf.d/30-autologin.conf
  mkdir -p /var/lib/sddm
  printf '[Last]\nUser=%s\nSession=hyprland-uwsm.desktop\n' "$user" > /var/lib/sddm/state.conf
  chown -R sddm:sddm /var/lib/sddm 2>/dev/null || true

  STEP "SSH server: $want_ssh"
  if [[ $want_ssh == yes ]]; then systemctl enable --now sshd >/dev/null 2>&1
  else systemctl disable --now sshd >/dev/null 2>&1 || true; fi
}

# The shipped default password is a known secret, so say so until it is changed. The reminder
# shows on every interactive shell while the marker exists; a passwd() wrapper clears it from
# passwd's own exit code — no fragile password guessing.
arm_password_reminder() {
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
}

finish() {
  rm -f "$MARKER"
  systemctl disable omarchy-parallels-firstboot.service >/dev/null 2>&1 || true
  exit 0
}

# ---------------------------------------------------------------- no UI, no problem
# The image ships the UI library next to this script. If it is missing the payload is broken —
# but a broken payload must never mean a machine that will not finish booting, so apply the
# documented defaults, say so in plain text, and get out of the way.
TUI_LIB=${OMARCHY_TUI_LIB:-/usr/local/lib/omarchy-parallels/tui.sh}
# shellcheck source=../lib/tui.sh
if [[ ! -r $TUI_LIB ]] || ! . "$TUI_LIB" 2>/dev/null || ! tui_init 2>/dev/null; then
  clear 2>/dev/null || true
  echo "Omarchy for Parallels — first boot"
  echo "Applying quick-start defaults (user: $DEFAULT_USER / $DEFAULT_USER)."
  regen_identity
  apply "$DEFAULT_USER" "$DEFAULT_USER" omarchy no no
  arm_password_reminder
  echo "Starting the desktop..."
  sleep 4
  finish
fi

# ---------------------------------------------------------------- UI helpers
STEP() { tui_detail setup "$1"; }

# A draining bar reads as "time is passing" in a way a bare number never does, and it makes the
# window to interrupt obvious. Tenths of a second: smooth to watch, and the same read() that
# paces the loop is the one listening for the keypress — no separate sleep, no busy-wait.
countdown() { # countdown <seconds> — returns 1 if a key was pressed, 0 if it ran out
  # The loop paces itself on read(2). With no terminal on stdin that returns instantly, so the
  # ten seconds would collapse into a spin — and nobody is there to press anything anyway.
  [ -t 0 ] || return 0
  # Two declarations on purpose: assignments in a single `local` are not visible to the
  # expressions beside them, so `local secs=$1 tenths=$((secs * 10))` would read whatever
  # `secs` meant outside this function.
  local secs=$1
  local tenths=$((secs * 10)) left bar shown
  left=$tenths
  while [[ $left -gt 0 ]]; do
    tui_bar bar "$left" "$tenths" 22
    shown=$(( (left + 9) / 10 ))
    printf '\r\033[2K     %s  %sstarting in %2ds%s   %spress any key to set things up%s' \
      "$bar" "$TUI_B" "$shown" "$TUI_R" "$TUI_DIM" "$TUI_R"
    if read -rsn1 -t 0.1; then printf '\r\033[2K'; return 1; fi
    left=$((left - 1))
  done
  printf '\r\033[2K'
  return 0
}

valid_user()  { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
valid_host()  { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]]; }

# ---------------------------------------------------------------- main
clear 2>/dev/null || true
tui_header "Welcome to Omarchy" "Arch + Hyprland, running in Parallels"
# shellcheck disable=SC2034  # read by the library's interrupt handler
TUI_CANCEL_HINT="first boot will run again next time."

tui_task_add ident "Creating machine identity"
tui_start ident "ssh host keys"
regen_identity
tui_ok ident "fresh ssh host keys"
tui_commit

USERNAME=$DEFAULT_USER; PASSWORD=$DEFAULT_USER; HOSTNAME_IN=omarchy
WANT_SSH=no; EXPIRE=no; DEFAULTED=1; WANT_UPDATE=0

printf '\n'
tui_note "Doing nothing sets up user 'omarchy', password 'omarchy', hostname 'omarchy'."
if ! countdown 10; then
  DEFAULTED=0
  # A key pressed during boot is as likely to be a stray as a decision, and nobody may be
  # watching. Fall back to the highlighted default rather than blocking the desktop for ever.
  TUI_READ_TIMEOUT=60
  tui_choose PICK 0 "How would you like to set this machine up?" \
    "Quick|user 'omarchy', password 'omarchy', hostname 'omarchy'" \
    "Custom|choose the username, password, hostname and SSH"
  [[ $PICK -eq 0 ]] && DEFAULTED=1
  # Past the first decision there is definitely a person here; let them take their time.
  unset TUI_READ_TIMEOUT
fi

if [[ $DEFAULTED -eq 0 ]]; then
  while :; do
    tui_ask USERNAME "Username:" "$DEFAULT_USER"
    valid_user "$USERNAME" && break
    tui_note "Lowercase letters, digits, - and _, starting with a letter or _."
  done
  while :; do
    tui_ask_secret P1 "Password:"
    tui_ask_secret P2 "Confirm: "
    [[ -n $P1 && $P1 == "$P2" ]] && { PASSWORD=$P1; break; }
    if [[ -z $P1 ]]; then tui_note "An empty password would lock you out of sudo — try again."
    else tui_note "Those did not match — try again."; fi
  done
  while :; do
    tui_ask HOSTNAME_IN "Hostname:" omarchy
    valid_host "$HOSTNAME_IN" && break
    tui_note "Letters, digits and hyphens; must start with a letter or digit."
  done
  tui_toggle OPTS "Anything else?" \
    "SSH server|reachable over the network from your Mac|0" \
    "Expire password|force a change at first login|0" \
    "Update now|run omarchy-update before the desktop starts|0"
  # shellcheck disable=SC2086  # tui_toggle returns "0 1 0"; splitting it is the point
  set -- $OPTS
  [[ ${1:-0} -eq 1 ]] && WANT_SSH=yes
  [[ ${2:-0} -eq 1 ]] && EXPIRE=yes
  WANT_UPDATE=${3:-0}

  tui_panel "$TUI_ACCENT" "Ready to set up" \
    "user       $USERNAME" \
    "hostname   $HOSTNAME_IN" \
    "ssh        $WANT_SSH" \
    "update     $([[ $WANT_UPDATE -eq 1 ]] && echo yes || echo no)"
  tui_confirm "Apply these settings?" y || { tui_note "Starting over."; exec "$0"; }
fi

tui_tasks_reset
tui_task_add setup "Setting up this machine"
tui_start setup "applying"
apply "$USERNAME" "$PASSWORD" "$HOSTNAME_IN" "$WANT_SSH" "$EXPIRE"
if [[ $DEFAULTED -eq 1 ]]; then arm_password_reminder; fi
tui_ok setup "user $USERNAME · host $HOSTNAME_IN · ssh $WANT_SSH"

if [[ $WANT_UPDATE -eq 1 ]]; then
  tui_task_add update "System update"
  tui_start update "this takes a few minutes"
  # The redirect is opened by this shell, which is root — sudo only lowers privilege for the
  # command itself, so the log lands where we want it.
  # shellcheck disable=SC2024
  if sudo -u "$USERNAME" -i omarchy-update -y >/var/log/omarchy-firstboot-update.log 2>&1; then
    tui_ok update "up to date"
  else
    tui_warn update "hit a snag — run 'omarchy-update' later (log: /var/log/omarchy-firstboot-update.log)"
  fi
fi
tui_commit

if [[ $DEFAULTED -eq 1 ]]; then
  tui_panel "$TUI_OK" "Ready — starting the desktop." \
    "Log in as ${TUI_B}$USERNAME${TUI_R} / ${TUI_B}$USERNAME${TUI_R}." \
    "Run ${TUI_B}passwd${TUI_R} after you log in to set your own password."
else
  tui_panel "$TUI_OK" "Ready — starting the desktop." "Logging in as ${TUI_B}$USERNAME${TUI_R}."
fi
tui_hint "Super is your Mac's $TUI_G_CMD key.  Menu: Cmd+Space   Terminal: Cmd+Ctrl+Return"
tui_hint "Health check any time: ${TUI_B}omarchy-parallels-verify${TUI_R}"

sleep 4
finish
