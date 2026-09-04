# shellcheck shell=bash
# shellcheck disable=SC2004  # $ in array subscripts is deliberate: it reads as an index, not maths
# shellcheck disable=SC2034  # TUI_* are this library's public surface; callers use them
# shellcheck disable=SC1003  # '\\' is a literal backslash — the ASCII spinner's fourth frame
# lib/tui.sh — portable terminal UI primitives for omarchy-apple-silicon-parallels.
#
# One implementation, two very different terminals:
#   host  — macOS /bin/bash 3.2.57 under `curl … | bash`, usually a 24-bit-colour Terminal/iTerm
#   guest — Arch ARM tty1, TERM=linux, 8 colours, a 256-glyph console font, running as root
#
# Everything here is bash-3.2 clean: no associative arrays, no `read -t <fraction>`, no
# `${var^^}`, no mapfile. Task state lives in parallel indexed arrays keyed by a linear id
# scan; the lists are ~8 items long, so the scan is cheaper than any cleverness would be.
#
# PERFORMANCE CONTRACT: the render path does not fork. No command substitution, no subshells,
# no external commands inside _tui_render or the menu loops — everything composes with
# `printf -v` and parameter expansion, and each frame is emitted as a single write(2). A frame
# that costs a dozen forks is what makes a shell TUI feel like a shell script.
#
# Capability tiers (auto-detected; override with OMARCHY_TUI=fancy|basic|plain):
#   3 fancy — UTF-8 on a real terminal: braille spinner, eighth-block bars, ✓/✗
#   2 basic — UTF-8 on a console font: quadrant spinner, block/shade bars, ●/×
#   1 plain — ASCII, no animation, one line per state change (pipes, CI, NO_COLOR, dumb)
#
# The renderer keeps a "live region": N lines at the bottom of the screen rewritten in place
# with cursor-up + erase-line. It never clears the screen and never scrolls on its own, so
# scrollback stays intact and a plain-mode run reads like an ordinary log.
#
# IMPORTANT: while a live region is open nothing else may write to stdout/stderr — a stray
# line desynchronises the cursor accounting. Redirect subprocess output to a log and surface
# it with tui_fail/tui_note once the region is committed.

# ---------------------------------------------------------------- capability detection

tui_init() {
  TUI_TTY=0; [ -t 1 ] && TUI_TTY=1
  # A permission test on /dev/tty is not enough: the node exists and is readable even when the
  # process has no controlling terminal, and only the open(2) fails — with a shell error we
  # cannot suppress after the fact. Try the open once, in a subshell, and remember the answer.
  TUI_HAS_TTY=0
  ( exec </dev/tty >/dev/tty ) 2>/dev/null && TUI_HAS_TTY=1

  _tui_measure

  # Colour depth. NO_COLOR (https://no-color.org) and a non-tty both mean "no escapes at all".
  local depth=0
  if [ "$TUI_TTY" -eq 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    case "${COLORTERM:-}" in truecolor|24bit) depth=24 ;; esac
    if [ "$depth" -eq 0 ]; then
      case "${TERM:-}" in *256color*|*direct*) depth=8 ;; *) depth=4 ;; esac
    fi
  fi

  # Unicode. The locale is the primary signal, but plenty of perfectly UTF-8-capable terminals
  # arrive with no LANG at all (ssh without SendEnv, tmux, ttyd, launchd-spawned shells), and
  # falling back to ASCII there is needlessly ugly. So also trust the emulator when it
  # identifies itself: a TERM_PROGRAM, a truecolor COLORTERM, or an xterm-family TERM on macOS
  # all mean a modern emulator whose encoding is UTF-8 regardless of what the locale claims.
  # Anything genuinely 8-bit (a serial console, TERM=vt100) matches none of these.
  local utf8=0
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *UTF-8*|*utf8*|*UTF8*) utf8=1 ;; esac
  if [ "$utf8" -eq 0 ]; then
    [ -n "${TERM_PROGRAM:-}" ] && utf8=1
    case "${COLORTERM:-}" in truecolor|24bit) utf8=1 ;; esac
    case "${OSTYPE:-}" in darwin*) case "${TERM:-}" in xterm*|*256color*) utf8=1 ;; esac ;; esac
  fi
  TUI_TIER=1
  if [ "$utf8" -eq 1 ] && [ "$depth" -gt 0 ]; then
    case "${TERM:-}" in linux|vt*|ansi|screen) TUI_TIER=2 ;; *) TUI_TIER=3 ;; esac
  fi

  case "${OMARCHY_TUI:-}" in
    fancy) TUI_TIER=3 ;;
    basic) TUI_TIER=2 ;;
    plain) TUI_TIER=1; depth=0 ;;
  esac
  [ -n "${CI:-}" ] && TUI_TIER=1

  # Bash measures strings in CHARACTERS only when its own LC_CTYPE is a multibyte locale.
  # With LANG unset every ${#s} and ${s:i:1} counts BYTES instead, which silently shreds
  # every glyph we slice and renders progress bars a third of their intended width. Repair
  # LC_CTYPE if we can; if we cannot, drop to ASCII, where bytes and characters agree.
  [ "$TUI_TIER" -ge 2 ] && _tui_fix_ctype

  TUI_LIVE=0
  [ "$TUI_TTY" -eq 1 ] && [ "$TUI_TIER" -ge 2 ] && [ "${TUI_NARROW:-0}" -eq 0 ] && TUI_LIVE=1
  # Appended to every line printed outside the live region. Empty when we are not driving a
  # terminal, so a piped log never gains an escape sequence.
  if [ "$TUI_LIVE" -eq 1 ]; then TUI_EOL=$'\033[K'; else TUI_EOL=''; fi

  _tui_probe_bg
  _tui_palette "$depth"
  _tui_glyphs "$TUI_TIER"
  _tui_precompute

  _TUI_DRAWN=0; _TUI_SPIN=0; _TUI_N=0; _TUI_MORPH_AT=-1; _TUI_MORPH_CH=''; _TUI_SEEN=''
  _TUI_LABELW=16
  _TUI_ID=(); _TUI_LABEL=(); _TUI_STATE=(); _TUI_DETAIL=(); _TUI_BAR=()
  _tui_stty_save=''

  trap '_tui_measure' WINCH 2>/dev/null || true
  trap '_tui_atexit' EXIT
  trap '_tui_interrupt' INT
  trap '_tui_interrupt' TERM
  [ "$TUI_LIVE" -eq 1 ] && printf '\033[?25l'
  return 0
}

