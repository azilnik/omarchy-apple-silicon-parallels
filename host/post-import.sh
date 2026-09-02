#!/bin/bash
# host/post-import.sh — per-machine host settings that cannot travel inside the image.
#
# The Retina "More Space" HiDPI setting lives in host preferences keyed by the VM's UUID,
# and the UUID is regenerated on import — so this must run on the recipient's Mac after
# the VM registers. We write the (undocumented) pref AND print the supported UI path.

set -uo pipefail
QUIET=0; [[ ${1:-} == --quiet ]] && QUIET=1
PRLCTL="/usr/local/bin/prlctl"
PVM="${OMARCHY_PVM:-$HOME/Parallels/Omarchy.pvm}"

# UUID from prlctl when available (most editions), else from the registered VM's config (B3).
UUID=""
[[ -x $PRLCTL ]] && UUID=$("$PRLCTL" list -a --no-header 2>/dev/null | awk '/Omarchy/{print $1; exit}' | tr -d '{}')
[[ -z $UUID && -f "$PVM/config.pvs" ]] && \
  UUID=$(grep -o '<VmUuid>{[^}]*}</VmUuid>' "$PVM/config.pvs" | head -1 | tr -d '{}' | sed 's/<[^>]*>//g')
if [[ -z $UUID ]]; then
  echo "post-import: couldn't find the VM's UUID — set HiDPI by hand:" >&2
  echo "  Parallels → View → Retina Resolution → More Space" >&2
  exit 0
fi

# HiDPI: undocumented key observed on Parallels 27 (ConsoleWidgetScaleFactorWithDynres=2 is what
# View → Retina Resolution → More Space writes). Harmless if ignored by other versions.
defaults write "com.parallels.Parallels Desktop" "{$UUID}.0.ConsoleWidgetScaleFactorWithDynres" -int 2 2>/dev/null || true

# Keyboard: assign the "Linux" profile to this VM. That profile forwards macOS *system*
# shortcuts (Cmd+Space, Cmd+Tab) to the guest, so Omarchy's Super+Space menu etc. work
# natively. This assignment is keyed by VM UUID, which regenerates on import — so it can't
# ship in the image and has to be (re)written here. Parallels reads it on next launch.
defaults write "com.parallels.Parallels Desktop" "User Preferences.Keyboard.Profile Assigns.{$UUID}" -string "Linux" 2>/dev/null || true

if [[ $QUIET -eq 0 ]]; then
  cat <<EOF

    HiDPI: set automatically. If the desktop still looks soft, do it by hand:
      Parallels menu bar → View → Retina Resolution → More Space  (adapts in seconds, no reboot)

    Keyboard: the Linux shortcut profile is assigned, so Cmd+Space opens the Omarchy menu
    (not Spotlight) while the VM is focused. Two Parallels app shortcuts still win over the
    guest — if you want them back in Omarchy, turn them off once in
    Parallels → Preferences → Shortcuts → Application Shortcuts:
      • Cmd+Return  (Enter Full Screen)  — frees Omarchy's Super+Return = terminal
      • Cmd+Q       (Quit)               — frees Omarchy's Super+Q = close window
    Until then, the image binds a Mac-safe terminal on Cmd+Ctrl+Return that always works.
EOF
fi
exit 0
