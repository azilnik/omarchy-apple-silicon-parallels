#!/bin/bash
# packages/build-all.sh — build the aarch64 packages Omarchy ships x86_64-only, on an
# Arch Linux ARM machine (the builder VM). Produces .pkg.tar.* under each package dir and,
# with --repo, a local pacman repo the image can install from.
#
# Run ON the guest as a normal user with sudo (base-devel + git required):
#   ./build-all.sh [--repo DIR] [pkgname ...]
#
# With no package names, builds them all. Each build is independent — a failure is reported
# and skipped, not fatal, so one bad network fetch doesn't sink the batch.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=""
PKGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) PKGS+=("$1"); shift ;;
  esac
done
[[ ${#PKGS[@]} -eq 0 ]] && PKGS=(ttfx tobi-try hyprland-preview-share-picker omacalc omawrite omacut obsidian-arm-bin)

command -v makepkg >/dev/null || { echo "run this on an Arch Linux ARM machine (makepkg missing)"; exit 1; }

built=(); failed=()
for p in "${PKGS[@]}"; do
  d="$HERE/$p"
  [[ -f "$d/PKGBUILD" ]] || { echo "!! no PKGBUILD for $p"; failed+=("$p"); continue; }
  echo "==> building $p"
  if ( cd "$d" && makepkg -sf --noconfirm --needed ); then
    built+=("$p")
    [[ -n $REPO ]] && { mkdir -p "$REPO"; cp "$d"/*.pkg.tar.* "$REPO/"; }
  else
    echo "!! $p failed"; failed+=("$p")
  fi
done

if [[ -n $REPO ]]; then
  echo "==> updating local repo db in $REPO"
  ( cd "$REPO" && repo-add -q omarchy-arm-extra.db.tar.zst ./*.pkg.tar.* )
fi

echo
echo "built:  ${built[*]:-none}"
echo "failed: ${failed[*]:-none}"
[[ ${#failed[@]} -eq 0 ]]
