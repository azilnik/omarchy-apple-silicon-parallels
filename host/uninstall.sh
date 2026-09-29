#!/bin/bash
# host/uninstall.sh — remove the Omarchy VM and its files. Asks before anything destructive.
#
# Run from a clone of the repo; it shares the installer's terminal UI when lib/tui.sh is
# next to it, and falls back to plain text when it is not (e.g. copied out on its own).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PRLCTL="${OMARCHY_PRLCTL:-/usr/local/bin/prlctl}"
DEST="${OMARCHY_PARALLELS_DEST:-$HOME/Parallels}"
PVM="$DEST/Omarchy.pvm"

# shellcheck source=../lib/tui.sh
if [[ -r "$HERE/../lib/tui.sh" ]] && . "$HERE/../lib/tui.sh" 2>/dev/null && tui_init 2>/dev/null; then
  HAVE_TUI=1
else
  HAVE_TUI=0
  TUI_ERR=''; TUI_OK=''; TUI_WARN=''; TUI_DIM=''; TUI_B=''; TUI_R=''
fi

if [[ ! -d $PVM ]]; then
  printf '\n  No Omarchy VM found at %s — nothing to remove.\n\n' "$PVM"
  exit 0
fi

SIZE=$(du -sh "$PVM" 2>/dev/null | awk '{print $1}')

if [[ $HAVE_TUI -eq 1 ]]; then
  tui_header "Remove Omarchy for Parallels" "this cannot be undone"
  tui_panel "$TUI_WARN" "This deletes the VM and everything inside it" \
    "$PVM  ($SIZE)" \
    "Files you created inside Omarchy live in this bundle and go with it."
else
  printf '\nThis deletes %s (%s) and everything inside the VM. It cannot be undone.\n\n' "$PVM" "$SIZE"
fi

# A typed word, not a keypress: this is the one irreversible thing either script does, and it
# should be impossible to do by leaning on the return key.
printf '  %sType %sdelete%s to confirm:%s ' "$TUI_B" "$TUI_ERR" "$TUI_B" "$TUI_R"
read -r ANS </dev/tty || ANS=''
if [[ $ANS != delete ]]; then
  printf '\n  %sNothing was removed.%s\n\n' "$TUI_DIM" "$TUI_R"
  exit 1
fi

UUID=$("$PRLCTL" list -a --no-header 2>/dev/null | awk '/Omarchy/{print $1; exit}' | tr -d '{}')
[[ -z $UUID && -f "$PVM/config.pvs" ]] && \
  UUID=$(grep -o '<VmUuid>{[^}]*}</VmUuid>' "$PVM/config.pvs" | head -1 | tr -d '{}' | sed 's/<[^>]*>//g')

if [[ $HAVE_TUI -eq 1 ]]; then
  tui_task_add unreg "Unregistering from Parallels"
  tui_task_add files "Deleting the VM"
  tui_task_add prefs "Clearing host preferences"

  tui_start unreg
  if [[ -n $UUID ]] && "$PRLCTL" unregister "$UUID" >/dev/null 2>&1; then
    tui_ok unreg "removed from the VM list"
  else
    tui_warn unreg "could not unregister — in Parallels: right-click the VM → Remove → Keep Files"
  fi

  tui_start files "$SIZE to remove"
  rm -rf "$PVM" && tui_ok files "deleted $PVM" || tui_fail files "could not delete $PVM"

  tui_start prefs
  if [[ -n $UUID ]]; then
    defaults delete "com.parallels.Parallels Desktop" "{$UUID}.0.ConsoleWidgetScaleFactorWithDynres" 2>/dev/null || true
    defaults delete "com.parallels.Parallels Desktop" "User Preferences.Keyboard.Profile Assigns.{$UUID}" 2>/dev/null || true
  fi
  tui_ok prefs "HiDPI and keyboard-profile settings cleared"
  tui_commit
  tui_panel "$TUI_OK" "Removed." "Re-install any time with the one-line installer."
else
  [[ -n $UUID ]] && "$PRLCTL" unregister "$UUID" >/dev/null 2>&1
  rm -rf "$PVM" && echo "Deleted $PVM"
  [[ -n $UUID ]] && defaults delete "com.parallels.Parallels Desktop" "{$UUID}.0.ConsoleWidgetScaleFactorWithDynres" 2>/dev/null
  echo "Done."
fi
