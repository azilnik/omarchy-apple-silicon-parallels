#!/bin/bash
# omarchy-parallels-welcome — the handful of things that work differently because Omarchy is
# running in Parallels on a Mac.
#
# Shown once, in a floating terminal, the first time the desktop comes up: a post-boot hook
# (installed at ~/.config/omarchy/hooks/post-boot.d/) launches it through Omarchy's own
# presentation wrapper, so it is framed like every other Omarchy walkthrough. Run it again any
# time by name.
#
# This deliberately does NOT repeat what Omarchy already teaches. Omarchy's own first-run
# notification covers Super+K and Super+Space; the only things it cannot know are that Super
# is Cmd on this keyboard, that Parallels has taken Cmd+Return, and how to get crisp text.

set -uo pipefail

ONCE=0
case "${1:-}" in
  --once) ONCE=1 ;;
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# The once-guard uses Omarchy's own marker store, so it behaves like every other one-shot.
if [ "$ONCE" -eq 1 ]; then
  omarchy-done check omarchy-parallels-welcome 2>/dev/null && exit 0
fi

TUI_LIB=${OMARCHY_TUI_LIB:-/usr/local/lib/omarchy-parallels/tui.sh}
# shellcheck source=../lib/tui.sh
if [ ! -r "$TUI_LIB" ] || ! . "$TUI_LIB" 2>/dev/null || ! tui_init 2>/dev/null; then
  cat <<'PLAIN'

  Omarchy in Parallels — what is different on a Mac

    Super is your Cmd key.  Menu: Cmd+Space   All shortcuts: Cmd+K
    Terminal: Cmd+Ctrl+Return  (Parallels keeps Cmd+Return for full screen)
    Soft text? Parallels menu bar -> View -> Retina Resolution -> More Space
    Health check: omarchy-parallels-verify

PLAIN
  omarchy-done mark omarchy-parallels-welcome 2>/dev/null
  exit 0
fi

tui_label_width 22
tui_header "Omarchy on your Mac" "the few things that work differently in a VM"

tui_kv "$TUI_ACCENT" "$TUI_G_ARROW" "Super is ⌘ Cmd"     "every Omarchy shortcut you read uses Super"
tui_kv "$TUI_ACCENT" "$TUI_G_ARROW" "Open the menu"      "Cmd + Space"
tui_kv "$TUI_ACCENT" "$TUI_G_ARROW" "Open a terminal"    "Cmd + Ctrl + Return"
tui_kv "$TUI_ACCENT" "$TUI_G_ARROW" "See every shortcut" "Cmd + K"

tui_panel "$TUI_DIM" "Why Ctrl in the terminal shortcut?" \
  "Parallels claims Cmd+Return for full screen before the VM ever sees it, so Omarchy's" \
  "own Super+Return cannot reach you. Cmd+Ctrl+Return always works." \
  "" \
  "To get the native binding back, turn that one shortcut off in Parallels:" \
  "Preferences → Shortcuts → Application Shortcuts."

tui_hint "Text looking soft? Parallels menu bar $TUI_G_TO View $TUI_G_TO Retina Resolution $TUI_G_TO ${TUI_B}More Space${TUI_R}."
tui_hint "Check this VM is healthy: ${TUI_B}omarchy-parallels-verify${TUI_R}"
tui_hint "Show this again: ${TUI_B}omarchy-parallels-welcome${TUI_R}"

if [ -f /var/lib/omarchy-parallels/default-password ]; then
  tui_panel "$TUI_WARN" "This VM still uses the password it shipped with" \
    "You are logged in automatically, but you need a password for ${TUI_B}sudo${TUI_R} and the lock screen." \
    "It is currently ${TUI_B}omarchy${TUI_R}. Change it here: run ${TUI_B}passwd${TUI_R}."
fi

omarchy-done mark omarchy-parallels-welcome 2>/dev/null

# When this is a window of its own, hold it open on our own terms rather than relying on the
# launcher to append something — the window closing the instant it finishes rendering is
# worse than not showing it at all.
if [ "${TUI_HAS_TTY:-0}" -eq 1 ] && [ "$ONCE" -eq 1 ]; then
  printf '     %spress any key to close%s ' "$TUI_FAINT" "$TUI_R"
  _tui_raw_on; _tui_readkey; _tui_raw_off
  printf '\n'
fi
exit 0
