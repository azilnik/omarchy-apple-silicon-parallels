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