_tui_fix_ctype() {
  local probe='…' c
  [ "${#probe}" -eq 1 ] && return 0
  # BSD accepts the bare "UTF-8"; glibc ships C.UTF-8 since 2.35 and en_US.UTF-8 nearly always.
  for c in C.UTF-8 en_US.UTF-8 UTF-8 C.utf8 en_US.utf8; do
    LC_CTYPE=$c
    [ "${#probe}" -eq 1 ] && return 0
  done
  unset LC_CTYPE
  TUI_TIER=1
  return 1
}

_tui_measure() {
  local c=''
  if [ "${TUI_HAS_TTY:-0}" -eq 1 ]; then
    c=$(stty size 2>/dev/null </dev/tty | awk '{print $2}')
  fi
  [ -z "$c" ] && c=$(tput cols 2>/dev/null)
  case "$c" in ''|*[!0-9]*) c=80 ;; esac
  # Below the minimum, drop out of live rendering entirely rather than clamping upward:
  # clamping would emit lines wider than the terminal, each wrapping to two physical rows
  # while the cursor bookkeeping counts one, and the region would walk down the screen
  # eating scrollback. A narrow tmux split is a real place to end up.
  if [ "$c" -lt 44 ]; then TUI_NARROW=1; TUI_LIVE=0; else TUI_NARROW=0; fi
  [ "$c" -gt 100 ] && c=100
  if [ "${TUI_COLS:-0}" != "$c" ]; then
    TUI_COLS=$c
    _TUI_DRAWN=0        # the wrap points moved; start a fresh region rather than corrupt the old
  fi
}

# Ask the terminal what colour its background is (OSC 11). Worth the trouble: macOS
# Terminal.app ships a WHITE profile, and a palette tuned for dark terminals puts the green
# check mark at 1.75:1 there — a glyph this UI repeats on every line, invisible. Terminals
# that do not answer cost us 0.2s and fall back to a palette that clears ~4:1 on both.
_tui_probe_bg() {
  TUI_BG=unknown
  case "${OMARCHY_TUI_BG:-}" in light|dark) TUI_BG=$OMARCHY_TUI_BG; return 0 ;; esac
  [ "${TUI_HAS_TTY:-0}" -eq 1 ] && [ "${TUI_TTY:-0}" -eq 1 ] || return 0
  case "${TERM:-}" in linux|dumb|'') return 0 ;; esac

  local save resp r g b lum
  save=$(stty -g 2>/dev/null </dev/tty) || return 0
  stty -echo -icanon min 0 time 1 2>/dev/null </dev/tty
  printf '\033]11;?\033\\' > /dev/tty 2>/dev/null
  IFS= read -r resp 2>/dev/null </dev/tty
  # Drain anything else the terminal queued, so a late reply cannot be mistaken for a
  # keypress by the first menu.
  stty min 0 time 0 2>/dev/null </dev/tty
  IFS= read -r _tui_junk 2>/dev/null </dev/tty
  stty "$save" 2>/dev/null </dev/tty

  case "$resp" in
    *rgb:*)
      resp=${resp#*rgb:}
      r=${resp%%/*}; resp=${resp#*/}
      g=${resp%%/*}; b=${resp#*/}
      b=${b%%[!0-9A-Fa-f]*}
      # Components come back as 2, 4 or 4-hex-digit-per-channel; the top byte is enough.
      r=$((16#${r:0:2})); g=$((16#${g:0:2})); b=$((16#${b:0:2}))
      lum=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
      if [ "$lum" -ge 128 ]; then TUI_BG=light; else TUI_BG=dark; fi ;;
  esac
  return 0
}

_tui_palette() { # _tui_palette <depth:0|4|8|24>
  case "$1" in
    24)
      case "${TUI_BG:-unknown}" in
        light) TUI_ACCENT=$'\033[38;2;93;58;214m';  TUI_OK=$'\033[38;2;24;114;62m'
               TUI_WARN=$'\033[38;2;138;88;0m';     TUI_ERR=$'\033[38;2;179;38;30m'
               TUI_DIM=$'\033[38;2;92;92;102m';     TUI_FAINT=$'\033[38;2;138;138;148m' ;;
        dark)  TUI_ACCENT=$'\033[38;2;167;139;250m'; TUI_OK=$'\033[38;2;134;213;150m'
               TUI_WARN=$'\033[38;2;240;180;96m';    TUI_ERR=$'\033[38;2;242;120;120m'
               TUI_DIM=$'\033[38;2;150;150;162m';    TUI_FAINT=$'\033[38;2;110;110;122m' ;;
        # No answer from the terminal: no single hue clears 4.5:1 against both white and a
        # dark ground, so these sit near the 4.1:1 ceiling and stay readable either way.
        *)     TUI_ACCENT=$'\033[38;2;133;98;232m'; TUI_OK=$'\033[38;2;47;158;86m'
               TUI_WARN=$'\033[38;2;168;118;26m';   TUI_ERR=$'\033[38;2;207;90;90m'
               TUI_DIM=$'\033[38;2;119;119;127m';   TUI_FAINT=$'\033[2;38;2;119;119;127m' ;;
      esac ;;
    8)
      case "${TUI_BG:-unknown}" in
        light) TUI_ACCENT=$'\033[38;5;92m';  TUI_OK=$'\033[38;5;28m'
               TUI_WARN=$'\033[38;5;94m';    TUI_ERR=$'\033[38;5;124m'
               TUI_DIM=$'\033[38;5;241m';    TUI_FAINT=$'\033[38;5;245m' ;;
        dark)  TUI_ACCENT=$'\033[38;5;141m'; TUI_OK=$'\033[38;5;114m'
               TUI_WARN=$'\033[38;5;179m';   TUI_ERR=$'\033[38;5;210m'
               TUI_DIM=$'\033[38;5;248m';    TUI_FAINT=$'\033[38;5;243m' ;;
        *)     TUI_ACCENT=$'\033[38;5;98m';  TUI_OK=$'\033[38;5;71m'
               TUI_WARN=$'\033[38;5;136m';   TUI_ERR=$'\033[38;5;167m'
               TUI_DIM=$'\033[38;5;244m';    TUI_FAINT=$'\033[2;38;5;244m' ;;
      esac ;;
    # The Linux console gives exactly three greys: 1;37 white, 37 grey, 1;30 near-black.
    # 37 is ALSO the default foreground, so using it for detail text would render the whole
    # row in one flat colour — the ramp has to start one notch higher than you would expect.
    4)  TUI_ACCENT=$'\033[1;36m'; TUI_OK=$'\033[1;32m'; TUI_WARN=$'\033[1;33m'
        TUI_ERR=$'\033[1;31m';    TUI_DIM=$'\033[37m';  TUI_FAINT=$'\033[37m'
        TUI_FG=$'\033[1;37m';     TUI_TRACK=$'\033[1;30m' ;;
    *)  TUI_ACCENT=''; TUI_OK=''; TUI_WARN=''; TUI_ERR=''; TUI_DIM=''; TUI_FAINT='' ;;
  esac
  [ -z "${TUI_FG+x}" ] && TUI_FG=''
  [ -z "${TUI_TRACK+x}" ] && TUI_TRACK=$TUI_FAINT
  if [ "$1" -gt 0 ]; then TUI_B=$'\033[1m'; TUI_R=$'\033[0m'; else TUI_B=''; TUI_R=''; fi
}

