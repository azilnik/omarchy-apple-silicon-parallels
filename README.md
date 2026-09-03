# Omarchy for Parallels on Apple Silicon

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1–M4-000000?logo=apple&logoColor=white)
![Omarchy 4 Quattro](https://img.shields.io/badge/Omarchy-4_%22Quattro%22-5e2ca5)
![Hyprland + Quickshell](https://img.shields.io/badge/Hyprland-%2B_Quickshell-1793d1)

**Omarchy 4 "Quattro" as a ready-to-run VM for Apple Silicon Macs (M1–M4)** — the full Hyprland + Quickshell Arch desktop with native HiDPI, live window-resize, and a 60-second first boot. One command, no dual-boot, no bare-metal risk, on every Parallels edition including the free trial — so you can [test-drive Omarchy](https://omarchy.org) for two weeks with no spare hardware.

![One command installs Omarchy for Parallels on Apple Silicon — the installer downloads, verifies, imports, and boots straight to the Hyprland + Quickshell desktop](docs/assets/demo.gif)

```sh
curl -fsSL https://raw.githubusercontent.com/azilnik/omarchy-apple-silicon-parallels/main/install.sh | bash
```

Pick **YOLO** at the prompt (or pass `--yolo`) and the next thing you touch is the Omarchy desktop.

## What you get

- **Omarchy 4 (Quattro)** on Arch Linux ARM — Hyprland 0.56, Quickshell, SDDM, the full theme system
- **Native HiDPI** matched to your Retina display, and a desktop that **follows the Parallels window** as you resize it
- **Omarchy's x86-only apps, rebuilt for ARM**: omacalc, omawrite, omacut, ttfx, tobi-try, the Hyprland share picker, and Obsidian ([from source](packages/))
- **First-boot setup** — username/password/hostname, or a 10-second countdown to sensible defaults
- **Verifiable**: `omarchy-parallels-verify` inside the VM prints a green/red health report

## Install

Requirements: Apple Silicon Mac (M1–M4+), Parallels Desktop (any edition), ~25 GB free.

The one-liner above downloads, verifies, imports, and boots. Prefer manual? Grab the image from the [releases manifest](https://dl.omarchy-apple-silicon.zilnik.me/latest.json), verify the checksum, unzip into `~/Parallels`, double-click `Omarchy.pvm` (choose **Copied** if asked), then set View → Retina Resolution → **More Space**.

## First things to know

- **`Super` is `⌘ Cmd`.** Menu is **Cmd+Space**; terminal is **Cmd+Ctrl+Return** (Parallels keeps Cmd+Return for fullscreen). Full map + how to get native bindings back: [docs/keybindings.md](docs/keybindings.md).
- Default login on the YOLO path is **`omarchy` / `omarchy`** — run **`passwd`** to change it.

## Security & provenance

- Every release ships a **sha256 + minisign signature** and the installer verifies both (key: [`minisign.pub`](minisign.pub)). The image is served from Cloudflare R2 (GitHub caps assets at 2 GiB), but the GitHub-hosted checksum and signature are what you trust — not the host.
- Built **solely by the public scripts in [`build/`](build/)** from a stock [Archboot](https://archboot.com) aarch64 base plus the [`omarchy-arm`](https://github.com/alexisraitano-myffu/omarchy-arm) port (audited: no `curl | bash`, no `eval`, no install hooks). Rebuild it yourself: [docs/rebuild-from-iso.md](docs/rebuild-from-iso.md).
- **Sysprepped**: no SSH/host keys, no machine-id, no credentials or shell history — first boot regenerates identity, and SSH is off by default.
- Parallels Tools (userspace only) runs under *your* licensed Parallels; a Tools-free rebuild path is in the docs.
- [Report a vulnerability](SECURITY.md) · [AI disclosure](AI-DISCLOSURE.md) — built by AI under human direction.

## Known limitations

- **No GPU acceleration** — Parallels' virtio-gpu is software-rendered for Linux ARM guests. Fine for real use; don't judge animation polish here.
- **`omarchy-update` prints a harmless keyring error** on ARM (`omarchy-keyring` is x86-only); the update still works.
- A few x86-only packages are deliberately skipped (`asdcontrol`, `obs-studio`, `pinta`) — see [docs/arm-limitations.md](docs/arm-limitations.md).
- Verified on **M3 (Studio Display)**; reports from other machines welcome — see [test/VERIFY.md](test/VERIFY.md).

## Uninstall & license

`./host/uninstall.sh` removes it. Scripts and docs are MIT; Omarchy, Arch Linux ARM, and Parallels Tools keep their own licenses.
