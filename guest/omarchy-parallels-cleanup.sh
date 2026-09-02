#!/bin/bash
# omarchy-parallels-cleanup — one-shot, first boot only.
#
# On a freshly imported image the Qt input plugin (fcitx5) races the machine-id during cold start
# and quickshell crash-loops ~10x before the session settles (it recovers on its own; the crashes
# land before omarchy-crash-watch starts, so the user sees no toast). This clears the coredumps and
# any queued notifications those crashes leave, once the desktop has settled, then disables itself.
set -uo pipefail
[[ -f /var/lib/omarchy-parallels/cleanup-pending ]] || exit 0

sleep 45   # let the cold-start crash storm finish and the session settle

rm -f /var/lib/systemd/coredump/* 2>/dev/null || true
for h in /root /home/*; do
  rm -f "$h/.local/state/omarchy/notifications/"*.json 2>/dev/null || true
done

rm -f /var/lib/omarchy-parallels/cleanup-pending
systemctl disable omarchy-parallels-cleanup.service >/dev/null 2>&1 || true
exit 0