_tui_glyphs() { # _tui_glyphs <tier>
  case "$1" in
    3) TUI_SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
       TUI_G_OK='✓'; TUI_G_FAIL='✗'; TUI_G_WARN='!'; TUI_G_PENDING='·'
       TUI_G_MORPH=(· ◦ ● ✓); TUI_G_ARROW='▸'; TUI_G_BULLET='·'
       TUI_BAR_FULL='█'; TUI_BAR_EMPTY='▒'; TUI_BAR_PARTIAL=(▏ ▎ ▍ ▌ ▋ ▊ ▉)
       TUI_G_RULE='─'; TUI_G_TL='╭'; TUI_G_TR='╮'; TUI_G_BL='╰'; TUI_G_BR='╯'; TUI_G_V='│'
       TUI_G_TO='→'; TUI_G_CMD='⌘ Cmd'; TUI_ELL='…'
       TUI_G_UP='↑'; TUI_G_DN='↓'; TUI_G_ON='✓'; TUI_G_OFF=' '; TUI_G_RAIL='▌' ;;
    # Tier 2 is the Linux console. Its built-in font has 256 glyphs and no fallback: an
    # unmapped codepoint is drawn as some *other* glyph, silently. Every character below was
    # photographed on a real tty1 (test/tui/deploy-guest.sh glyphs) and renders as itself.
    # Notably absent, and previously assumed present: braille, quadrant blocks (all four
    # collapse to one glyph, so a quadrant spinner does not appear to move at all), eighth
    # blocks, ✓, ✗, … and ⌘. The half-blocks below rotate; √ reads as a check; ░▒▓█ are four
    # distinct shades.
    2) TUI_SPINNER=(▀ ▐ ▄ ▌)
       TUI_G_OK='■'; TUI_G_FAIL='×'; TUI_G_WARN='!'; TUI_G_PENDING='·'
       TUI_G_MORPH=(· ▒ ▓ ■); TUI_G_ARROW='▶'; TUI_G_BULLET='·'
       TUI_BAR_FULL='█'; TUI_BAR_EMPTY='▒'; TUI_BAR_PARTIAL=()
       TUI_G_RULE='─'; TUI_G_TL='┌'; TUI_G_TR='┐'; TUI_G_BL='└'; TUI_G_BR='┘'; TUI_G_V='│'
       TUI_G_TO='→'; TUI_G_CMD='Cmd'; TUI_ELL='...'
       TUI_G_UP='↑'; TUI_G_DN='↓'; TUI_G_ON='■'; TUI_G_OFF=' '; TUI_G_RAIL='▌' ;;
    *) TUI_SPINNER=('|' '/' '-' '\')
       TUI_G_OK='+'; TUI_G_FAIL='x'; TUI_G_WARN='!'; TUI_G_PENDING='.'
       TUI_G_MORPH=('+'); TUI_G_ARROW='>'; TUI_G_BULLET='-'
       TUI_BAR_FULL='#'; TUI_BAR_EMPTY='.'; TUI_BAR_PARTIAL=()
       TUI_G_RULE='-'; TUI_G_TL='+'; TUI_G_TR='+'; TUI_G_BL='+'; TUI_G_BR='+'; TUI_G_V='|'
       TUI_G_TO='->'; TUI_G_CMD='Cmd'; TUI_ELL='...'
       TUI_G_UP='up'; TUI_G_DN='down'; TUI_G_ON='x'; TUI_G_OFF=' '; TUI_G_RAIL='|' ;;
  esac
}

# Runs of every repeated glyph, precomputed once as prefix arrays: _TUI_FULL[k] is exactly k
# copies of the bar glyph. Rendering a bar is then two array lookups instead of a loop — and,
# unlike slicing one long string, it stays correct even where the locale is byte-oriented.
_tui_precompute() {
  local i=1
  _TUI_FULL=(''); _TUI_EMPTY=(''); _TUI_RULE=(''); _TUI_SP=('')
  while [ "$i" -le 104 ]; do
    _TUI_FULL[$i]="${_TUI_FULL[$((i - 1))]}$TUI_BAR_FULL"
    _TUI_EMPTY[$i]="${_TUI_EMPTY[$((i - 1))]}$TUI_BAR_EMPTY"
    _TUI_RULE[$i]="${_TUI_RULE[$((i - 1))]}$TUI_G_RULE"
    _TUI_SP[$i]="${_TUI_SP[$((i - 1))]} "
    i=$((i + 1))
  done
}

