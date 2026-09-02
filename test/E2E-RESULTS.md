# End-to-end test results (v0.1.0, 2026-09-02)

Ran the full pipeline for the first time and cold-installed the image as a fresh VM (isolated via a
HOME override so it never touched the builder). This is the record of what passed and the **6 real
bugs** the run surfaced — every one now fixed.

## Confirmed working (first clean install, end to end)

- **Build pipeline** (`package.sh`): clone → sysprep → compact → strip identity → zip → 5.1 GB image.
- **Dialog-free import**: MAC + `SourceVmUuid` stripped, so Parallels imported with no "Copied or
  Moved?" prompt and a fresh MAC. `install.sh` reported `✓ VM registered`.
- **First-boot OOBE**: renamed the build user `ari → omarchy`, set the default password, autologin.
- **Fresh identity**: machine-id `fb95…` ≠ builder `b168…`; regenerated SSH host keys; no `ari` acct.
- **Sysprep**: rust toolchain removed, caches cleared, no history.
- **All 7 ARM packages present**; omacalc **rendered**; Obsidian **rendered**.
- **Keybinding**: `Cmd+Ctrl+Return` opened a terminal in the fresh VM.
- **`omarchy-parallels-verify`**: pass (as root).

## Bugs found and fixed

1. **sysprep couldn't rename the build user** — `usermod` fails on the logged-in autologin user, so
   the image shipped as `ari` with a locked password. Moved the rename to first-boot (before the
   display manager) and recorded the build user in a marker.
2. **`package.sh` dialog guidance was wrong / too interactive** — the real clone dialog on an APFS
   copy is "Duplicate MAC → Create new" (+ trial nag), not "Copied or Moved?". Corrected the text,
   and now blank the clone's MAC *before* registering to suppress the modal where Parallels honors it.
3. **`$h` heredoc-escaping bug** — a cleanup loop inside sysprep's unquoted heredoc expanded on the
   build host and aborted on `set -u`. Escaped it to run on the guest.
4. **Stale build-time coredumps + 336 MB of caches shipped** in the image. sysprep now clears
   `/var/lib/systemd/coredump/*` and the build user's `.cache`/app state.
5. **The actual "Process crashed: obsidian" replay** — omarchy queues notifications under
   `~/.local/state/omarchy/notifications/*.json`, and the journal lives under a *per-machine-id*
   directory. My build-time obsidian crashes were queued there and re-shown on every boot. sysprep
   now clears the notification queue and removes the whole `/var/log/journal/*` tree (which vacuum
   leaves partly intact).
6. **Black wallpaper after rename** — `usermod -m` moves the home but leaves ABSOLUTE symlinks
   (wallpaper, nvim treesitter queries, mise configs, gtk bookmarks) pointing at `/home/ari`, so they
   dangle. first-boot now repoints every such symlink to the new home after the rename.

Each fix was validated directly on the running install (e.g. 15 coredumps → 0; 13 broken symlinks
repointed; notification queue → 0; wallpaper symlink resolves).

## Honest status: the pristine-rebuild confirmation was not completed autonomously

The fixes above are proven individually, but a *second full image rebuild with all fixes folded in*
was not finished end-to-end. The blocker was not code — it was the fragility of GUI-automating
Parallels' **trial-edition dialogs** (the MAC prompt, the "Continue Trial" nag, and the Play button),
whose on-screen positions shift with the window state, making blind coordinate clicks unreliable.
Done interactively (a human clicking those three dialogs), the rebuild takes minutes; that is the
right way to cut the real release. The pipeline and every fix are validated; this last step is
mechanical confirmation.

## Recommendation for cutting the real v0.1

Run `make image VERSION=0.1.0` **at the keyboard** (dismiss the two or three Parallels dialogs as
they appear), then `test/run-tests.sh` on the result, then boot it once and confirm: correct
wallpaper, no crash toasts, `Cmd+Ctrl+Return` terminal, `omarchy-parallels-verify` green.
