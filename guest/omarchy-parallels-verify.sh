#!/bin/bash
# omarchy-parallels-verify — health check for the Omarchy Parallels image.
#
# Exit 0 when every check passes, 1 otherwise.
#
#   omarchy-parallels-verify           pretty checklist on a terminal, JSON when piped
#   omarchy-parallels-verify --json    always JSON (what the build pipeline and tests read)
#   omarchy-parallels-verify --pretty  always the checklist
#
# The JSON is one object on stdout and is the single source of truth shared by the build
# pipeline, the first-boot OOBE and bug reports. The checklist is the same data rendered for
# a human — several of these checks take seconds (pacman -Sy can take 25), so on a terminal
# they stream in one at a time rather than leaving the screen blank for half a minute.
#
# Run as root (the build pipeline does) or via sudo; per-user checks resolve the desktop user
# from the active graphical session rather than assuming a name.

set -uo pipefail

MODE=auto
case "${1:-}" in
  --json)   MODE=json ;;
  --pretty) MODE=pretty ;;
  -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[ "$MODE" = auto ] && { if [ -t 1 ]; then MODE=pretty; else MODE=json; fi; }

TUI_LIB=${OMARCHY_TUI_LIB:-/usr/local/lib/omarchy-parallels/tui.sh}
if [ "$MODE" = pretty ] && [ -r "$TUI_LIB" ]; then
  # shellcheck source=/dev/null
  . "$TUI_LIB" && tui_init || MODE=json
else
  MODE=json
fi

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
KB_HOME=$(getent passwd "${DESKTOP_USER:-omarchy}" 2>/dev/null | cut -d: -f6)
HYPR_OK=1

# Every check is id | label | the thing it proves, in the order a human wants to read them.
CHECKS=(
  "root_on_sda|Root filesystem|boots from the SATA disk"
  "sddm_active|Display manager|SDDM is running"
  "hyprland_session|Hyprland session|the compositor is up"
  "quickshell|Quickshell bar|the desktop shell is running"
  "display_mode|Display mode|resolution and scale"
  "autoresize_service|Window autoresize|follows the Parallels window"
  "network_up|Network|default route"
  "dns_resolves|DNS|name resolution"
  "pacman_sync|Package mirrors|repo databases reachable"
  "prltoolsd|Parallels Tools|prltoolsd is running"
  "mac_keybinds|Mac keybindings|terminal-on-Ctrl-Return drop-in"
  "cursor_fix|Cursor fix|software cursors, no double cursor"
  "no_failed_units|systemd units|nothing in a failed state"
)

run_check() { # run_check <id>
  case "$1" in
    root_on_sda)
      local dev; dev=$(findmnt -no SOURCE / 2>/dev/null)
      check root_on_sda "$([[ $dev == /dev/sda* ]] && echo 0 || echo 1)" "$dev" ;;
    sddm_active)
      local s; s=$(systemctl is-active sddm 2>/dev/null)
      check sddm_active "$([[ $s == active ]] && echo 0 || echo 1)" "$s" ;;
    hyprland_session)
      local detail="no Hyprland for ${DESKTOP_USER:-?}"
      if [[ -n $DESKTOP_UID ]] && pgrep -u "$DESKTOP_USER" -x Hyprland >/dev/null 2>&1; then
        HYPR_OK=0; detail="pid $(pgrep -u "$DESKTOP_USER" -x Hyprland | head -1)"
      fi
      check hyprland_session "$HYPR_OK" "$detail" ;;
    quickshell)
      local ok=1
      [[ -n $DESKTOP_UID ]] && pgrep -u "$DESKTOP_USER" -f quickshell >/dev/null 2>&1 && ok=0
      check quickshell "$ok" "$([[ $ok -eq 0 ]] && echo running || echo "not running")" ;;
    display_mode)
      local mode='' scale='' sig mon
      if [[ $HYPR_OK -eq 0 ]]; then
        sig=$(ls -1t "/run/user/$DESKTOP_UID/hypr" 2>/dev/null | head -1)
        mon=$(sudo -u "$DESKTOP_USER" env HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)" \
              XDG_RUNTIME_DIR="/run/user/$DESKTOP_UID" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
              hyprctl monitors 2>/dev/null)
        mode=$(awk 'NR==2{print $1}' <<<"$mon")
        scale=$(awk '/scale:/{print $2; exit}' <<<"$mon")
      fi
      local pretty="none"
      [[ $mode == *x*@* ]] && pretty="${mode%@*} @ ${mode#*@} Hz · scale ${scale:-?}"
      pretty=${pretty/.[0-9][0-9]* Hz/ Hz}
      check display_mode "$([[ $mode == *x*@* ]] && echo 0 || echo 1)" "$pretty" ;;
    autoresize_service)
      local ok=1 state=unknown
      if [[ -n $DESKTOP_UID ]]; then
        state=$(sudo -u "$DESKTOP_USER" XDG_RUNTIME_DIR="/run/user/$DESKTOP_UID" \
                systemctl --user is-active parallels-autoresize 2>/dev/null)
        [[ $state == active ]] && ok=0
      fi
      check autoresize_service "$ok" "$state" ;;
    network_up)
      check network_up "$(ip -4 route get 1.1.1.1 >/dev/null 2>&1 && echo 0 || echo 1)" "default route" ;;
    dns_resolves)
      check dns_resolves "$(getent hosts mirror.archlinuxarm.org >/dev/null 2>&1 && echo 0 || echo 1)" "mirror.archlinuxarm.org" ;;
    pacman_sync)
      local ok=1; timeout 25 pacman -Sy --noconfirm >/dev/null 2>&1 && ok=0
      check pacman_sync "$ok" "repo databases reachable" ;;
    prltoolsd)
      local s; s=$(systemctl is-active prltoolsd 2>/dev/null)
      check prltoolsd "$([[ $s == active ]] && echo 0 || echo 1)" "$s" ;;
    mac_keybinds)
      local ok=1
      [[ -n $KB_HOME && -f "$KB_HOME/.config/hypr/bindings.lua" ]] && \
        grep -q "omarchy-parallels mac keybinds" "$KB_HOME/.config/hypr/bindings.lua" && ok=0
      check mac_keybinds "$ok" "terminal-on-ctrl-return drop-in" ;;
    cursor_fix)
      local ok=1
      [[ -n $KB_HOME && -f "$KB_HOME/.config/hypr/looknfeel.lua" ]] && \
        grep -q "no_hardware_cursors" "$KB_HOME/.config/hypr/looknfeel.lua" && ok=0
      check cursor_fix "$ok" "software cursors (no double cursor)" ;;
    no_failed_units)
      local n; n=$(systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l | tr -d ' ')
      check no_failed_units "$([[ $n -eq 0 ]] && echo 0 || echo 1)" \
        "$([[ $n -eq 0 ]] && echo "none failed" || echo "$n failed")" ;;
  esac
}

