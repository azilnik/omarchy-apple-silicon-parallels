#!/bin/bash
# test/tui/run-tui-tests.sh — headless checks for the terminal UI and the installer flow.
#
# No VM, no Parallels, no network: the installer runs against test/tui/harness.sh, which
# serves a synthetic image from localhost and stubs prlctl/open/defaults. Safe to run anywhere.
#
#   make tui-test          everything
#   run-tui-tests.sh -q    quick subset (skips the slow network-failure cases)

set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
QUICK=0; [[ ${1:-} == -q ]] && QUICK=1
PASS=0; FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; [[ -n ${2:-} ]] && printf '      %s\n' "$2"; FAIL=$((FAIL + 1)); }
have() { grep -qF "$2" <<<"$1"; }

H="$REPO/test/tui/harness.sh"
export OMARCHY_HARNESS_WORK="${TMPDIR:-/tmp}/omarchy-tui-tests"

printf '\n== library units ==\n'
# Pure-function checks run in a subshell per case so a bad assignment cannot leak.
lib_eval() { /bin/bash -c '. '"$REPO"'/lib/tui.sh; OMARCHY_TUI=plain tui_init >/dev/null 2>&1; '"$1"; }

got=$(lib_eval 'tui_human_bytes v 5074103050; echo "$v"')
[[ $got == "4.72 GB" ]] && ok "human_bytes: 5074103050 -> 4.72 GB" || bad "human_bytes" "got '$got'"
got=$(lib_eval 'tui_human_bytes v 0; echo "$v"')
[[ $got == "0 B" ]] && ok "human_bytes: zero" || bad "human_bytes zero" "got '$got'"
got=$(lib_eval 'tui_human_time v 3725; echo "$v"')
[[ $got == "1h 02m" ]] && ok "human_time: 3725 -> 1h 02m" || bad "human_time" "got '$got'"
got=$(lib_eval 'tui_human_time v 0; echo "$v"')
[[ $got == "0s" ]] && ok "human_time: zero" || bad "human_time zero" "got '$got'"
got=$(lib_eval 'tui_human_bytes v abc; echo "$v"')
[[ $got == "0 B" ]] && ok "human_bytes: non-numeric input is not fatal" || bad "human_bytes garbage" "got '$got'"

# The bar must be exactly <width> characters at every fill level, including the ends, and it
# must never divide by zero when a total is unknown.
got=$(lib_eval 'for d in 0 1 49 50 99 100 101; do tui_bar v $d 100 20; echo -n "${#v} "; done')
[[ $got == "20 20 20 20 20 20 20 " ]] && ok "bar: constant width across 0..over-full" || bad "bar width" "got '$got'"
got=$(lib_eval 'tui_bar v 5 0 10; echo "${#v}"')
[[ $got == "10" ]] && ok "bar: zero total does not divide by zero" || bad "bar zero total" "got '$got'"
got=$(lib_eval 'tui_bar v 0 100 20; echo "$v"')
[[ $got == "...................." ]] && ok "bar: empty at 0%" || bad "bar empty" "got '$got'"
got=$(lib_eval 'tui_bar v 100 100 20; echo "$v"')
[[ $got == "####################" ]] && ok "bar: full at 100%" || bad "bar full" "got '$got'"

got=$(lib_eval '_tui_pad v "hello" 10; echo "[$v]"')
[[ $got == "[hello     ]" ]] && ok "pad: right-pads to width" || bad "pad" "got '$got'"
got=$(lib_eval '_tui_pad v "a-very-long-label-indeed" 10; echo "${#v}"')
[[ $got == "10" ]] && ok "pad: truncates to width" || bad "pad truncate" "got '$got'"

# Multibyte safety: with a byte-oriented locale the library must repair LC_CTYPE (or drop to
# ASCII) rather than slicing glyphs in half. This is the bug that made bars a third-width.
got=$(env -u LANG -u LC_ALL -u LC_CTYPE /bin/bash -c '. '"$REPO"'/lib/tui.sh; OMARCHY_TUI=fancy tui_init >/dev/null 2>&1; tui_bar v 50 100 20; echo "${#v}-$TUI_TIER"' 2>/dev/null)
[[ $got == 20-* ]] && ok "multibyte: bar keeps its width with no locale set ($got)" || bad "multibyte bar" "got '$got'"

