#!/bin/bash
# test/tui/deploy-guest.sh — push the guest payload into a running VM and exercise its UI.
#
# Uses `prlctl exec` (over Parallels Tools) rather than SSH, because a YOLO-installed image
# leaves sshd off — the same channel test/run-tests.sh uses. Files are base64'd through the
# command line; the payload is ~20 KB, far inside any argv limit.
#
#   deploy-guest.sh <vm> push               install lib + guest scripts
#   deploy-guest.sh <vm> glyphs             render a glyph probe on a spare VT and screenshot it
#   deploy-guest.sh <vm> verify             run the health check on a spare VT and screenshot it
#   deploy-guest.sh <vm> rearm-firstboot    re-arm first boot so the OOBE runs again on reboot
#   deploy-guest.sh <vm> shot <name>        just capture the screen

set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
VM=${1:?usage: deploy-guest.sh <vm> <command>}
CMD=${2:?usage: deploy-guest.sh <vm> <command>}
PRLCTL=${PRLCTL:-/usr/local/bin/prlctl}
OUT="$REPO/build/out"
VT=${OMARCHY_TEST_VT:-4}
mkdir -p "$OUT"

X() { "$PRLCTL" exec "$VM" "$@" 2>&1; }

# prlctl exec forwards stdin to the guest process, so a plain `cat >` is the whole transfer.
# (Do not put an X call inside a `while read` loop: the guest process drains the loop's stdin.)
push_file() { # push_file <local> <remote> <mode>
  local src=$1 dst=$2 mode=$3 sum_local sum_remote
  X "install -d -m 755 $(dirname "$dst")" </dev/null >/dev/null
  "$PRLCTL" exec "$VM" "cat > '$dst' && chmod $mode '$dst'" < "$src" >/dev/null 2>&1
  sum_local=$(shasum -a 256 < "$src" | awk '{print $1}')
  sum_remote=$(X "sha256sum '$dst'" </dev/null | awk '{print $1}')
  if [ "$sum_local" = "$sum_remote" ]; then
    printf '  pushed %s (%s bytes)\n' "$dst" "$(wc -c < "$src" | tr -d ' ')"
  else
    printf '  FAILED %s (%s vs %s)\n' "$dst" "${sum_local:0:12}" "${sum_remote:0:12}" >&2
    return 1
  fi
}

# Run a command on a spare virtual terminal so we see exactly what a console user sees —
# TERM=linux, the real console font, eight colours — then photograph the framebuffer.
on_vt() { # on_vt <name> <shell-command>
  # Clear the VT and evict whatever was on it first: a leftover program from a previous run
  # keeps its output on screen, and a screenshot of that looks exactly like a successful run.
  X "fuser -k /dev/tty$VT 2>/dev/null; printf '\033[2J\033[H' > /dev/tty$VT; chvt $VT" </dev/null >/dev/null 2>&1
  sleep 1
  "$PRLCTL" exec "$VM" "openvt -c $VT -f -w -- /bin/bash -lc \"$2\"" </dev/null >/dev/null 2>&1 &
  local pid=$!
  sleep "${OMARCHY_SHOT_DELAY:-6}"
  "$PRLCTL" capture "$VM" --file "$OUT/$1.png" >/dev/null 2>&1
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo "captured $OUT/$1.png"
}

case "$CMD" in
  push)
    push_file "$REPO/lib/tui.sh" /usr/local/lib/omarchy-parallels/tui.sh 644
    for f in omarchy-parallels-verify omarchy-parallels-firstboot omarchy-parallels-cleanup omarchy-parallels-autoresize; do
      push_file "$REPO/guest/$f.sh" "/usr/local/bin/$f" 755
    done
    echo "pushed:"; X 'ls -l /usr/local/lib/omarchy-parallels/tui.sh /usr/local/bin/omarchy-parallels-*'
    ;;

  glyphs)
    # Ground truth for the console font: whether a glyph exists is a property of the loaded
    # font, not of the terminal type, so the only honest test is to draw it and look.
    X "cat > /tmp/glyphs.sh <<'PROBE'
printf '\n  omarchy-parallels glyph probe — TERM=%s  font=%s\n\n' \"\$TERM\" \"\$(setfont -O /dev/null 2>&1; grep -h FONT /etc/vconsole.conf 2>/dev/null || echo default)\"
printf '  tier3 spinner : ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏\n'
printf '  tier2 spinner : ▖ ▘ ▝ ▗\n'
printf '  marks         : ✓ ✗ ● ○ ◦ × · ▸ »\n'
printf '  bars          : █ ░ ▒ ▓  eighths ▏▎▍▌▋▊▉\n'
printf '  box           : ╭─╮ │ ╰─╯   ┌─┐ └─┘\n'
printf '  ellipsis/arrow: … → ⌘\n'
printf '\n  reference     : ABCdef 0123 |/-\\\\ +.#\n\n'
PROBE
chmod +x /tmp/glyphs.sh"
    on_vt "guest-glyphs" "bash /tmp/glyphs.sh; sleep 20"
    ;;

  verify)
    on_vt "guest-verify" "/usr/local/bin/omarchy-parallels-verify --pretty; sleep 25"
    ;;

  rearm-firstboot)
    X 'install -d /var/lib/omarchy-parallels
       touch /var/lib/omarchy-parallels/firstboot-pending
       systemctl enable omarchy-parallels-firstboot.service
       systemctl is-enabled omarchy-parallels-firstboot.service'
    ;;

  shot)
    "$PRLCTL" capture "$VM" --file "$OUT/${3:-shot}.png" && echo "captured $OUT/${3:-shot}.png"
    ;;

  *) echo "unknown command: $CMD" >&2; exit 2 ;;
esac