# ---------------------------------------------------------------- fork-free string helpers

_tui_pad() { # _tui_pad <outvar> <text> <width> — truncate or right-pad to exactly <width>
  local __t=$2 __w=$3
  if [ "$__w" -le "${#TUI_ELL}" ]; then
    printf -v "$1" '%s' "${__t:0:$__w}"; return
  elif [ "${#__t}" -gt "$__w" ]; then
    __t="${__t:0:$((__w - ${#TUI_ELL}))}$TUI_ELL"
  else
    __t="$__t${_TUI_SP[$((__w - ${#__t}))]}"
  fi
  printf -v "$1" '%s' "$__t"
}

_tui_trunc() { # _tui_trunc <outvar> <text> <max>
  local __t=$2 __m=$3
  [ "$__m" -lt 1 ] && __m=1
  if [ "$__m" -le "${#TUI_ELL}" ]; then __t="${__t:0:$__m}"
  elif [ "${#__t}" -gt "$__m" ]; then __t="${__t:0:$((__m - ${#TUI_ELL}))}$TUI_ELL"; fi
  printf -v "$1" '%s' "$__t"
}

tui_human_bytes() { # tui_human_bytes <outvar> <bytes> — "3.72 GB" / "184 MB" / "912 KB"
  local b=${2:-0}
  case "$b" in ''|*[!0-9]*) b=0 ;; esac
  if   [ "$b" -ge 1073741824 ]; then printf -v "$1" '%d.%02d GB' $((b / 1073741824)) $((b % 1073741824 * 100 / 1073741824))
  elif [ "$b" -ge 1048576 ];    then printf -v "$1" '%d.%d MB' $((b / 1048576)) $((b % 1048576 * 10 / 1048576))
  elif [ "$b" -ge 1024 ];       then printf -v "$1" '%d KB' $((b / 1024))
  else printf -v "$1" '%d B' "$b"; fi
}

tui_human_time() { # tui_human_time <outvar> <seconds> — "1h 04m" / "3m 21s" / "48s"
  local s=${2:-0}
  case "$s" in ''|*[!0-9]*) s=0 ;; esac
  if   [ "$s" -ge 3600 ]; then printf -v "$1" '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
  elif [ "$s" -ge 60 ];   then printf -v "$1" '%dm %02ds' $((s / 60)) $((s % 60))
  else printf -v "$1" '%ds' "$s"; fi
}

tui_bar() { # tui_bar <outvar> <done> <total> <width>
  # Fill and track are drawn in different colours — a bar tinted end to end reads as one
  # solid block and loses the very thing it exists to show. The leading eighth-block gives
  # sub-character resolution, so slow progress still visibly moves.
  local d=${2:-0} t=${3:-1} w=${4:-24} eighths full part out
  case "$d" in ''|*[!0-9]*) d=0 ;; esac
  case "$t" in ''|*[!0-9]*) t=1 ;; esac
  [ "$t" -le 0 ] && t=1
  [ "$d" -gt "$t" ] && d=$t
  eighths=$((d * w * 8 / t)); full=$((eighths / 8)); part=$((eighths % 8))
  [ "$full" -gt "$w" ] && { full=$w; part=0; }
  out="$TUI_ACCENT${_TUI_FULL[$full]}"
  if [ "${#TUI_BAR_PARTIAL[@]}" -gt 0 ] && [ "$part" -gt 0 ] && [ "$full" -lt "$w" ]; then
    out="$out${TUI_BAR_PARTIAL[$((part - 1))]}$TUI_TRACK${_TUI_EMPTY[$((w - full - 1))]}$TUI_R"
  else
    out="$out$TUI_TRACK${_TUI_EMPTY[$((w - full))]}$TUI_R"
  fi
  printf -v "$1" '%s' "$out"
}

# bash 3.2 has no fractional `read -t`, so this is one fork per frame — 2.3 ms of it, plus a
# near-constant ~10 ms of timer slack whatever duration you ask for. 0.05 lands at ~12 fps.
_tui_sleep_frame() { sleep 0.05; }

# ---------------------------------------------------------------- task list

tui_tasks_reset() { # start a fresh list (after a menu, say) without disturbing scrollback
  _TUI_N=0; _TUI_DRAWN=0; _TUI_SEEN=''; _TUI_MORPH_AT=-1; _TUI_LABELW=16
  _TUI_ID=(); _TUI_LABEL=(); _TUI_STATE=(); _TUI_DETAIL=(); _TUI_BAR=()
}

