#!/usr/bin/env python3
"""Replay a cast recorded by record-cast.py, optionally compressed in time.

  play-cast.py hero.cast --speed 25 --max-gap 0.4

--speed divides every delay; --max-gap caps any single pause so one slow moment cannot
dominate the result. Nothing about the bytes changes — the figures on screen stay exactly
what the real run produced.
"""
import argparse, base64, json, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("cast")
ap.add_argument("--speed", type=float, default=1.0)
ap.add_argument("--max-gap", type=float, default=1.0)
ap.add_argument("--start", type=float, default=0.0, help="skip everything before this timestamp")
ap.add_argument("--fps", type=float, default=0.0,
                help="coalesce output into this many writes per second (0 = one per chunk)")
ap.add_argument("--no-clear", action="store_true", help="do not clear the screen first")
ap.add_argument("--write", help="write the (batched) stream out as a cast instead of playing it")
ap.add_argument("--plan", help="segments as start-end@speed, comma separated, e.g. "
                               "'0-14@1,14-150@250,150-415@1'. Segments play in order and the "
                               "byte stream is never cut, so a fast segment can be hidden by "
                               "the recorder while the terminal stays in a correct state.")
args = ap.parse_args()

events = []
with open(args.cast) as fh:
    for line in fh:
        line = line.strip()
        if line:
            e = json.loads(line)
            events.append((e["t"], base64.b64decode(e["d"])))

events = [(t, d) for t, d in events if t >= args.start]

# Pacing. The naive approach — sleep between every chunk — spends more time in sleep overhead
# than in the delays themselves once the speed-up is large: five thousand chunks at a
# millisecond of granularity each is half a minute of pure overhead, and the replay falls
# behind. So coalesce everything that lands in the same output time slice and emit it as one
# write with a single sleep.
#
# Nothing is dropped. An earlier version thinned frames instead and corrupted the display:
# each frame starts by moving the cursor up by the height of the frame before it, so removing
# a frame of a different height makes every later frame draw in the wrong place. Batching
# leaves the byte stream intact, so the terminal ends each slice in exactly the state the real
# run produced.
slice_s = 1.0 / args.fps if args.fps > 0 else 0.0
batches = []
if slice_s > 0:
    base = events[0][0]
    cur_bucket, cur_bytes, cur_t = None, [], None
    for t, d in events:
        bucket = int((t - base) / (slice_s * args.speed))
        if bucket != cur_bucket and cur_bytes:
            batches.append((cur_t, b"".join(cur_bytes)))
            cur_bytes = []
        if not cur_bytes:
            cur_t = t
        cur_bucket = bucket
        cur_bytes.append(d)
    if cur_bytes:
        batches.append((cur_t, b"".join(cur_bytes)))
else:
    batches = events
events = batches

if args.write:
    import base64 as _b64
    with open(args.write, "w") as fh:
        for t, d in events:
            fh.write(json.dumps({"t": t, "d": _b64.b64encode(d).decode()}) + "\n")
    sys.exit(0)

# A plan varies the speed over the run instead of compressing it uniformly. That matters for
# one reason: a spinner. Time-compressed, it cycles many times per recorded frame and aliases
# into noise, and no uniform speed avoids that — a spinner only reads as a spinner in real
# time. So the parts worth watching play at 1x and the long monotonous middles are raced
# through for the recorder to hide. The stream itself is never cut, so the terminal is always
# in a state the real run actually produced.
plan = []
if args.plan:
    for part in args.plan.split(","):
        rng, _, sp = part.partition("@")
        a, _, b = rng.partition("-")
        plan.append((float(a), float(b), float(sp or 1)))

def speed_at(t):
    for a, b, sp in plan:
        if a <= t < b:
            return sp
    return plan[-1][2] if plan else args.speed

w = sys.stdout.buffer
if not args.no_clear:
    w.write(b"\033[2J\033[3J\033[H")   # start on a clean screen, not under a shell prompt
    w.flush()
prev = events[0][0] if events else 0.0
marks, seg_start, seg_i = [], time.time(), 0
for t, d in events:
    sp = speed_at(t) if plan else args.speed
    if plan:
        while seg_i < len(plan) and t >= plan[seg_i][1]:
            marks.append((plan[seg_i], round(time.time() - seg_start, 2)))
            seg_start = time.time()
            seg_i += 1
    gap = min((t - prev) / sp, args.max_gap)
    if gap > 0:
        time.sleep(gap)
    w.write(d)
    w.flush()
    prev = t
if plan:
    marks.append((plan[min(seg_i, len(plan) - 1)], round(time.time() - seg_start, 2)))
    for (a, b, sp), took in marks:
        print(f"segment {a:>6.1f}-{b:<6.1f} @{sp:g}x  ->  {took}s", file=sys.stderr)
