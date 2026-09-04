#!/usr/bin/env python3
"""Compose a demo video: a framed window on a backdrop, with keyframed camera moves.

Reelkit does this properly for web apps — Playwright shoots the app flat and high-resolution,
Remotion composes the camera on top, so a push-in only ever downsamples and stays sharp. Its
capture stage cannot drive a terminal or a VM, so this reproduces the same idea for the two
sources this project actually has: a terminal recording and frames of a guest framebuffer.

The rule that makes it look right is the same one: shoot far above the composition size, and
let the camera only ever crop and shrink. Never upscale.

  compose-demo.py --source installer-hi.mp4 --out out.mp4 --mode window --shots shots.json
"""
import argparse, json, math, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("--source", required=True)
ap.add_argument("--backdrop")
ap.add_argument("--out", required=True)
ap.add_argument("--shots", required=True, help="JSON list of {t, w, cx, cy} camera keyframes")
ap.add_argument("--mode", choices=["window", "full"], default="window")
ap.add_argument("--scene", default="3200x2000")
ap.add_argument("--outsize", default="1200x750")
ap.add_argument("--fps", type=float, default=24)
args = ap.parse_args()

SW, SH = (int(v) for v in args.scene.split("x"))
OW, OH = (int(v) for v in args.outsize.split("x"))
shots = json.load(open(args.shots))

probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                        "-show_entries", "stream=width,height", "-of", "csv=p=0",
                        args.source], capture_output=True, text=True).stdout.strip()
FW, FH = (int(v) for v in probe.split(",")[:2])


def smoothstep(a, b, u):
    u = max(0.0, min(1.0, u))
    return a + (b - a) * (u * u * (3 - 2 * u))


def camera(t):
    """Interpolate the camera between keyframes; hold before the first and after the last."""
    if t <= shots[0]["t"]:
        k = shots[0]
        return k["w"], k["cx"], k["cy"]
    for a, b in zip(shots, shots[1:]):
        if a["t"] <= t <= b["t"]:
            u = (t - a["t"]) / max(1e-6, b["t"] - a["t"])
            return (smoothstep(a["w"], b["w"], u),
                    smoothstep(a["cx"], b["cx"], u),
                    smoothstep(a["cy"], b["cy"], u))
    k = shots[-1]
    return k["w"], k["cx"], k["cy"]


# ---- the static parts of the scene, built once -------------------------------------
scene_base = Image.new("RGB", (SW, SH), (16, 16, 26))
if args.backdrop:
    bd = Image.open(args.backdrop).convert("RGB")
    scale = max(SW / bd.width, SH / bd.height)
    bd = bd.resize((math.ceil(bd.width * scale), math.ceil(bd.height * scale)), Image.LANCZOS)
    bd = bd.crop((0, 0, SW, SH))
    # Dimmed hard and blurred flat. Two reasons: the window has to stay the subject, and a
    # sharp photographic gradient is expensive in a 256-colour GIF — flattening it is worth
    # several megabytes.
    bd = bd.filter(ImageFilter.GaussianBlur(30))
    scene_base = Image.blend(bd, Image.new("RGB", (SW, SH), (9, 9, 16)), 0.72)

if args.mode == "window":
    BAR = 56                      # a title bar, so it reads as a window rather than a crop
    WW, WH = FW, FH + BAR
    WX, WY = (SW - WW) // 2, (SH - WH) // 2
    RADIUS = 26

    mask = Image.new("L", (WW, WH), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, WW - 1, WH - 1), RADIUS, fill=255)

    # A soft drop shadow, drawn once into the backdrop.
    sh = Image.new("L", (SW, SH), 0)
    ImageDraw.Draw(sh).rounded_rectangle((WX, WY + 16, WX + WW, WY + WH + 30), RADIUS, fill=190)
    sh = sh.filter(ImageFilter.GaussianBlur(34))
    scene_base = Image.composite(Image.new("RGB", (SW, SH), (0, 0, 0)), scene_base, sh)

    chrome = Image.new("RGB", (WW, WH), (30, 30, 46))
    d = ImageDraw.Draw(chrome)
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse((26 + i * 34, BAR // 2 - 9, 44 + i * 34, BAR // 2 + 9), fill=c)
else:
    WW = WH = WX = WY = BAR = 0
    mask = chrome = None

# ---- stream frames through ---------------------------------------------------------
rd = subprocess.Popen(["ffmpeg", "-v", "error", "-i", args.source,
                       "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                      stdout=subprocess.PIPE)
wr = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                       "-s", f"{OW}x{OH}", "-r", str(args.fps), "-i", "-",
                       "-c:v", "libx264", "-crf", "18", "-preset", "slow",
                       "-pix_fmt", "yuv420p", args.out], stdin=subprocess.PIPE)

n = 0
frame_bytes = FW * FH * 3
while True:
    raw = rd.stdout.read(frame_bytes)
    if len(raw) < frame_bytes:
        break
    src = Image.frombytes("RGB", (FW, FH), raw)
    scene = scene_base.copy()
    if args.mode == "window":
        win = chrome.copy()
        win.paste(src, (0, BAR))
        scene.paste(win, (WX, WY), mask)
    else:
        scale = min(SW / FW, SH / FH)
        w, h = int(FW * scale), int(FH * scale)
        scene.paste(src.resize((w, h), Image.LANCZOS), ((SW - w) // 2, (SH - h) // 2))

    cw, cx, cy = camera(n / args.fps)
    ch = cw * OH / OW
    x0 = max(0, min(SW - cw, cx - cw / 2))
    y0 = max(0, min(SH - ch, cy - ch / 2))
    out = scene.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((OW, OH), Image.LANCZOS)
    wr.stdin.write(out.tobytes())
    n += 1

wr.stdin.close()
rd.wait(); wr.wait()
print(f"composed {n} frames -> {args.out}", file=sys.stderr)
