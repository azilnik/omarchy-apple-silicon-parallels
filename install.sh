#!/bin/bash
# omarchy-apple-silicon-parallels installer — get Omarchy running in Parallels on an Apple Silicon Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/azilnik/omarchy-apple-silicon-parallels/main/install.sh | bash
#
# Interactive by default; `--yolo` (or choosing YOLO at the menu) runs fully headless:
# download → verify → import → HiDPI pref → boot, with the in-guest first-boot applying
# safe defaults after a short countdown.

set -euo pipefail

MANIFEST_URL="${OMARCHY_PARALLELS_MANIFEST:-https://dl.omarchy-apple-silicon.zilnik.me/latest.json}"
PUBKEY="${OMARCHY_PARALLELS_PUBKEY:-RWT5YqKK9D9tIBTX2tg4bz8TalDtG0qcXsN+tHu+QGMGfZXfZ/3Bm7Nl}"   # minisign public key, baked in at release
DEST="$HOME/Parallels"
YOLO=0
[[ ${1:-} == "--yolo" || ${1:-} == "-y" ]] && YOLO=1

# ---------- presentation (degrades cleanly: no color when not a tty / NO_COLOR) ----------
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  B=$'\033[1m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; RED=$'\033[31m'; N=$'\033[0m'
else B=""; CYAN=""; GREEN=""; RED=""; N=""; fi
step()  { printf '\n%s==>%s %s%s%s\n' "$CYAN" "$N" "$B" "$1" "$N"; }
note()  { printf '    %s\n' "$1"; }
ok()    { printf '    %s✓%s %s\n' "$GREEN" "$N" "$1"; }
die()   { printf '\n%s✗ %s%s\n' "$RED" "$1" "$N" >&2; exit 1; }
confirm() { # confirm <prompt> — auto-yes in yolo mode
  [[ $YOLO -eq 1 ]] && return 0
  read -r -p "    $1 [Y/n] " a </dev/tty || return 0
  [[ -z $a || $a =~ ^[Yy] ]]
}

printf '%s\n' "${B}Omarchy for Parallels on Apple Silicon${N} — Arch + Hyprland, one command, no dual-boot."

# ---------- mode selection ----------
# Gate on /dev/tty, not stdin: under `curl | bash` stdin is the script, but the controlling
# terminal is still reachable at /dev/tty. If there's no tty at all (fully non-interactive),
# default to YOLO so the install can still complete unattended.
if [[ $YOLO -eq 0 ]]; then
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    printf '\n  1) %sYOLO%s      — no more questions: download, import, boot, sensible defaults\n' "$B" "$N"
    printf '  2) Guided    — explain and confirm each step\n\n'
    read -r -p "  Choose [1/2] (default 1): " CHOICE </dev/tty || CHOICE=1
    [[ -z $CHOICE || $CHOICE == 1 ]] && YOLO=1
  else
    YOLO=1   # no terminal to ask — proceed unattended
  fi
fi

# ---------- preflight ----------
step "Checking this Mac"
[[ $(uname -m) == arm64 ]] || die "Apple Silicon required (this is an ARM64 image)."
[[ -d "/Applications/Parallels Desktop.app" ]] || die "Parallels Desktop not found. Any edition works, including the free 14-day trial: https://www.parallels.com/products/desktop/trial/"
ok "Apple Silicon + Parallels Desktop present"
FREE_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
[[ $FREE_GB -ge 25 ]] || die "Need ~25 GB free (image unpacks to ~10-12 GB); only ${FREE_GB} GB available."
ok "${FREE_GB} GB free disk"
# Check for a leftover install up front, before spending 10 minutes downloading (M4).
[[ -d "$DEST/Omarchy.pvm" ]] && die "$DEST/Omarchy.pvm already exists. Remove it (or ./host/uninstall.sh) and re-run."
ok "no existing install in the way"

# ---------- manifest ----------
step "Fetching release info"
MANIFEST=$(curl -fsSL "$MANIFEST_URL") || die "Could not fetch $MANIFEST_URL"
VER=$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' <<<"$MANIFEST" | head -1)
URL=$(sed -n 's/.*"url" *: *"\([^"]*\)".*/\1/p' <<<"$MANIFEST" | head -1)
SHA=$(sed -n 's/.*"sha256" *: *"\([^"]*\)".*/\1/p' <<<"$MANIFEST" | head -1)
SIZE=$(sed -n 's/.*"size_human" *: *"\([^"]*\)".*/\1/p' <<<"$MANIFEST" | head -1)
[[ -n $VER && -n $URL && -n $SHA ]] || die "Malformed manifest"
ok "Omarchy for Parallels on Apple Silicon v$VER (${SIZE:-a few GB} download)"
confirm "Download and install v$VER into $DEST?" || die "Cancelled."

# ---------- download (resumable) ----------
step "Downloading image"
note "${SIZE:-~3-4 GB} — several minutes on a typical connection. Safe to interrupt; re-running resumes."
mkdir -p "$DEST"
ZIP="$DEST/omarchy-apple-silicon-parallels-v$VER.zip"
# default curl meter (shows speed + ETA + elapsed) beats --progress-bar for a multi-GB file (M3)
curl -fL -C - -o "$ZIP" "$URL" || die "Download failed. Re-run to resume from where it stopped."
ok "downloaded"

step "Verifying integrity"
GOT=$(shasum -a 256 "$ZIP" | awk '{print $1}')
[[ $GOT == "$SHA" ]] || { rm -f "$ZIP"; die "Checksum mismatch — the download was corrupted in transit (removed it). Re-run to download again."; }
ok "sha256 verified"
if [[ -n $PUBKEY ]] && command -v minisign >/dev/null 2>&1; then
  curl -fsSL -o "$ZIP.minisig" "$URL.minisig" 2>/dev/null &&
    { minisign -Vm "$ZIP" -P "$PUBKEY" >/dev/null 2>&1 && ok "signature verified" || die "SIGNATURE INVALID — do not use this image. Please open an issue."; }
else
  note "signature check skipped ($([[ -z $PUBKEY ]] && echo 'no key configured for this release' || echo 'minisign not installed — brew install minisign to enable'))"
fi

# ---------- unpack ----------
step "Unpacking"
# The checksum already passed, so the bytes are exactly what the release published. If unzip
# still fails, the RELEASE artifact itself is broken — re-downloading gets the same bad bytes,
# so say so and stop rather than looping the user through another multi-GB download (B2).
if ! unzip -tq "$ZIP" >/dev/null 2>&1; then
  die "This release's image is corrupt (checksum matched, but it won't unpack). This is a problem with the release, not your download — please open an issue. The file is at $ZIP."
fi
unzip -q "$ZIP" -d "$DEST" >/dev/null || die "Could not unpack into $DEST (out of space, or permissions?)."
ok "unpacked to $DEST/Omarchy.pvm"
rm -f "$ZIP" "$ZIP.minisig"

# ---------- import ----------
step "Importing into Parallels"
note "A .pvm is a Parallels VM. If asked 'Copied or Moved?', choose Copied (either works — Copied just keeps your download in place)."
open "$DEST/Omarchy.pvm" || die "Could not hand the VM to Parallels. Open it yourself: $DEST/Omarchy.pvm"
# prlctl confirmation is a nicety, not a requirement — it exists on most editions but not all,
# and the import succeeds regardless. Never fail the install just because prlctl is absent (B3).
PRLCTL="/usr/local/bin/prlctl"
if [[ -x $PRLCTL ]]; then
  REGISTERED=0
  for _ in $(seq 1 24); do
    "$PRLCTL" list -a --no-header 2>/dev/null | grep -q Omarchy && { REGISTERED=1; break; }; sleep 5
  done
  [[ $REGISTERED -eq 1 ]] && ok "VM registered" ||
    note "couldn't confirm registration automatically — if the VM didn't appear, double-click $DEST/Omarchy.pvm"
else
  note "handed off to Parallels (this edition has no prlctl to confirm with)"
fi

# ---------- post-import (HiDPI pref, inline — no second remote fetch) ----------
# Retina 'More Space' lives in host prefs keyed by the VM's UUID, which is regenerated on import,
# so it can't ship inside the image. Best-effort here; the UI path below always works.
UUID=""
[[ -x $PRLCTL ]] && UUID=$("$PRLCTL" list -a --no-header 2>/dev/null | awk '/Omarchy/{print $1; exit}' | tr -d '{}')
[[ -z $UUID && -f "$DEST/Omarchy.pvm/config.pvs" ]] && \
  UUID=$(grep -o '<VmUuid>{[^}]*}</VmUuid>' "$DEST/Omarchy.pvm/config.pvs" | head -1 | tr -d '{}' | sed 's/<[^>]*>//g')
[[ -n $UUID ]] && defaults write "com.parallels.Parallels Desktop" "{$UUID}.0.ConsoleWidgetScaleFactorWithDynres" -int 2 2>/dev/null || true

# ---------- boot ----------
step "Starting Omarchy"
# Actually start the VM. `open` alone just opens the window and won't reliably auto-start a
# freshly-registered VM, so boot it with prlctl when available; then open the window so the user
# can watch first boot. On editions without prlctl, open is the only lever we have.
[[ -x $PRLCTL ]] && "$PRLCTL" start Omarchy >/dev/null 2>&1 || true
open "$DEST/Omarchy.pvm" 2>/dev/null || true
printf '\n%s✓ Done.%s ' "$GREEN" "$N"
if [[ $YOLO -eq 1 ]]; then
  printf 'The VM is booting. First boot applies defaults after a short countdown:\n'
  printf '  login %somarchy%s / password %somarchy%s — change it after first login by running %spasswd%s.\n' "$B" "$N" "$B" "$N" "$B" "$N"
else
  printf 'The VM is booting — answer the first-boot questions in its window.\n'
fi
cat <<TIPS

${B}A few things every first-timer needs to know:${N}
  • Omarchy's shortcuts use the ${B}Super${N} key — on your Mac keyboard that's ${B}⌘ Cmd${N}.
  • Menu: ${B}Cmd+Space${N}.  Terminal: ${B}Cmd+Ctrl+Return${N}.  All keys: ${B}Cmd+K${N}.
    (Parallels keeps Cmd+Return for fullscreen — docs/keybindings.md restores native Super+Return.)
  • If the desktop looks soft: View → Retina Resolution → ${B}More Space${N} (it adapts in seconds).
  • To confirm everything's healthy, open a terminal and run: ${B}omarchy-parallels-verify${N}
TIPS
