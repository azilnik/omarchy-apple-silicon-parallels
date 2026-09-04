#!/bin/bash
# test/tui/make-end-to-end.sh — cut the README hero: the installer, then the VM booting.
#
# Two sources, captured very differently, composed the same way:
#
#   installer  vhs on a high-resolution variant of test/tui/rec-hero.tape, replaying a
#              recording of a real install (see record-cast.py)
#   VM         frames from `prlctl capture`, which reads the guest framebuffer directly
#
# The VM half is captured that way on purpose. Screen-recording the Parallels window gives a
# far better frame rate, but it only works while the Mac is unlocked and it sees whatever else
# is on screen; `prlctl capture` works headlessly and sees nothing but the guest. It tops out
# near 2 fps, which is enough — the boot is mostly static screens, and the one animation that
# matters, the first-boot countdown, still gets two or three frames a second.
#
# Both halves then go through tools/compose-demo.py: framed on the Omarchy wallpaper, with
# keyframed camera moves. That is reelkit's idea — shoot far above the composition size and
# let the camera only ever crop and shrink, never upscale — applied to sources reelkit's own
# capture stage cannot drive (it drives a web app with Playwright).
#
#   test/tui/make-end-to-end.sh /tmp/vmframes docs/assets/end-to-end.gif
#
# Capture the VM half first, while it reboots:
#   T0=$(date +%s)
#   while :; do prlctl capture Omarchy --file "/tmp/vmframes/f$(date +%s%N)-$(( $(date +%s)-T0 )).png"; done

set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FRAMES=${1:?usage: make-end-to-end.sh <vm-frame-dir> <out.gif>}
OUT=${2:?usage: make-end-to-end.sh <vm-frame-dir> <out.gif>}
INSTALLER="$REPO/build/out/installer-hi.mp4"
WALL=${OMARCHY_WALLPAPER:-/tmp/wallpaper.png}
COMPOSE="$REPO/tools/compose-demo.py"
SIZE=1200x750

[[ -f $INSTALLER ]] || { echo "missing $INSTALLER — render the high-res tape first" >&2; exit 1; }
[[ -f $WALL ]] || { echo "missing wallpaper at $WALL (set OMARCHY_WALLPAPER)" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Beats, not coverage. An earlier cut showed everything at a uniform clip and read as a
# slideshow: the countdown had no tension and the payoff went by before you could read a line.
python3 - "$FRAMES" "$tmp/vm.concat" <<'PY'
import glob, os, sys
frames, out = sys.argv[1], sys.argv[2]
fs = sorted(glob.glob(os.path.join(frames, '*.png')))
def t(f): return float(os.path.basename(f).split('-')[1][:-4])
def pick(a, b, step=1): return [f for f in fs if a <= t(f) <= b][::step]
plan  = [(f, 0.15) for f in pick(2, 15, 6)]      # booting: a flash, just enough to place us
plan += [(f, 0.17) for f in pick(15.5, 28, 1)]   # the countdown draining — every frame
plan += [(f, 0.5)  for f in pick(28.3, 30.9, 2)] # "Ready" and the credentials: hold, it reads
plan += [(f, 0.4)  for f in pick(31, 43, 6)]     # dark handover — a beat of anticipation
plan += [(f, 0.3)  for f in pick(44.5, 47.5, 2)] # the welcome draws on a dark desktop
plan += [(f, 1.2)  for f in pick(48.0, 48.6, 1)] # the wallpaper lands — this is the reveal
plan += [(plan[-1][0], 1.0)] * 4                 # hold. Several entries, because the concat
                                                 # demuxer drops the duration on the last one.
with open(out, 'w') as fh:
    for f, d in plan:
        fh.write(f"file '{f}'\nduration {d}\n")
    fh.write(f"file '{plan[-1][0]}'\n")
print(f"vm half: {len(plan)} frames, {sum(d for _, d in plan):.1f}s", file=sys.stderr)
PY

ffmpeg -v error -f concat -safe 0 -i "$tmp/vm.concat" -fps_mode vfr -pix_fmt yuv420p \
  -c:v libx264 -preset slow -crf 18 -y "$tmp/vm.mp4"

python3 "$COMPOSE" --source "$INSTALLER" --backdrop "$WALL" --mode window \
  --shots "$REPO/build/shots/installer.json" --scene 3200x2000 --outsize "$SIZE" --out "$tmp/a.mp4"
python3 "$COMPOSE" --source "$tmp/vm.mp4" --backdrop "$WALL" --mode window \
  --shots "$REPO/build/shots/vm.json" --scene 1600x1000 --outsize "$SIZE" --out "$tmp/b.mp4"

printf "file '%s'\nfile '%s'\n" "$tmp/a.mp4" "$tmp/b.mp4" > "$tmp/join.txt"
ffmpeg -v error -f concat -safe 0 -i "$tmp/join.txt" -c copy -y "$tmp/full.mp4"

ffmpeg -v error -i "$tmp/full.mp4" -vf \
  "fps=12,scale=900:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 -y "$OUT"
cp "$tmp/full.mp4" "$REPO/build/out/end-to-end.mp4"
# A camera move changes every pixel of every frame, so GIF's inter-frame compression has
# nothing to work with and the file is dominated by duration, not by detail. Tuning colours,
# dither and width moves it by a few per cent; shortening the cut is the only real lever.
printf 'wrote %s (%s, %ss)\n' "$OUT" "$(du -h "$OUT" | cut -f1)" \
  "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$tmp/full.mp4" | cut -d. -f1)"
