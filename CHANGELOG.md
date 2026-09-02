# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org).

## [Unreleased]

### Fixed (adversarial UX review)
- Installer no longer hard-depends on `prlctl` (Pro-only) — imports succeed on Standard/trial
- Corrupt-release vs corrupt-download messages distinguished; no more futile multi-GB re-download loop
- YOLO/Guided menu now shows under `curl | bash` (gated on /dev/tty, not stdin)
- Existing-install and free-space checks moved before the download
- Download shows real speed/ETA; Super=Cmd and Spotlight guidance surfaced; OOBE has a bail-to-defaults path and works without gum
- Pre-publish CI guard against unfilled `OWNER` placeholders

### Added
- Mac keybinding compatibility: Linux profile assigned on import (Cmd+Space → menu), terminal on Cmd+Ctrl+Return (repurposes the ARM-dead herdr bind), docs/keybindings.md, verify check
- Initial image build pipeline (refresh → sysprep → package → release)
- First-boot OOBE with 10-second YOLO countdown
- Adaptive HiDPI auto-resize service (scale derived from the advertised mode)
- `omarchy-parallels-verify` health check
- Guided/YOLO installer, post-import HiDPI step, uninstaller
