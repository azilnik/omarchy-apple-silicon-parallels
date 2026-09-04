#!/usr/bin/env python3
"""Render a cast (record-cast.py) into the final terminal screen, as a terminal would.

The point is to assert on what a user would actually SEE, rather than on the bytes we sent.
It caught a real bug: text printed after the live region closed — the completion panel — did
not erase to the end of the line, so a short line left the tail of an older frame showing
through it. That is invisible in the byte stream and invisible in every plain-mode test.

  render-screen.py hero.cast [--cols 110] [--rows 40]
"""
import argparse, base64, json, re, sys

ap = argparse.ArgumentParser()
ap.add_argument("cast")
ap.add_argument("--cols", type=int, default=110)
ap.add_argument("--rows", type=int, default=40)
args = ap.parse_args()

data = b""
with open(args.cast) as fh:
    for line in fh:
        line = line.strip()
        if line:
            data += base64.b64decode(json.loads(line)["d"])

rows, cols = args.rows, args.cols
screen = [[" "] * cols for _ in range(rows)]
cy = cx = 0
text = data.decode("utf-8", "replace")
csi = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")
i = 0
while i < len(text):
    ch = text[i]
    if ch == "\x1b":
        m = csi.match(text, i)
        if m:
            p, cmd = m.group(1), m.group(2)
            n = int(p) if p.isdigit() else 1
            if cmd == "A":
                cy = max(0, cy - n)
            elif cmd == "B":
                cy = min(rows - 1, cy + n)
            elif cmd == "K":
                for x in range(cx, cols):
                    screen[cy][x] = " "
            elif cmd == "J":
                for yy in range(rows):
                    for xx in range(cols):
                        screen[yy][xx] = " "
                if p == "2":
                    cy = cx = 0
            elif cmd == "H":
                cy = cx = 0
            i = m.end()
            continue
        i += 1
        continue
    if ch == "\n":
        cy = min(rows - 1, cy + 1)
    elif ch == "\r":
        cx = 0
    else:
        if cx < cols:
            screen[cy][cx] = ch
            cx += 1
    i += 1

out = ["".join(r).rstrip() for r in screen]
while out and not out[-1]:
    out.pop()
sys.stdout.write("\n".join(out) + "\n")
