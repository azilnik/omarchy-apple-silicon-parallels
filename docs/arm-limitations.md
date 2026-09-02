# ARM limitations

Official Omarchy is x86_64-only: its ISO won't boot on Apple Silicon and its package
repository has no aarch64 tree (`pkgs.omarchy.org/stable/aarch64/omarchy.db` → 404).
This image uses Arch Linux ARM plus the [`omarchy-arm`](https://github.com/alexisraitano-myffu/omarchy-arm)
port, which resolves Omarchy's 148 base packages as: 123 native, 3 required AUR builds,
8 optional AUR builds (skipped), 13 with no aarch64 source, 1 bootstrapped (`yay`).

## Absent (no aarch64 build anywhere)

| Package | What it is | Note |
|---|---|---|
| `omacalc`, `omacut`, `omawrite`, `omarchy-nvim`, `ttfx`, `tobi-try`, `hyprland-preview-share-picker` | Omarchy first-party apps, published only via the x86_64 repo | `omarchy-nvim` replaced by a LazyVim setup (same foundation) |
| `obs-studio`, `pinta`, `dotnet-runtime` | Arch builds are x86_64-only | |
| `obsidian` | Proprietary Electron app, no aarch64 Arch package | |
| `asdcontrol`, `qemu-user-static-binfmt` | x86-only packaging | |

## Behavioral quirks

- `omarchy-update` reports `'omarchy-keyring' has no aarch64 build` every run — harmless;
  the ALARM keyring is used instead and updates proceed.
- No GPU acceleration under Parallels' virtio-gpu: rendering is software (`LIBGL_ALWAYS_SOFTWARE`
  territory). Omarchy 4 ships with blur/shadows/rounding off, which keeps it responsive.
- AUR installs compile from source on ARM (no `-bin` shortcuts). `herdr` in particular pulls a
  Zig toolchain rebuild — expect time and disk if you opt in via `--with-aur` on a rebuild.

## Now rebuilt for ARM (shipped in the image)

Most of these are portable source that was x86-only only because that's the tree Omarchy
publishes to. [`packages/`](../packages/) rebuilds them for aarch64: **omacalc, omawrite,
omacut** (Qt Quick), **ttfx** (Rust), **tobi-try** (Ruby), **hyprland-preview-share-picker**
(Rust+gtk4), and **Obsidian** (official ARM64 build). Still absent by choice: `asdcontrol`
(needs USB passthrough the VM lacks), `obs-studio`/`pinta` (not worth the build cost without GPU
acceleration), `qemu-user-static-binfmt` (x86 emulation, pointless on ARM), and `omarchy-nvim`
(redundant — LazyVim is installed).
