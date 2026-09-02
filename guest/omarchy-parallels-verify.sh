#!/bin/bash
# omarchy-parallels-verify — machine-readable health check for the Omarchy Parallels image.
#
# Exit 0 when every check passes, 1 otherwise. Emits one JSON object on stdout so the
# build pipeline, the first-boot OOBE, and bug reports all share a single source of truth.
#
# Run as root (the build pipeline does) or via sudo; per-user checks resolve the desktop
# user from the active graphical session rather than assuming a name.

set -uo pipefail

declare -A RESULT
FAIL=0

check() { # check <name> <ok:0|1> <detail>
  RESULT[$1]="$2|$3"
  [[ $2 -eq 0 ]] || FAIL=1
}

# --- resolve the desktop user from loginctl (survives the OOBE rename) ---
DESKTOP_USER=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$4=="seat0"{print $3; exit}')
[[ -z ${DESKTOP_USER:-} ]] && DESKTOP_USER=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$1!=""{u=$3} END{print u}')
DESKTOP_UID=$(id -u "${DESKTOP_USER:-nobody}" 2>/dev/null || echo "")

# --- boot / storage ---
ROOTDEV=$(findmnt -no SOURCE / 2>/dev/null)
check root_on_sda "$([[ $ROOTDEV == /dev/sda* ]] && echo 0 || echo 1)" "root=$ROOTDEV"

# --- display manager & session ---
check sddm_active "$([[ $(systemctl is-active sddm 2>/dev/null) == active ]] && echo 0 || echo 1)" "$(systemctl is-active sddm 2>/dev/null)"

HYPR_OK=1; HYPR_DETAIL="no Hyprland for ${DESKTOP_USER:-?}"
if [[ -n $DESKTOP_UID ]] && pgrep -u "$DESKTOP_USER" -x Hyprland >/dev/null 2>&1; then
  HYPR_OK=0; HYPR_DETAIL="pid $(pgrep -u "$DESKTOP_USER" -x Hyprland | head -1)"
fi
check hyprland_session "$HYPR_OK" "$HYPR_DETAIL"

QS_OK=1
[[ -n $DESKTOP_UID ]] && pgrep -u "$DESKTOP_USER" -f quickshell >/dev/null 2>&1 && QS_OK=0
check quickshell "$QS_OK" "shell bar process"

# --- display mode & scale (via hyprctl in the user's session) ---
MODE=""; SCALE=""
if [[ $HYPR_OK -eq 0 ]]; then
  SIG=$(ls -1t "/run/user/$DESKTOP_UID/hypr" 2>/dev/null | head -1)
  MON=$(sudo -u "$DESKTOP_USER" env HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)" \
        XDG_RUNTIME_DIR="/run/user/$DESKTOP_UID" HYPRLAND_INSTANCE_SIGNATURE="$SIG" \
        hyprctl monitors 2>/dev/null)
  MODE=$(awk 'NR==2{print $1}' <<<"$MON")
  SCALE=$(awk '/scale:/{print $2; exit}' <<<"$MON")
fi
check display_mode "$([[ $MODE == *x*@* ]] && echo 0 || echo 1)" "mode=${MODE:-none} scale=${SCALE:-?}"

# --- autoresize service (user unit) ---
AR_OK=1; AR_STATE="unknown"
if [[ -n $DESKTOP_UID ]]; then
  AR_STATE=$(sudo -u "$DESKTOP_USER" XDG_RUNTIME_DIR="/run/user/$DESKTOP_UID" \
             systemctl --user is-active parallels-autoresize 2>/dev/null)
  [[ $AR_STATE == active ]] && AR_OK=0
fi
check autoresize_service "$AR_OK" "$AR_STATE"

# --- network ---
check network_up "$(ip -4 route get 1.1.1.1 >/dev/null 2>&1 && echo 0 || echo 1)" "default route"
check dns_resolves "$(getent hosts mirror.archlinuxarm.org >/dev/null 2>&1 && echo 0 || echo 1)" "mirror.archlinuxarm.org"

REPO_OK=1
timeout 25 pacman -Sy --noconfirm >/dev/null 2>&1 && REPO_OK=0
check pacman_sync "$REPO_OK" "repo databases reachable"

# --- parallels tools ---
check prltoolsd "$([[ $(systemctl is-active prltoolsd 2>/dev/null) == active ]] && echo 0 || echo 1)" "$(systemctl is-active prltoolsd 2>/dev/null)"

# --- systemd overall ---
FAILED_UNITS=$(systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l | tr -d ' ')
check no_failed_units "$([[ $FAILED_UNITS -eq 0 ]] && echo 0 || echo 1)" "failed=$FAILED_UNITS"

# --- emit JSON ---
OMARCHY_VER=$(cat /usr/share/omarchy/version 2>/dev/null || echo unknown)
printf '{\n  "verdict": "%s",\n  "omarchy": "%s",\n  "kernel": "%s",\n  "user": "%s",\n  "checks": {\n' \
  "$([[ $FAIL -eq 0 ]] && echo pass || echo fail)" "$OMARCHY_VER" "$(uname -r)" "${DESKTOP_USER:-none}"
FIRST=1
for k in "${!RESULT[@]}"; do
  IFS='|' read -r ok detail <<<"${RESULT[$k]}"
  [[ $FIRST -eq 0 ]] && printf ',\n'
  printf '    "%s": {"ok": %s, "detail": "%s"}' "$k" "$([[ $ok -eq 0 ]] && echo true || echo false)" "$detail"
  FIRST=0
done
printf '\n  }\n}\n'
exit $FAIL
