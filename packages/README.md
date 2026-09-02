# ARM package builds

Omarchy publishes 13 packages only for x86_64 (via `pkgs.omarchy.org`, whose aarch64 tree
404s), so they're missing on Apple Silicon. Most of them build fine for aarch64 from source —
this directory does exactly that. Each subfolder is a PKGBUILD; [`build-all.sh`](build-all.sh)
builds them on the ARM builder VM.

```sh
# on the builder VM (Arch Linux ARM), as a normal user:
./build-all.sh                          # build everything
./build-all.sh --repo ~/omarchy-arm-extra   # + assemble a local pacman repo
```

## Status (built and tested on aarch64)

| Package | What | Result |
|---|---|---|
| **ttfx** | terminal text effects (Rust) | ✅ builds, runs — `ttfx matrix` animates |
| **tobi-try** | scratchpad-dir manager (Ruby, `arch=any`) | ✅ builds, runs |
| **hyprland-preview-share-picker** | screen-share picker w/ previews (Rust + gtk4) | ✅ builds, runs (`--help`) |
| **omacalc** | Qt Quick calculator | ✅ builds, **renders** under software GL |
| **omawrite** | Qt Quick markdown editor | ✅ builds, links clean |
| **omacut** | Qt Quick + ffmpeg video trimmer | ✅ builds, links clean |
| **obsidian-arm-bin** | Obsidian, official ARM64 build | ✅ builds, **renders** (needs the shipped software-GL wrapper) |

Seven of the thirteen — every one that's actually useful in the VM.

## Deliberately not built

| Package | Why not |
|---|---|
| `omarchy-nvim` | It's "LazyVim + cached plugins" — the image already installs LazyVim, so this is redundant. |
| `asdcontrol` | Controls Apple Studio Display brightness over USB. A Parallels guest has no USB passthrough to the display, so it would build but never function. |
| `qemu-user-static-binfmt` | Registers *x86* emulation. Pointless on an aarch64 host. |
| `dotnet-runtime` / `pinta` | `pinta` needs .NET; Microsoft ships an ARM64 runtime but it's a heavy dependency chain for one image editor. Left as a future PKGBUILD. |
| `obs-studio` | Builds on ARM but there's no GPU acceleration in the VM, so screen-capture/encoding is of limited use; a long C++ build for little payoff. |

## Notes on approach

- **Omarchy's own apps** (`omacalc`/`omawrite`/`omacut`/`ttfx`/`tobi-try`) are portable
  C++/Qt, Rust, or Ruby — they were x86-only purely because that's the tree Omarchy publishes
  to, not for any technical reason. The PKGBUILDs pin the same versions Omarchy ships.
- **`obsidian-arm-bin`** follows the AUR `-bin` convention: it downloads Obsidian's own official
  ARM64 release at build time and never redistributes the proprietary binary. The launcher
  wrapper disables Electron's separate GPU process (which crashes under virtio-gpu software
  rendering) — verified to give a clean launch.
- Everything installs with no missing shared libraries and, for the GUI apps, actually renders
  under Parallels' software rendering.
