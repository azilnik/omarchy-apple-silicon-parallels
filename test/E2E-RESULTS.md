# End-to-end test results (v0.1.0, 2026-09-02)

The full pipeline now runs **fully autonomously, end to end, with no GUI interaction** — build the
image, cold-import it as a recipient would, and assert every invariant from inside the guest. The
final clean re-build + re-import passes **26/26 checks**, including a host-side capture proving the
desktop paints its wallpaper.

## The unlock: headless `prlctl`

The earlier blocker was Parallels' trial dialogs (duplicate-MAC prompt, "Continue Trial" nag, Play
button) whose shifting positions defeated blind coordinate-clicking. Re-probing the edition showed
that **`prlctl clone / start / register / exec / stop / unregister` all work here** (Parallels
Desktop 27 trial). That removes every dialog:

- `prlctl clone` mints a fresh UUID **and** MAC with no duplicate-MAC prompt.
- `prlctl start` boots with no Play button.
- `prlctl register` imports the shipped `.pvm` with no "Copied or Moved?" dialog and a fresh MAC —
  exactly the recipient's double-click, driven from the CLI.
- `prlctl exec` runs commands inside the guest as root **without sshd**, so the cold-import test can
  assert the YOLO image (which ships with sshd off) from the inside.

`build/package.sh` and `test/run-tests.sh` were rewritten around this. `make image` and `make test`
now run unattended.

## Result: 26/26 on the clean re-build

Cold-imported the freshly built `omarchy-apple-silicon-parallels-v0.1.0.zip` and asserted, from inside the guest:

- Pre-boot: `SourceVmUuid` stripped, MAC blanked, disk on SATA.
- Headless import + fresh MAC assigned.
- First-boot completed (marker cleared, service self-disabled).
- Fresh identity: machine-id ≠ builder, SSH host keys regenerated, no `authorized_keys`.
- User renamed `ari → omarchy`; `/home/ari` gone; **no dangling symlinks**; wallpaper link resolves.
- No crash-toast queue, no coredumps, no crash records in the old journal.
- All 7 ARM-built apps installed; SDDM autologin → `omarchy`; default-password reminder armed; sshd off.
- Mac keybinding drop-in present in `bindings.lua`.
- `omarchy-parallels-verify` verdict = **pass** (all 12 checks).
- **Desktop paints wallpaper + bar** — fresh session, host-side `prlctl capture`, 803 KB frame (a
  black frame is a few KB). Screenshot saved to `dist/desktop-verified-v0.1.0.png`.

## Findings run down (all fixed)

The first end-to-end run surfaced six real pipeline bugs; every one is fixed and re-verified:

1. **sysprep can't rename the logged-in build user** (`usermod: user ari is currently used`) → the
   rename moved to first-boot, which runs before SDDM when no one is logged in; sysprep records the
   build user in a marker file.
2. **Clone/import required GUI clicks** → replaced the `open`-and-click flow with `prlctl`
   clone/register (fresh identity, no dialogs).
3. **`\$h` expanded on the build host** inside sysprep's `<<EOF` heredoc under `set -u` → escaped.
4. **Build coredumps + 336 MB of caches shipped** → sysprep clears them.
5. **Stale "Process crashed: obsidian" toasts** — not from coredumps but from omarchy's notification
   queue (`~/.local/state/omarchy/notifications/*.json`) plus the journal under the *old* machine-id
   dir → sysprep wipes both.
6. **Black wallpaper after rename** — `usermod -m` leaves absolute symlinks pointing at `/home/ari`
   (wallpaper, nvim, mise) → first-boot repoints them after the rename.

## Findings from the headless re-run (also fixed)

The deep guest-side assertions surfaced polish issues the earlier surface-level test missed:

- **5 dangling symlinks shipped** — build-session runtime cruft carrying the build user's name or the
  old machine-id: mise's `trusted-configs/home-ari-*` (bare `/home/ari` target, which first-boot's
  trailing-slash repoint had missed), PulseAudio's machine-id-keyed runtime link, and Chromium's
  `Singleton{Lock,Socket,Cookie}`. → sysprep now removes them; first-boot repoints bare-home targets
  and sweeps any residual dangling links after repointing. Re-verified: 0 dangling.
- **The "black wallpaper" scare, run to ground** — a capture taken mid-investigation showed black.
  Traced end to end: the desktop had simply **idled into a lock/DPMS state** during the long probe. A
  fresh autologin paints the full Winding-Road desktop, pixel-identical to the builder (803 KB frame
  vs 8 KB black). No wallpaper regression — but the harness now includes a desktop-paint check so a
  genuine one couldn't slip past.
- **Three harness false-negatives** (not image bugs): the ssh-host-key assertion used an `ls && wc`
  idiom that returned empty through `prlctl exec`; the verify call relied on PATH and on `prlctl
  exec`'s (intermittently mangled) exit code; the keybinding check looked for a standalone file when
  the drop-in is appended into `bindings.lua`. All three fixed to assert correctly.

## What still needs a human

Cutting the public release: create the minisign key, set up Cloudflare R2, run
`MINISIGN_KEY=… build/release.sh 0.1.0` to upload + write `latest.json` + tag, and flip the repo
public. The image itself is built, verified, and ready at `dist/omarchy-apple-silicon-parallels-v0.1.0.zip`.