tui_task_add() { # tui_task_add <id> <label>
  # The label column is as wide as it needs to be and no wider. A fixed 26 leaves a nine-column
  # river through the guest's health check, whose longest label is much shorter than the host's.
  [ "${#2}" -ge "$((_TUI_LABELW - 2))" ] && _TUI_LABELW=$(( ${#2} + 2 ))
  [ "$_TUI_LABELW" -gt 26 ] && _TUI_LABELW=26
  _TUI_ID[$_TUI_N]=$1; _TUI_LABEL[$_TUI_N]=$2
  _TUI_STATE[$_TUI_N]=pending; _TUI_DETAIL[$_TUI_N]=''; _TUI_BAR[$_TUI_N]=''
  _TUI_N=$((_TUI_N + 1))
}

_tui_idx() { # _tui_idx <id> — sets _TUI_I to the array index, or -1
  _TUI_I=0
  while [ "$_TUI_I" -lt "$_TUI_N" ]; do
    [ "${_TUI_ID[$_TUI_I]}" = "$1" ] && return 0
    _TUI_I=$((_TUI_I + 1))
  done
  _TUI_I=-1; return 1
}

tui_start() { # tui_start <id> [detail]
  _tui_idx "$1" || return 0
  _TUI_STATE[$_TUI_I]=active; _TUI_DETAIL[$_TUI_I]=${2:-}; _TUI_BAR[$_TUI_I]=''
  _tui_render
}

tui_detail() { _tui_idx "$1" || return 0; _TUI_DETAIL[$_TUI_I]=${2:-}; _tui_render; }

tui_progress() { # tui_progress <id> <detail> <done>/<total>
  _tui_idx "$1" || return 0
  _TUI_DETAIL[$_TUI_I]=${2:-}; _TUI_BAR[$_TUI_I]=${3:-}
  _tui_render
}

tui_warn() { _tui_idx "$1" || return 0; _TUI_STATE[$_TUI_I]=warn; _TUI_DETAIL[$_TUI_I]=${2:-}; _TUI_BAR[$_TUI_I]=''; _tui_render; }
tui_fail() { _tui_idx "$1" || return 0; _TUI_STATE[$_TUI_I]=fail; _TUI_DETAIL[$_TUI_I]=${2:-}; _TUI_BAR[$_TUI_I]=''; _tui_render; }

tui_ok() { # tui_ok <id> [detail] — commits the step with a short glyph morph
  _tui_idx "$1" || return 0
  local at=$_TUI_I
  _TUI_STATE[$at]=ok
  [ -n "${2:-}" ] && _TUI_DETAIL[$at]=$2
  _TUI_BAR[$at]=''
  if [ "$TUI_LIVE" -eq 1 ]; then
    local f=0
    while [ "$f" -lt "${#TUI_G_MORPH[@]}" ]; do
      _TUI_MORPH_AT=$at; _TUI_MORPH_CH=${TUI_G_MORPH[$f]}
      _tui_render; sleep 0.03; f=$((f + 1))
    done
    _TUI_MORPH_AT=-1
  fi
  _tui_render
}

# ---------------------------------------------------------------- rendering

_tui_render() {
  _TUI_SPIN=$((_TUI_SPIN + 1))
  if [ "$TUI_LIVE" -ne 1 ]; then _tui_render_plain; return 0; fi

  local frame='' i=0 n=0 lines=$_TUI_LABELW dw detail marker lcolor pad spec d t pct bar
  # Columns: 2 indent, marker, 2, label(lines), 2, detail. Everything below derives from that.
  dw=$((TUI_COLS - 8 - lines)); [ "$dw" -lt 8 ] && dw=8

  while [ "$i" -lt "$_TUI_N" ]; do
    case "${_TUI_STATE[$i]}" in
      ok)     marker="$TUI_OK$TUI_G_OK$TUI_R";       lcolor=$TUI_FG ;;
      fail)   marker="$TUI_ERR$TUI_G_FAIL$TUI_R";    lcolor=$TUI_ERR ;;
      warn)   marker="$TUI_WARN$TUI_G_WARN$TUI_R";   lcolor=$TUI_WARN ;;
      # Accent on the marker AND the label, so the running step is one vertical thread the eye
      # lands on. Bold alone was a ~5% luminance step against eight finished rows above it.
      active) marker="$TUI_ACCENT${TUI_SPINNER[$((_TUI_SPIN % ${#TUI_SPINNER[@]}))]}$TUI_R"
              lcolor="$TUI_ACCENT$TUI_B" ;;
      *)      marker="$TUI_FAINT$TUI_G_PENDING$TUI_R"; lcolor=$TUI_DIM ;;
    esac
    [ "$_TUI_MORPH_AT" -eq "$i" ] && marker="$TUI_OK$_TUI_MORPH_CH$TUI_R"

    _tui_pad pad "${_TUI_LABEL[$i]}" "$lines"
    _tui_trunc detail "${_TUI_DETAIL[$i]}" "$dw"
    frame="$frame"$'\r\033[2K'"  $marker  $lcolor$pad$TUI_R  $TUI_DIM$detail$TUI_R"$'\n'
    n=$((n + 1))

    spec=${_TUI_BAR[$i]}
    if [ -n "$spec" ]; then
      d=${spec%%/*}; t=${spec##*/}
      case "$d$t" in *[!0-9]*) d=''; t='' ;; esac
      if [ -n "$d" ] && [ -n "$t" ] && [ "$t" -gt 0 ]; then
        # The bar is exactly as wide as the label field, so it reads as an underline of the
        # step it belongs to, and the percentage lands in the detail column under the numbers
        # it summarises rather than floating in a column of its own.
        tui_bar bar "$d" "$t" "$lines"
        printf -v pct '%3d%%' $((d * 100 / t))
        frame="$frame"$'\r\033[2K'"     $bar  $TUI_DIM$pct$TUI_R"$'\n'
        n=$((n + 1))
      fi
    fi
    i=$((i + 1))
  done

  # Erase any rows a previously taller region left behind, then park the cursor below.
  i=$n
  while [ "$i" -lt "$_TUI_DRAWN" ]; do frame="$frame"$'\r\033[2K\n'; i=$((i + 1)); done

  local up=''
  [ "$_TUI_DRAWN" -gt 0 ] && printf -v up '\033[%dA' "$_TUI_DRAWN"
  local back=''
  [ "$_TUI_DRAWN" -gt "$n" ] && printf -v back '\033[%dA' $((_TUI_DRAWN - n))
  # One printf per frame, so the terminal never sees a half-drawn list. (A frame wider than
  # bash's 1 KB stdio buffer becomes two write(2)s; that is fine — nothing else is writing.)
  printf '%s%s%s' "$up" "$frame" "$back"
  _TUI_DRAWN=$n
}

# Plain mode: no cursor tricks, one line per meaningful state change, nothing repeated.
_tui_render_plain() {
  local i=0 key pad
  while [ "$i" -lt "$_TUI_N" ]; do
    key="$i=${_TUI_STATE[$i]}"
    if [[ $_TUI_SEEN != *"|$key|"* ]]; then
      # No line for "active": the finished line follows moments later and says strictly more.
      # Labels stay padded so the detail column survives into a log file.
      case "${_TUI_STATE[$i]}" in
        ok)   _tui_pad pad "${_TUI_LABEL[$i]}" "$_TUI_LABELW"
              printf '  %s  %s  %s\n' "$TUI_G_OK" "$pad" "${_TUI_DETAIL[$i]}" ;;
        warn) _tui_pad pad "${_TUI_LABEL[$i]}" "$_TUI_LABELW"
              printf '  %s  %s  %s\n' "$TUI_G_WARN" "$pad" "${_TUI_DETAIL[$i]}" ;;
        fail) _tui_pad pad "${_TUI_LABEL[$i]}" "$_TUI_LABELW"
              printf '  %s  %s  %s\n' "$TUI_G_FAIL" "$pad" "${_TUI_DETAIL[$i]}" ;;
        *) i=$((i + 1)); continue ;;
      esac
      _TUI_SEEN="$_TUI_SEEN|$key|"
    fi
    i=$((i + 1))
  done
}