OMARCHY_VER=$(cat /usr/share/omarchy/version 2>/dev/null || echo unknown)

if [[ $MODE == pretty ]]; then
  tui_header "Omarchy for Parallels — health check" "omarchy $OMARCHY_VER · kernel $(uname -r)"
  for spec in "${CHECKS[@]}"; do
    IFS='|' read -r id label _ <<<"$spec"
    tui_task_add "$id" "$label"
  done
  for spec in "${CHECKS[@]}"; do
    IFS='|' read -r id label proves <<<"$spec"
    tui_start "$id" "$proves"
    run_check "$id"
    IFS='|' read -r ok detail <<<"${RESULT[$id]}"
    if [[ $ok -eq 0 ]]; then tui_ok "$id" "$detail"; else tui_fail "$id" "$detail"; fi
  done
  tui_commit
  PASSED=0
  for spec in "${CHECKS[@]}"; do
    IFS='|' read -r id _ _ <<<"$spec"
    [[ ${RESULT[$id]%%|*} -eq 0 ]] && PASSED=$((PASSED + 1))
  done
  if [[ $FAIL -eq 0 ]]; then
    tui_panel "$TUI_OK" "Healthy — all $PASSED checks passed." \
      "Nothing to do. This VM is set up the way the image intends."
  else
    NET_BAD=0
    for id in network_up dns_resolves pacman_sync; do
      [[ ${RESULT[$id]%%|*} -eq 0 ]] || NET_BAD=$((NET_BAD + 1))
    done
    if [[ $NET_BAD -ge 2 ]]; then
      tui_panel "$TUI_ERR" "$((${#CHECKS[@]} - PASSED)) of ${#CHECKS[@]} checks failed — this VM has no internet." \
        "That is almost always the host side: check Parallels → Configure → Hardware →" \
        "Network, and that your Mac itself is online. Nothing inside the VM needs changing." \
        "" \
        "If the network is fine, attach the JSON to a bug report:" \
        "  omarchy-parallels-verify --json"
    else
      tui_panel "$TUI_ERR" "$((${#CHECKS[@]} - PASSED)) of ${#CHECKS[@]} checks failed." \
        "Attach the JSON to a bug report:" \
        "  omarchy-parallels-verify --json"
    fi
  fi
  exit $FAIL
fi

# --- JSON: byte-for-byte the same contract the build pipeline and tests already read ---
for spec in "${CHECKS[@]}"; do
  IFS='|' read -r id _ _ <<<"$spec"
  run_check "$id"
done
printf '{\n  "verdict": "%s",\n  "omarchy": "%s",\n  "kernel": "%s",\n  "user": "%s",\n  "checks": {\n' \
  "$([[ $FAIL -eq 0 ]] && echo pass || echo fail)" "$OMARCHY_VER" "$(uname -r)" "${DESKTOP_USER:-none}"
FIRST=1
for spec in "${CHECKS[@]}"; do
  IFS='|' read -r k _ _ <<<"$spec"
  IFS='|' read -r ok detail <<<"${RESULT[$k]}"
  [[ $FIRST -eq 0 ]] && printf ',\n'
  printf '    "%s": {"ok": %s, "detail": "%s"}' "$k" "$([[ $ok -eq 0 ]] && echo true || echo false)" "$detail"
  FIRST=0
done
printf '\n  }\n}\n'
exit $FAIL