printf '\n== render performance ==\n'
# The render path must not fork. A fork per field would not change the output, only the speed,
# so time is the assertion: 300 frames of an 8-task list should be milliseconds, not seconds.
ms=$( { TIMEFORMAT=%R; time /bin/bash -c '
  . '"$REPO"'/lib/tui.sh
  OMARCHY_TUI=fancy tui_init >/dev/null 2>&1
  TUI_LIVE=1; TUI_COLS=100
  for i in 1 2 3 4 5 6 7 8; do tui_task_add "t$i" "Task number $i"; done
  tui_progress t3 "2.1 GB of 3.7 GB" "55/100" >/dev/null
  n=0; while [ $n -lt 300 ]; do _tui_render; n=$((n+1)); done' >/dev/null 2>&1; } 2>&1 )
awk -v t="$ms" 'BEGIN{exit !(t < 1.0)}' && ok "render: 300 frames of 8 tasks in ${ms}s (< 1.0s)" \
  || bad "render too slow" "300 frames took ${ms}s — something in the frame path is forking"

printf '\n== installer: happy path ==\n'
out=$(OMARCHY_TUI=plain "$H" --size 6 -- --quick 2>&1); rc=$?
[[ $rc -eq 0 ]] && ok "quick install exits 0" || bad "quick install exit $rc" "$(tail -3 <<<"$out")"
have "$out" "Checking this Mac" && ok "reports the preflight" || bad "no preflight line"
have "$out" "Downloading" && ok "reports the download" || bad "no download line"
have "$out" "Omarchy.pvm" && ok "reports what it unpacked" || bad "no unpack line"
have "$out" "registered with Parallels" && ok "confirms registration via prlctl" || bad "no registration line"
[[ -d "$OMARCHY_HARNESS_WORK/dest/Omarchy.pvm" ]] && ok "the VM bundle actually landed on disk" || bad "no Omarchy.pvm in dest"
[[ ! -f "$OMARCHY_HARNESS_WORK/dest/omarchy-apple-silicon-parallels-v0.9.9.zip" ]] \
  && ok "the downloaded zip is cleaned up" || bad "zip left behind"
grep -q 'defaults write' "$OMARCHY_HARNESS_WORK/state/defaults.log" 2>/dev/null \
  && ok "sets the Retina HiDPI preference" || bad "no HiDPI preference written"

# Nothing a subprocess prints may reach the terminal — that is what corrupts a live region.
for noise in 'Archive:' 'inflating:' '% Total' 'Warning:'; do
  have "$out" "$noise" && bad "subprocess noise leaked: $noise" || ok "no leaked output: '$noise'"
done

printf '\n== installer: presentation ==\n'
esc=$(printf '\033')
out=$(NO_COLOR=1 "$H" --size 4 -- --quick 2>&1)
grep -q "$esc" <<<"$out" && bad "NO_COLOR still emits escape sequences" || ok "NO_COLOR: no escape sequences at all"
out=$(OMARCHY_TUI=plain "$H" --size 4 -- --quick 2>&1)
longest=$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' <<<"$out")
[[ $longest -le 100 ]] && ok "plain output stays within 100 columns (longest $longest)" \
  || bad "line too long" "longest line is $longest characters"

printf '\n== installer: failure paths ==\n'
out=$(OMARCHY_TUI=plain OMARCHY_PARALLELS_APP=/nonexistent "$H" --size 4 -- --quick 2>&1); rc=$?
[[ $rc -eq 1 ]] && ok "missing Parallels exits 1" || bad "missing Parallels exit $rc"
have "$out" "Parallels Desktop is not installed" && ok "says what is wrong" || bad "unhelpful message"
have "$out" "trial" && ok "says how to fix it" || bad "no remedy offered"

out=$(OMARCHY_TUI=plain "$H" --size 4 --bad-sha -- --quick 2>&1); rc=$?
[[ $rc -eq 1 ]] && ok "checksum mismatch exits 1" || bad "bad checksum exit $rc"
have "$out" "Checksum mismatch" && ok "names the checksum failure" || bad "no checksum message"
[[ -z $(find "$OMARCHY_HARNESS_WORK/dest" -name '*.zip' 2>/dev/null) ]] \
  && ok "deletes the corrupt download" || bad "corrupt zip kept"

# With no controlling terminal at all, every prompt has to resolve to its safe default rather
# than block — and nothing may print a raw shell error about /dev/tty. macOS has no setsid(1),
# so detach with python and then run the interactive (no --quick) path.
NOTTY=$(python3 -c 'import os,sys,subprocess; os.setsid(); sys.exit(subprocess.call(sys.argv[1:]))' \
        env OMARCHY_TUI=plain "$H" --size 4 2>&1 </dev/null); rc=$?
[[ $rc -eq 0 || $rc -eq 1 ]] && ok "no-tty run terminates instead of blocking on a prompt" \
  || bad "no-tty run hung or crashed (exit $rc)" "$(tail -3 <<<"$NOTTY")"
have "$NOTTY" "/dev/tty" && bad "no-tty run leaks a shell error about /dev/tty" \
  || ok "no-tty run says nothing about /dev/tty"

if [[ $QUICK -eq 0 ]]; then
  printf '\n== installer: network trouble ==\n'
  out=$(OMARCHY_TUI=plain "$H" --size 24 --rate 6291456 --die-at 40 -- --quick 2>&1); rc=$?
  [[ $rc -eq 0 ]] && ok "a dropped connection resumes and still finishes" || bad "die-at 40 exit $rc" "$(tail -3 <<<"$out")"

  # A stalled mirror must announce itself quickly; the retry/abort behind it is curl's own
  # --speed-time, so this only asserts that the user is told within a few seconds.
  ( OMARCHY_TUI=plain "$H" --size 24 --stall-at 30 -- --quick > "$OMARCHY_HARNESS_WORK/stall.out" 2>&1 ) &
  stallpid=$!
  found=0
  for _ in $(seq 1 40); do
    grep -q 'no data for' "$OMARCHY_HARNESS_WORK/stall.out" 2>/dev/null && { found=1; break; }
    sleep 1
  done
  kill -TERM $stallpid 2>/dev/null; wait $stallpid 2>/dev/null
  pkill -f 'test/tui/server.py' 2>/dev/null
  [[ $found -eq 1 ]] && ok "a stalled download says so instead of looking hung" || bad "stall never reported"
fi

printf '\n== source hazards ==\n'
# An unbraced $VAR immediately followed by a multibyte character loses that character's
# leading byte into the variable name — bash reads `"$TUI_FAINT·"` as ${TUI_FAINT\xc2}, which
# under `set -u` aborts the script. It only bites where the glyph follows a bare expansion, so
# it survives every ASCII test and every non-UTF-8 run. Braces are the fix; this is the guard.
hazard=$(python3 - "$REPO" <<'SCAN'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
# Two adjacency traps, same root cause: bash keeps reading after a bare $VAR.
# A following multibyte character has its leading byte swallowed into the name; a
# following "[" is parsed as an array subscript. Both survive every ASCII test.
pat = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7f]|\[)')
hits = []
for f in ['lib/tui.sh', 'install.sh', 'guest/omarchy-parallels-firstboot.sh',
          'guest/omarchy-parallels-verify.sh']:
    for n, line in enumerate((root / f).read_text(encoding='utf-8').splitlines(), 1):
        for m in pat.finditer(line):
            hits.append(f"{f}:{n}: {m.group(0)}")
print("\n".join(hits))
SCAN
)
[[ -z $hazard ]] && ok "no unbraced expansion is followed by a multibyte character or [" \
  || bad "unbraced expansion before a multibyte character or [" "$hazard"

printf '\n== bundler safety ==\n'
# Each of these was a way for build/bundle.sh to silently destroy install.sh and then have
# --check certify the wreckage as in sync.
BS="$OMARCHY_HARNESS_WORK/bundle"; rm -rf "$BS"; mkdir -p "$BS/build" "$BS/lib"
cp "$REPO/build/bundle.sh" "$BS/build/"; cp "$REPO/lib/tui.sh" "$BS/lib/"; cp "$REPO/install.sh" "$BS/"
before=$(wc -l < "$BS/install.sh")
grep -v '^# <<< END lib/tui.sh' "$BS/install.sh" > "$BS/i2" && cp "$BS/i2" "$BS/install.sh"
( cd "$BS" && ./build/bundle.sh ) >/dev/null 2>&1
[[ $? -ne 0 ]] && ok "bundler refuses a missing END marker" || bad "bundler accepted a missing END marker"
cp "$REPO/install.sh" "$BS/install.sh"
chmod 000 "$BS/lib/tui.sh"
( cd "$BS" && ./build/bundle.sh ) >/dev/null 2>&1
[[ $? -ne 0 ]] && ok "bundler refuses an unreadable library" || bad "bundler accepted an unreadable library"
chmod 644 "$BS/lib/tui.sh"
awk '{print} /^# <<< END lib\/tui.sh/{print "# >>> BEGIN lib/tui.sh"; print "# <<< END lib/tui.sh"}' \
  "$BS/install.sh" > "$BS/i3" && cp "$BS/i3" "$BS/install.sh"
( cd "$BS" && ./build/bundle.sh ) >/dev/null 2>&1
[[ $? -ne 0 ]] && ok "bundler refuses duplicated markers" || bad "bundler accepted duplicated markers"
cp "$REPO/install.sh" "$BS/install.sh"
( cd "$BS" && ./build/bundle.sh ) >/dev/null 2>&1 && \
  [[ $(wc -l < "$BS/install.sh") -eq $before ]] && ok "bundler is idempotent" || bad "bundler is not idempotent"

printf '\n== manifest hardening ==\n'
# The download URL comes from the manifest, and lands in curl's argument list — where a
# leading dash is read as an option (-K makes curl read its config from a file of your
# choosing). A compromised release host must not be able to do that.
out=$(OMARCHY_TUI=plain "$H" --size 2 --bad-url '-K/etc/passwd' -- --quick 2>&1); rc=$?
[[ $rc -ne 0 ]] && have "$out" "points somewhere unexpected" \
  && ok "a manifest URL that is a curl option is refused" \
  || bad "curl option injection via the manifest not refused" "$(tail -2 <<<"$out")"
out=$(OMARCHY_TUI=plain "$H" --size 2 --bad-url 'file:///etc/passwd' -- --quick 2>&1)
have "$out" "points somewhere unexpected" && ok "a non-http manifest URL is refused" \
  || bad "file:// manifest URL not refused"
out=$(OMARCHY_TUI=plain "$H" --size 2 --bad-url 'http://evil.example/x.zip' -- --quick 2>&1)
have "$out" "points somewhere unexpected" && ok "plain http off-loopback is refused" \
  || bad "off-loopback http accepted"

printf '\n== narrow terminals ==\n'
# Below the minimum width the live region must stand down, not emit lines that wrap to two
# physical rows while the cursor bookkeeping counts one.
got=$(/bin/bash -c '. '"$REPO"'/lib/tui.sh; TUI_HAS_TTY=0; OMARCHY_TUI=fancy tui_init >/dev/null 2>&1; TUI_COLS=30; _tui_measure; echo "$TUI_LIVE"' 2>/dev/null)
lo=$(/bin/bash -c 'stty() { echo "24 30"; }; . '"$REPO"'/lib/tui.sh; OMARCHY_TUI=fancy tui_init >/dev/null 2>&1; echo "$TUI_COLS/$TUI_LIVE"' 2>/dev/null)
[[ $lo == 30/0 || $lo == */0 ]] && ok "a 30-column terminal falls back to plain ($lo)" \
  || bad "narrow terminal still renders a live region" "got '$lo'"
got=$(lib_eval '_tui_pad v abcdef 2; echo "[$v]"')
[[ $got == "[ab]" ]] && ok "pad survives a width below the ellipsis" || bad "pad underflow" "got '$got'"

printf '\n== repository invariants ==\n'
"$REPO/build/bundle.sh" --check >/dev/null 2>&1 && ok "install.sh matches lib/tui.sh" \
  || bad "install.sh is stale" "run: make bundle"
/bin/bash -n "$REPO/install.sh" 2>/dev/null && ok "install.sh parses under bash 3.2 (macOS /bin/bash)" \
  || bad "install.sh is not bash-3.2 clean"
/bin/bash -n "$REPO/lib/tui.sh" 2>/dev/null && ok "lib/tui.sh parses under bash 3.2" \
  || bad "lib/tui.sh is not bash-3.2 clean"
# The welcome must never be able to block a login: it has to run headlessly, exit 0, and stay
# quiet when its marker is already set.
out=$(OMARCHY_TUI=plain bash "$REPO/guest/omarchy-parallels-welcome.sh" 2>&1 </dev/null); rc=$?
[[ $rc -eq 0 ]] && ok "the in-VM welcome runs headlessly and exits 0" || bad "welcome exit $rc"
have "$out" "Cmd" && ok "the welcome names the Mac key translation" || bad "welcome does not mention Cmd"
grep -q 'omarchy-done check omarchy-parallels-welcome' "$REPO/guest/hooks/omarchy-parallels-welcome.post-boot" \
  && ok "the post-boot hook is guarded by a once-marker" || bad "welcome hook would fire every boot"
grep -q 'omarchy-parallels-welcome' "$REPO/build/sysprep.sh" \
  && ok "sysprep re-arms the welcome for the recipient" || bad "packaged image would ship the welcome already shown"

for g in "$REPO"/guest/*.sh; do
  bash -n "$g" 2>/dev/null || bad "guest script does not parse: $(basename "$g")"
done
ok "guest scripts parse"
grep -q 'OMARCHY_TUI_LIB\|tui.sh' "$REPO/build/refresh.sh" && ok "refresh.sh installs the UI library into the guest" \
  || bad "refresh.sh does not ship lib/tui.sh"

printf '\n== RESULT: %d passed, %d failed ==\n\n' "$PASS" "$FAIL"
exit $((FAIL > 0 ? 1 : 0))
