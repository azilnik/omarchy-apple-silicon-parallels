#!/bin/bash
# test/tui/harness.sh — run install.sh end to end against a fake release server.
#
# Nothing here touches Parallels, the network, or ~/Parallels: prlctl/open/defaults are
# stubbed, the manifest and image come from a local throttled HTTP server, and the install
# goes into a scratch directory that is wiped on every run.
#
#   test/tui/harness.sh [--rate BYTES] [--stall-at PCT] [--die-at PCT] [--size MB] [-- <install args>]

set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${OMARCHY_HARNESS_WORK:-${TMPDIR:-/tmp}/omarchy-harness}"
RATE=$((12 << 20)); STALL=-1; DIE=-1; MB=48; BADSHA=(); REUSE=0; BADURL=()
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --rate) RATE=$2; shift ;;
    --stall-at) STALL=$2; shift ;;
    --die-at) DIE=$2; shift ;;
    --size) MB=$2; shift ;;
    --bad-sha) BADSHA=(--bad-sha) ;;
    --bad-url) BADURL=("--bad-url=$2"); shift ;;
    --reuse) REUSE=1 ;;   # keep the generated image between runs (recordings)
    --) shift; ARGS=("$@"); break ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

if [ "$REUSE" -eq 1 ] && [ -f "$WORK/image.zip" ]; then
  rm -rf "$WORK/dest" "$WORK/state"; mkdir -p "$WORK/dest" "$WORK/state"
else
  rm -rf "$WORK"; mkdir -p "$WORK/fixture/Omarchy.pvm" "$WORK/dest" "$WORK/state"
  # Incompressible payload, so the zip is roughly the size of what it unpacks to and both
  # progress bars have real work to show.
  dd if=/dev/urandom of="$WORK/fixture/Omarchy.pvm/Omarchy-0.hdd" bs=1m count="$MB" 2>/dev/null
  printf '<ParallelsVirtualMachine><VmUuid>{6de04848-268b-4d4d-b642-0cf4f1484b67}</VmUuid></ParallelsVirtualMachine>\n' \
    > "$WORK/fixture/Omarchy.pvm/config.pvs"
  ( cd "$WORK/fixture" && zip -qry "$WORK/image.zip" Omarchy.pvm )
fi

python3 "$REPO/test/tui/server.py" --root "$WORK" --zip "$WORK/image.zip" \
  --rate "$RATE" --stall-at "$STALL" --die-at "$DIE" "${BADSHA[@]+"${BADSHA[@]}"}" "${BADURL[@]+"${BADURL[@]}"}" \
  > "$WORK/port" 2>"$WORK/server.log" &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
PORT=$(cat "$WORK/port")
[ -n "$PORT" ] || { echo "harness: server did not start" >&2; cat "$WORK/server.log" >&2; exit 1; }

export PATH="$REPO/test/tui/stubs:$PATH"
export OMARCHY_PARALLELS_MANIFEST="http://127.0.0.1:$PORT/latest.json"
export OMARCHY_PARALLELS_DEST="$WORK/dest"
export OMARCHY_PARALLELS_PUBKEY=""
export OMARCHY_PRLCTL="$REPO/test/tui/stubs/prlctl"
export OMARCHY_STUB_STATE="$WORK/state"

# Run a snapshot, not the file in the tree. Bash reads a script incrementally by byte offset,
# so editing install.sh while a run is in flight makes the running shell resume at a stale
# position and fail with nonsense ("command not found" on a fragment of a word). That is very
# easy to do by accident while iterating, and very confusing to debug.
SNAP="$WORK/install-snapshot.sh"
cp "$REPO/install.sh" "$SNAP"
bash "$SNAP" ${ARGS[@]+"${ARGS[@]}"}
