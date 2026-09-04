#!/bin/bash
# test/tui/make-end-to-end.sh — join the installer recording and the VM boot into one GIF.
#
# Two halves, captured very differently:
#
#   installer  vhs test/tui/rec-hero.tape  (replays a real install; see record-cast.py)
#   VM         frames from `prlctl capture`, which reads the guest framebuffer directly
#
# The VM half is captured that way on purpose. Screen-recording the Parallels window gives a
# much higher frame rate, but it only works while the Mac is unlocked and shows whatever else
# is on screen; `prlctl capture` works headlessly and sees nothing but the guest. It tops out
# around 2 fps, which is fine here — the boot is mostly static screens, and the one animation
# that matters (the first-boot countdown) still gets two or three frames a second.
#
#   test/tui/make-end-to-end.sh /tmp/vmframes docs/assets/end-to-end.gif
#
# Capture the VM half first with something like:
#   while :; do prlctl capture Omarchy --file /tmp/vmframes/f$(date +%s%N).png; done

set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FRAMES=${1:?usage: make-end-to-end.sh <vm-frame-dir> <out.gif>}
OUT=${2:?usage: make-end-to-end.sh <vm-frame-dir> <out.gif>}
INSTALLER="$REPO/build/out/installer.mp4"
BG=0x1e1e2e
W=1080; H=720

[[ -f $INSTALLER ]] || { echo "missing $INSTALLER — run: vhs test/tui/rec-hero.tape" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Frame names carry their capture time, so the timeline can be re-cut without re-capturing.
python3 - "$FRAMES" "$tmp/vm.concat" <<'PY'
import glob, os, sys
frames, out = sys.argv[1], sys.argv[2]
fs = sorted(glob.glob(os.path.join(frames, '*.png')))
def t(f): return float(os.path.basename(f).split('-')[1][:-4])
def pick(a, b, step=1): return [f for f in fs if a <= t(f) <= b][::step]
plan  = [(f, 0.16) for f in pick(2, 15, 3)]      # kernel boot, sampled — nothing to dwell on
plan += [(f, 0.13) for f in pick(15.5, 31, 1)]   # the first-boot countdown, every frame
plan += [(f, 0.14) for f in pick(31, 43, 3)]     # handover to the desktop
plan += [(f, 0.16) for f in pick(43, 52, 1)]     # desktop paints, the welcome opens
plan += [(plan[-1][0], 2.0)]                     # hold on the welcome
with open(out, 'w') as fh:
    for f, d in plan:
        fh.write(f"file '{f}'\nduration {d}\n")
    fh.write(f"file '{plan[-1][0]}'\n")
print(f"vm half: {len(plan)} frames, {sum(d for _, d in plan):.1f}s", file=sys.stderr)
PY

ffmpeg -v error -f concat -safe 0 -i "$tmp/vm.concat" -fps_mode vfr -pix_fmt yuv420p \
  -c:v libx264 -preset slow -crf 20 -y "$tmp/vm.mp4"

# The terminal is wide and short, the guest is 4:3. Crop the installer to its content and
# centre it, so the first half does not read as a strip pinned to the top of an empty frame.
ffmpeg -v error -i "$INSTALLER" \
  -vf "crop=$W:500:0:0,pad=$W:$H:0:(($H-500)/2):$BG,fps=24,format=yuv420p" \
  -c:v libx264 -crf 20 -y "$tmp/a.mp4"
ffmpeg -v error -i "$tmp/vm.mp4" \
  -vf "scale=-2:$H,pad=$W:$H:(ow-iw)/2:0:$BG,fps=24,format=yuv420p" \
  -c:v libx264 -crf 20 -y "$tmp/b.mp4"

printf "file '%s'\nfile '%s'\n" "$tmp/a.mp4" "$tmp/b.mp4" > "$tmp/join.txt"
ffmpeg -v error -f concat -safe 0 -i "$tmp/join.txt" -c copy -y "$tmp/full.mp4"

ffmpeg -v error -i "$tmp/full.mp4" -vf \
  "fps=16,scale=900:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  -loop 0 -y "$OUT"
printf 'wrote %s (%s, %ss)\n' "$OUT" "$(du -h "$OUT" | cut -f1)" \
  "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$tmp/full.mp4" | cut -d. -f1)"