tui_tick() { _tui_render; _tui_sleep_frame; }

tui_commit() { # leave the region on screen and start a fresh one below it
  # _tui_render always finishes with the cursor on the line directly below the region, so
  # there is nothing to skip past here — advancing again would open a hole in the output.
  _tui_render
  _TUI_DRAWN=0
}

# ---------------------------------------------------------------- chrome

tui_header() { # tui_header <title> [subtitle]
  printf '\n%s  %s%s%s' "$TUI_EOL" "$TUI_B" "$1" "$TUI_R"
  [ -n "${2:-}" ] && printf '  %s%s%s' "$TUI_FAINT" "$2" "$TUI_R"
  printf '%s\n%s\n' "$TUI_EOL" "$TUI_EOL"
}

tui_kv() { # tui_kv <marker-colour> <marker> <key> <value> — a reference row on the task grid
  # Static reference screens share the task list's columns so a cheatsheet and a checklist
  # read as the same surface rather than two different programs.
  local pad
  _tui_pad pad "$3" "$_TUI_LABELW"
  printf '  %s%s%s  %s%s%s  %s%s%s%s\n' "$1" "$2" "$TUI_R" "$TUI_FG" "$pad" "$TUI_R" \
    "$TUI_DIM" "$4" "$TUI_R" "$TUI_EOL"
}

tui_label_width() { _TUI_LABELW=$1; }   # fix the column when there is no task list to size it

tui_rule()  { printf '  %s%s%s%s\n' "$TUI_FAINT" "${_TUI_RULE[$((TUI_COLS - 4))]}" "$TUI_R" "$TUI_EOL"; }
tui_note()  { local t; _tui_trunc t "$1" $((TUI_COLS - 6)); printf '     %s%s%s%s\n' "$TUI_DIM" "$t" "$TUI_R" "$TUI_EOL"; }
tui_hint()  { local t; _tui_trunc t "$1" $((TUI_COLS - 8)); printf '     %s%s%s %s%s%s%s\n' "$TUI_FAINT" "$TUI_G_BULLET" "$TUI_R" "$TUI_DIM" "$t" "$TUI_R" "$TUI_EOL"; }
tui_blank() { printf '%s\n' "$TUI_EOL"; }

tui_panel() { # tui_panel <colour> <title> <line>… — a callout with an accent rail
  # Deliberately one-sided. A box needs every body line padded to the closing edge, and the
  # body lines here carry embedded colour codes, so any width maths on them over-counts and
  # the right edge lands ragged — which is how this used to render as an open-ended "C".
  local color=$1 title=$2 line
  shift 2
  printf '\n%s  %s%s%s %s%s%s%s\n' "$TUI_EOL" "$color" "$TUI_G_RAIL" "$TUI_R" "$TUI_B" "$title" "$TUI_R" "$TUI_EOL"
  for line in "$@"; do
    if [ -z "$line" ]; then printf '  %s%s%s%s\n' "$color" "$TUI_G_RAIL" "$TUI_R" "$TUI_EOL"
    else printf '  %s%s%s %s%s%s%s\n' "$color" "$TUI_G_RAIL" "$TUI_R" "$TUI_DIM" "$line" "$TUI_R" "$TUI_EOL"; fi
  done
  printf '%s\n' "$TUI_EOL"
}

# ---------------------------------------------------------------- input

_tui_raw_on()  { _tui_stty_save=$(stty -g 2>/dev/null </dev/tty); stty -echo -icanon min 1 time 0 2>/dev/null </dev/tty; }
_tui_raw_off() { [ -n "$_tui_stty_save" ] && stty "$_tui_stty_save" 2>/dev/null </dev/tty; _tui_stty_save=''; }

# _tui_readkey — sets TUI_KEY to one logical key. No fork: callers must not use $( ).
_tui_readkey() {
  local c rest
  TUI_KEY=''
  # TUI_READ_TIMEOUT (whole seconds) lets a caller stop waiting for a person who is not there
  # — a stray keypress during boot must not leave a machine parked on a prompt for ever.
  if [ -n "${TUI_READ_TIMEOUT:-}" ]; then
    IFS= read -rsn1 -t "$TUI_READ_TIMEOUT" c </dev/tty || { TUI_KEY=timeout; return; }
  else
    IFS= read -rsn1 c </dev/tty || { TUI_KEY=esc; return; }
  fi
  case "$c" in
    '')  TUI_KEY=enter; return ;;
    ' ') TUI_KEY=space; return ;;
    $'\003') TUI_KEY=ctrlc; return ;;
    $'\033')
      # Read the CSI tail without blocking: min 0 / time 1 returns within 0.1s, so a bare Esc
      # resolves immediately instead of waiting on a fractional read -t that bash 3.2 lacks.
      stty min 0 time 1 2>/dev/null </dev/tty
      IFS= read -rsn2 rest 2>/dev/null </dev/tty
      stty min 1 time 0 2>/dev/null </dev/tty
      case "$rest" in
        '[A') TUI_KEY=up ;; '[B') TUI_KEY=down ;; '[C') TUI_KEY=right ;; '[D') TUI_KEY=left ;;
        *)    TUI_KEY=esc ;;
      esac
      return ;;
  esac
  case "$c" in
    k|K) TUI_KEY=up ;; j|J) TUI_KEY=down ;;
    q|Q) TUI_KEY=quit ;;
    *)   TUI_KEY=$c ;;
  esac
}

