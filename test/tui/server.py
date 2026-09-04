#!/usr/bin/env python3
"""Fake release server for the installer harness.

Serves latest.json plus a throttled, range-capable zip so the download bar, the resume path
and the stall watchdog can all be exercised without touching the real CDN.

  --rate BYTES_PER_SEC   throttle the zip (default 8 MB/s)
  --stall-at PERCENT     stop sending at this point and hold the socket open (stall watchdog)
  --die-at PERCENT       drop the connection at this point (retry + resume path)
"""
import argparse, hashlib, http.server, json, os, socketserver, sys, threading, time

ap = argparse.ArgumentParser()
ap.add_argument("--root", required=True)
ap.add_argument("--zip", required=True)
ap.add_argument("--port", type=int, default=0)
ap.add_argument("--rate", type=int, default=8 << 20)
ap.add_argument("--stall-at", type=int, default=-1)
ap.add_argument("--die-at", type=int, default=-1)
ap.add_argument("--version", default="0.9.9")
ap.add_argument("--bad-url", default="",
                help="advertise this download URL instead of the real one, to exercise the "
                     "manifest-hardening checks (e.g. '-K/etc/passwd' for curl option injection)")
ap.add_argument("--bad-sha", action="store_true",
                help="advertise a checksum that will not match, to exercise the corruption path")
args = ap.parse_args()

ZIP = os.path.abspath(args.zip)
SIZE = os.path.getsize(ZIP)
SHA = hashlib.sha256(open(ZIP, "rb").read()).hexdigest()
if args.bad_sha:
    SHA = "0" * 64
served_once = {"died": False}


def human(n):
    return f"{n/(1<<30):.2f}G" if n >= 1 << 30 else f"{n/(1<<20):.0f}M"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_HEAD(self):
        self.do_GET(head=True)

    def do_GET(self, head=False):
        if self.path.endswith("latest.json"):
            body = json.dumps({
                "version": args.version,
                "url": args.bad_url or f"http://{self.headers['Host']}/image.zip",
                "sha256": SHA,
                "size": SIZE,
                "size_human": human(SIZE),
                "omarchy_version": "4.1.0",
                "built": "2026-09-03T00:00:00Z",
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if not head:
                self.wfile.write(body)
            return

        if self.path.endswith(".minisig"):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        if not self.path.endswith("image.zip"):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        start = 0
        rng = self.headers.get("Range")
        if rng and rng.startswith("bytes="):
            try:
                start = int(rng.split("=")[1].split("-")[0])
            except ValueError:
                start = 0
        remaining = SIZE - start
        self.send_response(206 if start else 200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(remaining))
        if start:
            self.send_header("Content-Range", f"bytes {start}-{SIZE-1}/{SIZE}")
        self.end_headers()
        if head:
            return

        chunk = max(args.rate // 20, 8192)
        sent = 0
        with open(ZIP, "rb") as fh:
            fh.seek(start)
            while sent < remaining:
                pct = (start + sent) * 100 // SIZE
                if args.stall_at >= 0 and pct >= args.stall_at:
                    time.sleep(600)          # hold the socket open and send nothing
                    return
                if args.die_at >= 0 and pct >= args.die_at and not served_once["died"]:
                    served_once["died"] = True
                    self.wfile.flush()
                    self.connection.close()  # abrupt drop; curl must retry and resume
                    return
                buf = fh.read(min(chunk, remaining - sent))
                if not buf:
                    break
                try:
                    self.wfile.write(buf)
                except (BrokenPipeError, ConnectionResetError):
                    return
                sent += len(buf)
                time.sleep(len(buf) / args.rate)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


srv = Server(("127.0.0.1", args.port), Handler)
print(srv.server_address[1], flush=True)
srv.serve_forever()
