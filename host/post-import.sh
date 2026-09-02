#!/bin/bash
# host/post-import.sh — per-machine host settings that cannot travel inside the image.
#
# The Retina "More Space" HiDPI setting lives in host preferences keyed by the VM's UUID,
# and the UUID is regenerated on import — so this must run on the recipient's Mac after
# the VM registers. We write the (undocumented) pref AND print the supported UI path.

set -uo pipefail
QUIET=0; [[ ${1:-} == --quiet ]] && QUIET=1
PRLCTL="/usr/local/bin/prlctl"

UUID=$("$PRLCTL" list -a --no-header 2>/dev/null | awk '/Omarchy/{print $1; exit}' | tr -d '{}')
if [[ -z $UUID ]]; then
  echo "post-import: no Omarchy VM registered yet" >&2; exit 1
fi

# Best-effort: undocumented key observed on Parallels 27 (ConsoleWidgetScaleFactorWithDynres=2
# is what View → Retina Resolution → More Space writes). Harmless if ignored by other versions.
defaults write "com.parallels.Parallels Desktop" "{$UUID}.0.ConsoleWidgetScaleFactorWithDynres" -int 2 2>/dev/null || true

if [[ $QUIET -eq 0 ]]; then
  cat <<EOF

    HiDPI: attempted automatically. If the desktop looks soft or tiny, set it by hand:
      Parallels menu bar → View → Retina Resolution → More Space
      (the guest adapts on its own within a few seconds — no reboot needed)

    Keyboard: macOS keeps Cmd+Space (Spotlight). Inside Omarchy use Cmd+Option+O for
    the menu, or forward the shortcut: Parallels → Preferences → Shortcuts.
EOF
fi
exit 0
