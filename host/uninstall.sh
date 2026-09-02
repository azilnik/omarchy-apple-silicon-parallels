#!/bin/bash
# host/uninstall.sh — remove the Omarchy VM and its files. Asks before anything destructive.
set -uo pipefail
PRLCTL="/usr/local/bin/prlctl"
PVM="$HOME/Parallels/Omarchy.pvm"

echo "This removes the Omarchy VM registration and deletes $PVM (all data inside the VM)."
read -r -p "Type 'delete' to continue: " ANS </dev/tty
[[ $ANS == delete ]] || { echo "Aborted."; exit 1; }

UUID=$("$PRLCTL" list -a --no-header 2>/dev/null | awk '/Omarchy/{print $1; exit}' | tr -d '{}')
[[ -n $UUID ]] && "$PRLCTL" unregister "$UUID" 2>/dev/null ||
  echo "(unregister may need Pro edition — if the VM still shows in Parallels, right-click → Remove → Keep Files)"
[[ -d $PVM ]] && rm -rf "$PVM" && echo "Deleted $PVM"
defaults delete "com.parallels.Parallels Desktop" "{$UUID}.0.ConsoleWidgetScaleFactorWithDynres" 2>/dev/null || true
echo "Done."