# tui_choose <outvar> <default-index> <title> <label>|<hint> …
# Menus render on stderr; the answer lands in <outvar>, so callers never need $( ).
tui_choose() {
  local __out=$1 sel=$2 title=$3
  shift 3
  local n=$# i drawn=0 frame label hint pad
  local labels=() hints=()
  for o in "$@"; do
    labels[${#labels[@]}]=${o%%|*}
    if [ "${o#*|}" = "$o" ]; then hints[${#hints[@]}]=''; else hints[${#hints[@]}]=${o#*|}; fi
  done

  if [ "$TUI_HAS_TTY" -ne 1 ] || [ "$TUI_LIVE" -ne 1 ]; then
    printf '\n  %s\n' "$title" >&2
    i=0; while [ "$i" -lt "$n" ]; do
      printf '   %d) %-12s %s\n' $((i + 1)) "${labels[$i]}" "${hints[$i]}" >&2; i=$((i + 1))
    done
    if [ "$TUI_HAS_TTY" -eq 1 ]; then
      local a=''
      read -r -p "  choose [1-$n] (default $((sel + 1))): " a </dev/tty || a=''
      case "$a" in ''|*[!0-9]*) : ;; *) [ "$a" -ge 1 ] && [ "$a" -le "$n" ] && sel=$((a - 1)) ;; esac
    fi
    printf -v "$__out" '%d' "$sel"
    return 0
  fi

  printf '\n  %s%s%s\n\n' "$TUI_B" "$title" "$TUI_R" >&2
  _tui_raw_on
  while :; do
    frame=''
    [ "$drawn" -gt 0 ] && printf -v frame '\033[%dA' "$drawn"
    i=0
    while [ "$i" -lt "$n" ]; do
      _tui_pad pad "${labels[$i]}" "$_TUI_LABELW"
      if [ "$i" -eq "$sel" ]; then
        frame="$frame"$'\r\033[2K'"  $TUI_ACCENT$TUI_G_ARROW$TUI_R  $TUI_ACCENT$TUI_B$pad$TUI_R  $TUI_DIM${hints[$i]}$TUI_R"$'\n'
      else
        frame="$frame"$'\r\033[2K'"     $TUI_DIM$pad$TUI_R  $TUI_FAINT${hints[$i]}$TUI_R"$'\n'
      fi
      i=$((i + 1))
    done
    frame="$frame"$'\r\033[2K\n\r\033[2K'"     $TUI_DIM${TUI_KEYHINT:-$TUI_G_UP$TUI_G_DN move · enter select}$TUI_R"$'\n'
    printf '%s' "$frame" >&2
    drawn=$((n + 2))
    _tui_readkey
    case "$TUI_KEY" in
      up)    sel=$(( (sel - 1 + n) % n )) ;;
      down)  sel=$(( (sel + 1) % n )) ;;
      enter|timeout) break ;;
      ctrlc) _tui_raw_off; _tui_interrupt ;;
      [1-9]) [ "$TUI_KEY" -le "$n" ] && { sel=$((TUI_KEY - 1)); break; } ;;
    esac
  done
  _tui_raw_off

  # Collapse the menu to a single committed line, so the transcript stays clean.
  frame=''
  printf -v frame '\033[%dA' "$drawn"
  _tui_pad pad "${labels[$sel]}" "$_TUI_LABELW"
  frame="$frame"$'\r\033[2K'"  $TUI_OK$TUI_G_OK$TUI_R  $TUI_FG$pad$TUI_R  $TUI_FAINT${hints[$sel]}$TUI_R"$'\n'
  i=1
  while [ "$i" -lt "$drawn" ]; do frame="$frame"$'\r\033[2K\n'; i=$((i + 1)); done
  printf -v frame '%s\033[%dA' "$frame" $((drawn - 1))
  printf '%s' "$frame" >&2
  printf -v "$__out" '%d' "$sel"
}

