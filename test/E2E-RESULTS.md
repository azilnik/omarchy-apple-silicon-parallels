# End-to-end test results (v0.1.0, 2026-09-02)

First full run of the pipeline: `package.sh` built a real 5.1 GB image, `install.sh` cold-installed
it as a fresh VM (isolated via a HOME override), first-boot ran, and the result was verified.

## What passed

- **Build pipeline** (`package.sh`): clone → sysprep → compact → strip identity → zip. Produced
  `omarchy-parallels-v0.1.0.zip` (5.1 GB) + sha256.
- **Import was dialog-free**: because the image ships with MAC + `SourceVmUuid` stripped, Parallels
  imported it without a "Copied or Moved?" prompt and generated a fresh MAC. `install.sh` reported
  `✓ VM registered`.
- **First-boot OOBE**: renamed the build user `ari → omarchy`, set the default password, autologin,
  self-disabled. Desktop came up on its own.
- **Fresh identity**: machine-id `fb95…` ≠ builder `b168…`; SSH host keys regenerated; no `ari`
  account, only `/home/omarchy`.
- **Sysprep cleanup**: `rust` toolchain removed, `armbuild` gone, pacman cache 132K, no shell history.
- **All 7 ARM packages present** and omacalc **rendered** on the fresh install.
- **Keybinding drop-in works**: `Cmd+Ctrl+Return` opened a terminal in the fresh VM.
- **`omarchy-parallels-verify`**: **pass** (as root).

## Bugs found and fixed during this run

1. **sysprep couldn't rename the build user** — `usermod` fails on the logged-in autologin user, so
   the image shipped as `ari` with a locked password. Moved the rename to first-boot (runs before
   the display manager) and record the build user in a marker.
2. **`package.sh` dialog guidance was wrong** — the real dialog on an APFS clone is "Duplicate MAC
   addresses → Create new", plus a trial-edition nag, not "Copied or Moved?". Corrected script +
   maintainer doc.
3. **Stale coredumps + build-user caches shipped in the image** → `omarchy-crash-watch` surfaced them
   as "Process crashed" notifications on first boot, plus ~336 MB of bloat. sysprep now clears
   `/var/lib/systemd/coredump/*` and the build user's `.cache` / test app state. Fix validated on the
   live install (15 coredumps → 0, cache gone).

## Known, not-a-bug-for-real-users

- `install.sh` post-import matches the VM by the name "Omarchy"; with two VMs registered (the test
  had the builder + the fresh install) it can target the first match. A real recipient has exactly
  one, so this is only a test artifact.

## Not re-run

The three fixes above were each validated directly (sysprep cleanup proven on the live VM; rename
logic reasoned + firstboot installed), but a second full image rebuild with all fixes folded in was
not run end-to-end. That clean rebuild is the final confirmation step before cutting a public v0.1.
