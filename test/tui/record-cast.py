#!/usr/bin/env python3
"""Record a command's terminal output with timings, so it can be replayed later.

Used to build the README hero from a real install: the download and unpack take about
fifteen minutes, which is far too long for a GIF, but the numbers on screen have to be the
real ones. So capture the real session here and replay it compressed (play-cast.py) rather
than shrinking the work or faking the figures.

  record-cast.py --out hero.cast --cols 100 --rows 30 -- ./install.sh --quick

The format is one JSON object per line: {"t": <seconds since start>, "d": "<base64 bytes>"}.
"""
import argparse, base64, fcntl, json, os, pty, select, signal, struct, sys, termios, time

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--cols", type=int, default=100)
ap.add_argument("--rows", type=int, default=30)
ap.add_argument("cmd", nargs=argparse.REMAINDER)
args = ap.parse_args()
cmd = args.cmd[1:] if args.cmd and args.cmd[0] == "--" else args.cmd
if not cmd:
    sys.exit("record-cast.py: no command given")

pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["COLORTERM"] = "truecolor"
    os.environ.setdefault("LANG", "en_US.UTF-8")
    os.environ["OMARCHY_TUI_BG"] = "dark"      # no OSC 11 partner on a captured pty
    os.execvp(cmd[0], cmd)

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", args.rows, args.cols, 0, 0))
start = time.time()
n = 0
with open(args.out, "w") as out:
    while True:
        try:
            r, _, _ = select.select([fd], [], [], 5)
        except (OSError, InterruptedError):
            break
        if fd not in r:
            if os.waitpid(pid, os.WNOHANG)[0]:
                break
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        out.write(json.dumps({"t": round(time.time() - start, 3),
                              "d": base64.b64encode(data).decode()}) + "\n")
        out.flush()
        n += 1
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
print(f"recorded {n} chunks over {time.time() - start:.0f}s -> {args.out}", file=sys.stderr)