# tui_toggle <outvar> <title> <label>|<hint>|<on:0|1> … — multi-select; sets "0 1 0 1"
tui_toggle() {
  local __out=$1 title=$2
  shift 2
  local n=$# i sel=0 drawn=0 frame pad box rest
  local labels=() hints=() state=()
  for o in "$@"; do
    labels[${#labels[@]}]=${o%%|*}
    rest=${o#*|}
    hints[${#hints[@]}]=${rest%%|*}
    state[${#state[@]}]=$(( ${rest#*|} + 0 ))
  done
  if [ "$TUI_HAS_TTY" -ne 1 ] || [ "$TUI_LIVE" -ne 1 ]; then
    printf -v "$__out" '%s' "${state[*]}"
    return 0
  fi

  printf '\n  %s%s%s\n\n' "$TUI_B" "$title" "$TUI_R" >&2
  _tui_raw_on
  while :; do
    frame=''
    [ "$drawn" -gt 0 ] && printf -v frame '\033[%dA' "$drawn"
    i=0
    while [ "$i" -lt "$n" ]; do
      # Braces are load-bearing: an unbraced $VAR immediately followed by a multibyte
      # character has that character's leading byte swallowed into the variable name.
      # A green check here would read as "this step finished", two columns from a list where
      # that is exactly what it means. A checkbox says "you can change this".
      # Braces again: an unbraced $VAR followed by "[" is parsed as an array subscript.
      if [ "${state[$i]}" -eq 1 ]; then box="${TUI_DIM}[$TUI_OK$TUI_G_ON${TUI_DIM}]$TUI_R"
      else box="${TUI_FAINT}[$TUI_G_OFF]$TUI_R"; fi
      _tui_pad pad "${labels[$i]}" "$_TUI_LABELW"
      if [ "$i" -eq "$sel" ]; then
        frame="$frame"$'\r\033[2K'"  $box $TUI_ACCENT$TUI_B$pad$TUI_R  $TUI_DIM${hints[$i]}$TUI_R"$'\n'
      else
        frame="$frame"$'\r\033[2K'"  $box $TUI_DIM$pad$TUI_R  $TUI_FAINT${hints[$i]}$TUI_R"$'\n'
      fi
      i=$((i + 1))
    done
    frame="$frame"$'\r\033[2K\n\r\033[2K'"     $TUI_DIM$TUI_G_UP$TUI_G_DN move · space toggle · enter confirm$TUI_R"$'\n'
    printf '%s' "$frame" >&2
    drawn=$((n + 2))
    _tui_readkey
    case "$TUI_KEY" in
      up)    sel=$(( (sel - 1 + n) % n )) ;;
      down)  sel=$(( (sel + 1) % n )) ;;
      space) if [ "${state[$sel]}" -eq 1 ]; then state[$sel]=0; else state[$sel]=1; fi ;;
      enter|timeout) break ;;
      ctrlc) _tui_raw_off; _tui_interrupt ;;
    esac
  done
  _tui_raw_off

  # Collapse the widget to a one-line summary of what is on. Erasing it entirely would leave
  # the question above it hanging over a hole in the output.
  local chosen=''
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ "${state[$i]}" -eq 1 ]; then
      if [ -z "$chosen" ]; then chosen=${labels[$i]}; else chosen="$chosen, ${labels[$i]}"; fi
    fi
    i=$((i + 1))
  done
  [ -z "$chosen" ] && chosen='nothing selected'
  frame=''
  printf -v frame '\033[%dA' "$drawn"
  frame="$frame"$'\r\033[2K'"  $TUI_OK$TUI_G_OK$TUI_R  $TUI_DIM$chosen$TUI_R"$'\n'
  i=1; while [ "$i" -lt "$drawn" ]; do frame="$frame"$'\r\033[2K\n'; i=$((i + 1)); done
  printf -v frame '%s\033[%dA' "$frame" $((drawn - 1))
  printf '%s' "$frame" >&2
  printf -v "$__out" '%s' "${state[*]}"
}

tui_confirm() { # tui_confirm <prompt> [default:y|n] — single keypress, no Enter needed
  local prompt=$1 def=${2:-y} hint='[Y/n]' yes=1
  [ "$def" = n ] && hint='[y/N]'
  [ "$TUI_HAS_TTY" -ne 1 ] && { [ "$def" = y ]; return; }
  if [ "$TUI_LIVE" -ne 1 ]; then
    local a=''
    read -r -p "     $prompt $hint " a </dev/tty || a=''
    [ -z "$a" ] && { [ "$def" = y ]; return; }
    case "$a" in [Yy]*) return 0 ;; *) return 1 ;; esac
  fi
  printf '  %s%s%s  %s%s%s %s%s%s ' "$TUI_ACCENT" "$TUI_G_ARROW" "$TUI_R" \
    "$TUI_B" "$prompt" "$TUI_R" "$TUI_FAINT" "$hint" "$TUI_R" >&2
  _tui_raw_on; _tui_readkey; _tui_raw_off
  case "$TUI_KEY" in
    y|Y) yes=0 ;;
    n|N|quit|esc) yes=1 ;;
    ctrlc) _tui_interrupt ;;
    *) [ "$def" = y ] && yes=0 ;;
  esac
  if [ "$yes" -eq 0 ]; then printf '%syes%s\n' "$TUI_OK" "$TUI_R" >&2
  else printf '%sno%s\n' "$TUI_DIM" "$TUI_R" >&2; fi
  return $yes
}

tui_ask() { # tui_ask <outvar> <prompt> <default>
  local __out=$1 prompt=$2 def=${3:-} a=''
  if [ "$TUI_HAS_TTY" -ne 1 ]; then printf -v "$__out" '%s' "$def"; return 0; fi
  printf '  %s%s%s  %s%s%s %s%s%s ' "$TUI_ACCENT" "$TUI_G_ARROW" "$TUI_R" \
    "$TUI_B" "$prompt" "$TUI_R" "$TUI_FAINT" "${def:+[$def]}" "$TUI_R" >&2
  [ "$TUI_LIVE" -eq 1 ] && printf '\033[?25h' >&2
  IFS= read -r a </dev/tty || a=''
  a=${a:-$def}
  # Redraw the line as the answer, so the transcript reads as a record of decisions rather
  # than a list of prompts with the replies scrolled off the right-hand side.
  if [ "$TUI_LIVE" -eq 1 ]; then
    printf '\033[?25l\033[1A\r\033[2K  %s%s%s  %s%s%s %s%s%s\n' \
      "$TUI_OK" "$TUI_G_OK" "$TUI_R" "$TUI_DIM" "$prompt" "$TUI_R" "$TUI_FG" "$a" "$TUI_R" >&2
  fi
  printf -v "$__out" '%s' "$a"
}

tui_ask_secret() { # tui_ask_secret <outvar> <prompt> — hidden, echoes a dot per character
  local __out=$1 prompt=$2 a='' c
  if [ "$TUI_HAS_TTY" -ne 1 ]; then printf -v "$__out" '%s' ''; return 1; fi
  printf '  %s%s%s  %s%s%s ' "$TUI_ACCENT" "$TUI_G_ARROW" "$TUI_R" "$TUI_B" "$prompt" "$TUI_R" >&2
  _tui_raw_on
  while :; do
    IFS= read -rsn1 c </dev/tty || break
    case "$c" in
      '') break ;;
      $'\177'|$'\b') [ -n "$a" ] && { a=${a%?}; printf '\b \b' >&2; } ;;
      $'\003') _tui_raw_off; printf '\n' >&2; _tui_interrupt ;;
      *) a="$a$c"; printf '%s' "$TUI_G_BULLET" >&2 ;;
    esac
  done
  _tui_raw_off
  printf '\n' >&2
  printf -v "$__out" '%s' "$a"
}

# ---------------------------------------------------------------- teardown

_tui_atexit() {
  [ "${TUI_LIVE:-0}" -eq 1 ] && printf '\033[?25h'
  [ -n "${_tui_stty_save:-}" ] && stty "$_tui_stty_save" 2>/dev/null </dev/tty
  return 0
}

_tui_interrupt() {
  trap - INT TERM EXIT
  _tui_atexit
  printf '\n\n  %s%s cancelled%s  %s%s%s\n\n' \
    "$TUI_WARN" "$TUI_G_WARN" "$TUI_R" "$TUI_DIM" "${TUI_CANCEL_HINT:-}" "$TUI_R"
  exit 130
}
