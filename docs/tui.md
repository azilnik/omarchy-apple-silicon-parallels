# The terminal UI

Two programs share one look: the macOS installer (`install.sh`) and the first-boot setup and
health check inside the VM (`guest/omarchy-parallels-*`). Both render through `lib/tui.sh`.

They run in very different terminals, and most of the design here is a consequence of that.

| | host | guest |
|---|---|---|
| shell | macOS `/bin/bash` **3.2.57** | Arch ARM bash 5 |
| terminal | Terminal.app / iTerm, usually 24-bit colour | tty1, `TERM=linux`, 8 colours |
| font | whatever the user picked; full Unicode | the kernel's built-in 256-glyph console font |
| locale | usually UTF-8, sometimes nothing | nothing |
| input | `/dev/tty` (stdin is the script, under `curl \| bash`) | `/dev/tty1` via systemd |

## Capability tiers

`tui_init` picks one of three tiers and every glyph, colour and animation follows from it.
Override with `OMARCHY_TUI=fancy|basic|plain`; `NO_COLOR`, a non-tty stdout, `TERM=dumb` and
`CI` all force plain.

- **3 — fancy.** UTF-8 on a real emulator. Braille spinner, eighth-block progress bars, `✓`/`✗`.
- **2 — basic.** UTF-8 on a console font. Half-block rotation, `√`/`×`, full/light-shade bars.
- **1 — plain.** ASCII only, no colour, no cursor movement: one line per state change, so a
  piped or logged run reads like an ordinary build log.

### Tier 2 is not "tier 3 with fewer colours"

The Linux console font has 256 glyphs and **no fallback**. An unmapped codepoint is drawn as
some *other* glyph, silently — so a UI that assumes Unicode does not degrade, it lies. Every
tier-2 character was chosen by drawing candidates on a real tty1 and photographing the
framebuffer (`test/tui/deploy-guest.sh <vm> glyphs`).

What that probe found, and what it changed:

| wanted | on tty1 | used instead |
|---|---|---|
| `⠋⠙⠹…` braille spinner | random letters | — |
| `▖▘▝▗` quadrant spinner | **all four draw the same glyph** — the spinner appears frozen | `▀ ▐ ▄ ▌`, which really rotates |
| `✓` | `ʊ` | `√` (U+221A), which reads as a check |
| `▏▎▍▌` eighth blocks | `#` | no partial cell; whole blocks only |
| `…` | `.` | `...` |
| `⌘` | `■` | the word `Cmd` |
| `░ ▒ ▓ █` | four distinct shades | kept |
| `┌ ┐ └ ┘ ─ │`, `» « → ↑↓ ·` | correct | kept |

## The live region

The renderer keeps N lines at the bottom of the screen and rewrites them in place with
cursor-up plus erase-line. It never clears the screen and never scrolls on its own, so
scrollback survives and `tui_commit` can leave a finished block behind and start a fresh one.

**While a region is open, nothing else may write to stdout or stderr.** A stray line
desynchronises the cursor accounting and the display tears. Every subprocess in `install.sh`
is redirected to a log for exactly this reason, which is also why a failed install has one
file to attach to a bug report.

## Two rules that are easy to break

**The render path must not fork.** No command substitution, no subshells, no external
commands inside `_tui_render` or the menu loops — everything composes with `printf -v` and
parameter expansion, and each frame is emitted as a single `write`. Bars are two lookups into
prefix arrays built once at init, not loops. A frame that costs a dozen forks is what makes a
shell TUI feel like a shell script. `make tui-test` asserts 300 frames of an 8-task list
render in under a second.

**Bash counts characters only in a multibyte locale.** With no `LANG` set — which is the
default on tty1, and common enough on a Mac — `${#s}` and `${s:i:1}` count *bytes*. That
silently shreds every glyph the UI slices and renders progress bars at a third of their
intended width. `_tui_fix_ctype` repairs `LC_CTYPE` if it can and drops to ASCII if it cannot,
because in ASCII bytes and characters agree.

A related trap, which cost an afternoon: an unbraced `$VAR` immediately followed by a
multibyte character has that character's leading byte swallowed into the variable name —
`"$TUI_FAINT·"` is read as `${TUI_FAINT\xc2}`, which under `set -u` aborts the script. It only
bites where a glyph follows a bare expansion, so it survives every ASCII test. Brace it.
`make tui-test` greps for the pattern.

## bash 3.2

`install.sh` is piped to whatever `bash` is on a stranger's Mac, which is 3.2.57. No
associative arrays, no `read -t <fraction>`, no `${var^^}`, no `mapfile`, and no bare
`"${arr[@]}"` on an empty array under `set -u`. Task state therefore lives in parallel indexed
arrays with a linear id scan; the lists are about eight items long, so the scan is cheaper
than any cleverness would be.

`install.sh` must also stay a single self-contained file, because it is fetched by URL and
piped straight to bash — it cannot source anything. `build/bundle.sh` inlines `lib/tui.sh`
between marker comments; **edit `lib/tui.sh`, then `make bundle`**. `make lint` fails if the
inlined copy has drifted.

## Testing

```sh
make tui-test      # library units, installer flow, failure paths, source hazards
make lint          # shellcheck at CI severity + the bundle drift check
```

`test/tui/harness.sh` runs the whole installer end to end against a local throttled HTTP
server with `prlctl`, `open` and `defaults` stubbed, so nothing touches Parallels, the network
or `~/Parallels`. It can simulate a dropped connection (`--die-at`), a stalled mirror
(`--stall-at`), a bad checksum (`--bad-sha`) and any transfer rate.

It runs a *copy* of `install.sh`. Bash reads a script incrementally by byte offset, so editing
`install.sh` while a run is in flight makes the running shell resume at a stale position and
fail with nonsense — a fragment of a word reported as "command not found". That is very easy
to do by accident while iterating, and very confusing to debug.

For the guest, `test/tui/deploy-guest.sh <vm> push|glyphs|verify|rearm-firstboot|shot` pushes
the payload into a running VM over `prlctl exec` (no sshd needed — a quick-install image
leaves it off), runs things on a spare virtual terminal, and screenshots the framebuffer.
That screenshot is the only honest test of a console font.

## Recording

`vhs` (`brew install vhs`) drives the tapes in `test/tui/*.tape` against the harness, so the
GIFs in `docs/assets/` are reproducible and do not require a real 4.7 GB download.

```sh
vhs test/tui/rec-quick.tape    # docs/assets/install-quick.gif
vhs test/tui/rec-menu.tape     # docs/assets/install-menu.gif
```
