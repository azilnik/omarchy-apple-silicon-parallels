# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org).

## [Unreleased]

### Added — one terminal UI, host and guest
- `lib/tui.sh`: a shared, dependency-free terminal UI — live task list, progress bars with
  rate/ETA, arrow-key menus and multi-select, animated completion, capability tiers. Inlined
  into `install.sh` by `build/bundle.sh` so the one-liner stays a single auditable file;
  installed into the VM for first boot and the health check. Design notes: [docs/tui.md](docs/tui.md).
- Installer: arrow-key **Quick / Custom / Cancel** menu, a Custom path that chooses the folder
  and what happens after import, and a live checklist for the whole install.
- Download shows bytes, rate and ETA on one line instead of curl's meter, warns when a mirror
  stalls, retries with resume, and recognises an already-complete file instead of asking a
  server to resume it (which returns 416 and fails).
- `omarchy-parallels-verify` renders a streaming checklist on a terminal — several checks take
  seconds — and still emits byte-identical JSON when piped or given `--json`.
- First boot: a draining countdown bar, arrow-key setup, masked password entry with
  confirmation, and a summary before anything is applied.
- `host/uninstall.sh` shares the same UI and clears the keyboard-profile preference too.
- `make tui-test`: 50 headless checks (library units, installer flow, failure paths, bundler
  safety, manifest hardening, narrow terminals, render performance) against a local fake
  release server with `prlctl`/`open`/`defaults` stubbed. `make lint` matches CI severity and
  fails if the inlined library drifts.

### Fixed — found by testing this UI on real hardware
- **Progress bars rendered a third of their width** and spinner glyphs were mangled whenever
  `LANG` was unset: bash counts bytes, not characters, without a multibyte `LC_CTYPE`.
- **The tier-2 spinner never appeared to move.** All four quadrant blocks map to a single
  glyph in the Linux console font; braille renders as random letters and `✓` as `ʊ`. Every
  guest glyph is now one photographed on a real tty1.
- **First-boot prompts were invisible**: the systemd unit set `StandardOutput=tty` but not
  `StandardError`, and menus render on stderr.
- **A stray keypress during boot parked the machine on a prompt forever** — prompts now fall
  back to the highlighted default after 60 seconds.
- **Custom mode overwrote an existing VM without asking.** Both places that ask for a folder
  now share one helper that expands `~` and refuses a folder that already holds a VM.
- **Cancelling mid-install orphaned `curl`/`unzip`/`shasum`**, which kept writing after the
  installer said "nothing was installed"; a half-unpacked VM is now marked as such so the next
  run can tell rubble from a machine you care about.
- **`build/bundle.sh` could silently destroy `install.sh`** (missing or duplicated markers, an
  unreadable library) and `--check` would certify the result as in sync.
- A download URL from the manifest is now required to be https (or loopback) — a leading dash
  would otherwise be read by curl as an option.
- The 20-minute silent `unzip -t` pass over 24 GB is gone; the sha256 already proves the bytes.
- The sha256 no longer blocks the UI: a spinner that stops mid-animation looks like a hang.
- `[ -r /dev/tty ]` is not a tty test — the open has to be attempted, and `2>/dev/null` has to
  come *before* `</dev/tty` or the shell's own error reaches the terminal.
- The live region stands down below 44 columns instead of emitting lines that wrap.
- Colours adapt to the terminal's background (OSC 11), so the green check is not 1.75:1 on
  macOS Terminal's default white profile.
- Honest reporting: the installer says when it skipped the signature check and why, and no
  longer claims success when Parallels never confirmed the import.

### Fixed (adversarial UX review)
- Installer no longer hard-depends on `prlctl` (Pro-only) — imports succeed on Standard/trial
- Corrupt-release vs corrupt-download messages distinguished; no more futile multi-GB re-download loop
- YOLO/Guided menu now shows under `curl | bash` (gated on /dev/tty, not stdin)
- Existing-install and free-space checks moved before the download
- Download shows real speed/ETA; Super=Cmd and Spotlight guidance surfaced; OOBE has a bail-to-defaults path and works without gum
- Pre-publish CI guard against unfilled `OWNER` placeholders

### Added
- ARM package builds: 7 of Omarchy's 13 x86-only packages rebuilt for aarch64 and shipped in the image — omacalc/omawrite/omacut (Qt), ttfx (Rust), tobi-try (Ruby), hyprland-preview-share-picker (Rust+gtk4), Obsidian (official ARM64 + software-GL wrapper). See packages/.
- AI disclosure (AI-DISCLOSURE.md)
- Mac keybinding compatibility: Linux profile assigned on import (Cmd+Space → menu), terminal on Cmd+Ctrl+Return (repurposes the ARM-dead herdr bind), docs/keybindings.md, verify check
- Initial image build pipeline (refresh → sysprep → package → release)
- First-boot OOBE with 10-second YOLO countdown
- Adaptive HiDPI auto-resize service (scale derived from the advertised mode)
- `omarchy-parallels-verify` health check
- Guided/YOLO installer, post-import HiDPI step, uninstaller
