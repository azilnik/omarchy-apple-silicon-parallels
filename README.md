# Omarchy for Apple Silicon

**Omarchy 4 "Quattro" as a ready-to-run VM for Apple Silicon Macs (M1–M4).** A full Hyprland + Quickshell Arch desktop in Parallels — one command, no dual-boot, no bare-metal risk.

> **Test-drive the feel of [Omarchy](https://omarchy.org) free for two weeks on the [Parallels trial](https://www.parallels.com/products/desktop/trial/) — no spare hardware, no dual-boot, one command.**

A ready-to-run **Omarchy 4 (Quattro)** — Arch Linux ARM, Hyprland 0.56, and the new Quickshell desktop — as a virtual machine for **Apple Silicon Macs (M1–M4)**, with native HiDPI, a desktop that follows the Parallels window as you resize it, and a 60-second first-boot setup. Works on every Parallels edition, including Standard and the free trial.

```sh
curl -fsSL https://raw.githubusercontent.com/azilnik/omarchy-apple-silicon-vm/main/install.sh | bash
```

Pick **YOLO** at the prompt (or pass `--yolo`) and the next thing you interact with is the Omarchy desktop.

## What you get

- **Omarchy 4** (quattro) on Arch Linux ARM — Hyprland, Quickshell, SDDM, the full theme system
- **Native HiDPI**: 2× rendering matched to your Retina display (5120×2880 on a Studio Display)
- **Live resize**: drag the Parallels window; the desktop follows at the right scale
- **First-boot setup**: username, password, hostname — or a 10-second countdown to sensible defaults
- **Omarchy's apps, rebuilt for ARM**: omacalc, omawrite, omacut, ttfx, the share picker, and Obsidian — packages Omarchy ships x86-only, [built from source for aarch64](packages/)
- **Verifiable**: run `omarchy-parallels-verify` inside the VM for a machine-readable health report

## Install

**One-liner** (above), or **manually**: download the latest image from the [releases manifest](https://dl.omarchy-apple-silicon.zilnik.me/latest.json), verify the checksum, unzip into `~/Parallels`, double-click `Omarchy.pvm` (choose **Copied** if asked), then set View → Retina Resolution → **More Space**.

Requirements: Apple Silicon Mac (M1–M4+), Parallels Desktop (any edition), ~25 GB free disk.

## First steps once it boots

New to Arch or tiling window managers? Two things save everyone's first ten minutes:

- **The `Super` key is `⌘ Cmd`** on your Mac keyboard. Every Omarchy shortcut hint that says "Super" means Cmd.
- **Menu: `Cmd+Space`. Terminal: `Cmd+Ctrl+Return`.** The image assigns Parallels' Linux keyboard profile so Cmd+Space opens the Omarchy menu (not Spotlight); Parallels keeps Cmd+Return for fullscreen, so the terminal ships on Cmd+Ctrl+Return. Full map + how to restore native Super+Return: [docs/keybindings.md](docs/keybindings.md).
- Default login is **`omarchy` / `omarchy`** on the quick-start (YOLO) path — run **`passwd`** in a terminal to change it.
- Sanity check: open a terminal (**Cmd+Ctrl+Return**) and run **`omarchy-parallels-verify`** — it prints a health report and exits green when all is well.

## Security & provenance

- Every release ships a **sha256 checksum** and a **minisign signature**; the installer verifies both. Public key: [`minisign.pub`](minisign.pub).
- The image is produced **solely by the public scripts in [`build/`](build/)** against a stock [Archboot](https://archboot.com) aarch64 install plus the [`omarchy-arm`](https://github.com/alexisraitano-myffu/omarchy-arm) port. Rebuild it yourself: [docs/rebuild-from-iso.md](docs/rebuild-from-iso.md).
- Before adopting `omarchy-arm` we audited its installer: no `curl | bash`, no `eval`, no install hooks, every network host enumerated and expected (Arch Linux ARM mirrors, AUR, GitHub). The audit steps are documented so you can repeat them.
- Images are **sysprepped**: no SSH keys, no host keys, no machine-id, no credentials, no shell history. First boot regenerates all identity. SSH is **off** by default.
- Parallels Tools (userspace only — clipboard, shared folders, time sync) is preinstalled and runs under *your* licensed Parallels install. Object to redistributed Tools binaries? The rebuild doc has a Tools-free path.
- **Where the bytes come from:** code and this page live on GitHub; the image itself is served from `dl.omarchy-apple-silicon.zilnik.me` (Cloudflare R2, maintainer-controlled) because GitHub caps release assets at 2 GiB. The checksum in the GitHub-hosted `latest.json` and the minisign signature are what bind the two together — verify them (the installer does) and the hosting location doesn't require trust.
- Report vulnerabilities via [SECURITY.md](SECURITY.md).
- This project was built by AI under human direction — see [AI-DISCLOSURE.md](AI-DISCLOSURE.md).

## Known limitations (honesty section)

- **Software rendering.** Parallels' virtio-gpu has no 3D acceleration for Linux ARM guests — fine for real use, but don't judge Omarchy's animation polish here.
- **Most of Omarchy's x86-only packages are rebuilt for ARM and ship in the image** — `omacalc`, `omawrite`, `omacut`, `ttfx`, `tobi-try`, the Hyprland share picker, and Obsidian (see [packages/](packages/)). A few are deliberately left out (`asdcontrol` needs USB the VM lacks; `obs-studio`/`pinta` aren't worth their build cost without GPU accel). Full ARM notes: [docs/arm-limitations.md](docs/arm-limitations.md).
- **`omarchy-update` prints a keyring error on ARM** (`omarchy-keyring` is x86-only). Harmless; the update still works.
- **A couple of Cmd shortcuts belong to Parallels, not Omarchy** — Cmd+Return (fullscreen) and Cmd+Q (quit) are intercepted before the guest. The image works around Cmd+Return by binding the terminal to Cmd+Ctrl+Return; [docs/keybindings.md](docs/keybindings.md) explains the full picture and the one-time Parallels tweak to get native bindings back.
- Verified on: M3 (Studio Display). Other machines: see [test/VERIFY.md](test/VERIFY.md) — reports welcome.

## Uninstall

```sh
./host/uninstall.sh
```

## License

Scripts and docs: MIT. Omarchy, Arch Linux ARM, and Parallels Tools remain under their own licenses.
