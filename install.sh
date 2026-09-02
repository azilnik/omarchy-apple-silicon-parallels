#!/bin/bash
# omarchy-parallels installer — get Omarchy running in Parallels on an Apple Silicon Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/OWNER/omarchy-parallels/main/install.sh | bash
#
# Interactive by default; `--yolo` (or choosing YOLO at the menu) runs fully headless:
# download → verify → import → HiDPI pref → boot, with the in-guest first-boot applying
# safe defaults on a 10-second countdown.

set -euo pipefail

MANIFEST_URL="${OMARCHY_PARALLELS_MANIFEST:-https://dl.omarchy-parallels.zilnik.me/latest.json}"
PUBKEY="${OMARCHY_PARALLELS_PUBKEY:-}"   # minisign public key, baked in at release
DEST="$HOME/Parallels"
YOLO=0
[[ ${1:-} == "--yolo" || ${1:-} == "-y" ]] && YOLO=1

# ---------- presentation (degrades cleanly: no color when not a tty / NO_COLOR) ----------
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  B=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; RED=$'\033[31m'; N=$'\033[0m'
else B=""; DIM=""; CYAN=""; GREEN=""; RED=""; N=""; fi
step()  { printf '\n%s==>%s %s%s%s\n' "$CYAN" "$N" "$B" "$1" "$N"; }
note()  { printf '    %s%s%s\n' "$DIM" "$1" "$N"; }
ok()    { printf '    %s✓%s %s\n' "$GREEN" "$N" "$1"; }
die()   { printf '\n%s✗ %s%s\n' "$RED" "$1" "$N" >&2; exit 1; }
confirm() { # confirm <prompt> — auto-yes in yolo mode
  [[ $YOLO -eq 1 ]] && return 0
  read -r -p "    $1 [Y/n] " a </dev/tty || return 0
  [[ -z $a || $a =~ ^[Yy] ]]
}

printf '%s\n' "${B}Omarchy on Parallels${N} — Arch + Hyprland, one command, no dual-boot."

# ---------- mode selection ----------
if [[ $YOLO -eq 0 && -t 0 ]]; then
  printf '\n  1) %sYOLO%s      — no more questions: download, import, boot, sensible defaults\n' "$B" "$N"
  printf '  2) Guided    — explain and confirm each step\n\n'
  read -r -p "  Choose [1/2] (default 1): " CHOICE </dev/tty || CHOICE=1
  [[ -z $CHOICE || $CHOICE == 1 ]] && YOLO=1
fi

# ---------- preflight ----------
step "Checking this Mac"
[[ $(uname -m) == arm64 ]] || die "Apple Silicon required (this is an ARM64 image)."
[[ -d "/Applications/Parallels Desktop.app" ]] || die "Parallels Desktop not found. Any edition works, including the free 14-day trial: https://www.parallels.com/products/desktop/trial/"
ok "Apple Silicon + Parallels Desktop present"
FREE_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
[[ $FREE_GB -ge 25 ]] || die "Need ~25 GB free (image unpacks to ~10-12 GB); only ${FREE_GB} GB available."
ok "${FREE_GB} GB free disk"

# ---------- manifest ----------
step "Fetching release info"
MANIFEST=$(curl -fsSL "$MANIFEST_URL") || die "Could not fetch $MANIFEST_URL"
VER=$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' <<<"$MANIFEST" | head -1)
URL=$(sed -n 's/.*"url" *: *"\([^"]*\)".*/\1/p' <<<"$MANIFEST" | head -1)
SHA=$(sed -n 's/.*"sha256" *: *"\([^"]*\)".*/\1/p' <<<"$MANIFEST" | head -1)
SIZE=$(sed -n 's/.*"size_human" *: *"\([^"]*\)".*/\1/p' <<<"$MANIFEST" | head -1)
[[ -n $VER && -n $URL && -n $SHA ]] || die "Malformed manifest"
ok "omarchy-parallels v$VER (${SIZE:-a few GB} download)"
confirm "Download and install v$VER into $DEST?" || die "Cancelled."

# ---------- download (resumable) ----------
step "Downloading image"
mkdir -p "$DEST"
ZIP="$DEST/omarchy-parallels-v$VER.zip"
curl -fL -C - --progress-bar -o "$ZIP" "$URL" || die "Download failed (re-run to resume)."
ok "downloaded"

step "Verifying integrity"
GOT=$(shasum -a 256 "$ZIP" | awk '{print $1}')
[[ $GOT == "$SHA" ]] || die "sha256 mismatch — corrupted or tampered download. Delete $ZIP and retry."
ok "sha256 verified"
if [[ -n $PUBKEY ]] && command -v minisign >/dev/null 2>&1; then
  curl -fsSL -o "$ZIP.minisig" "$URL.minisig" 2>/dev/null &&
    { minisign -Vm "$ZIP" -P "$PUBKEY" >/dev/null 2>&1 && ok "signature verified" || die "SIGNATURE INVALID — do not use this image."; }
else
  note "signature check skipped ($([[ -z $PUBKEY ]] && echo 'no key configured' || echo 'minisign not installed — brew install minisign'))"
fi

# ---------- unpack + import ----------
step "Unpacking"
[[ -d "$DEST/Omarchy.pvm" ]] && die "$DEST/Omarchy.pvm already exists — remove or rename it first."
unzip -q "$ZIP" -d "$DEST"
ok "unpacked to $DEST/Omarchy.pvm"
rm -f "$ZIP" "$ZIP.minisig"

step "Importing into Parallels"
note "If Parallels asks 'Copied or Moved?', choose Copied."
open "$DEST/Omarchy.pvm"
PRLCTL="/usr/local/bin/prlctl"
for _ in $(seq 1 24); do
  "$PRLCTL" list -a --no-header 2>/dev/null | grep -q Omarchy && break; sleep 5
done
"$PRLCTL" list -a --no-header 2>/dev/null | grep -q Omarchy || die "VM never registered in Parallels."
ok "VM registered"

# ---------- post-import (HiDPI + notes) ----------
QUIET_FLAG=(); [[ $YOLO -eq 1 ]] && QUIET_FLAG=(--quiet)
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [[ -n $SELF_DIR && -x "$SELF_DIR/host/post-import.sh" ]]; then
  "$SELF_DIR/host/post-import.sh" "${QUIET_FLAG[@]}"
else
  curl -fsSL "${MANIFEST_URL%/latest.json}/post-import.sh" | bash -s -- "${QUIET_FLAG[@]}" ||
    note "post-import step unavailable — set HiDPI by hand: View → Retina Resolution → More Space"
fi

# ---------- boot ----------
step "Starting Omarchy"
open "$DEST/Omarchy.pvm"
printf '\n%s✓ Done.%s ' "$GREEN" "$N"
if [[ $YOLO -eq 1 ]]; then
  printf 'The VM is booting. First boot applies defaults after a 10s countdown:\n'
  printf '  user %somarchy%s, a generated password shown on screen (change it at first login).\n' "$B" "$N"
else
  printf 'The VM is booting — answer the three first-boot questions in its window.\n'
fi
printf '%sTip:%s Cmd+Space is taken by Spotlight; use Cmd+Option+O for the Omarchy menu,\n' "$B" "$N"
printf 'or free it up in Parallels: Preferences → Shortcuts.\n'
