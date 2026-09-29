#!/bin/bash
# Visual smoke test for lib/tui.sh — the task list, progress bar and completion morph.
set -uo pipefail
. "$(dirname "$0")/../../lib/tui.sh"
tui_init
tui_header "Omarchy for Parallels" "Arch + Hyprland on Apple Silicon"

tui_task_add pre   "Checking this Mac"
tui_task_add rel   "Release"
tui_task_add dl    "Downloading image"
tui_task_add ver   "Verifying"
tui_task_add unz   "Unpacking"
tui_task_add imp   "Importing into Parallels"
tui_task_add boot  "Starting Omarchy"

tui_start pre; for i in 1 2 3 4 5 6; do tui_tick; done
tui_ok pre "Apple Silicon · Parallels Desktop · 412 GB free"
tui_start rel; for i in 1 2 3; do tui_tick; done
tui_ok rel "v0.3.1 · 3.71 GB"

tui_start dl
total=3985729536
i=0
while [ $i -le 100 ]; do
  done_b=$(( total * i / 100 ))
  tui_human_bytes hb "$done_b"; tui_human_bytes ht "$total"
  eta=$(( (100 - i) / 3 )); tui_human_time he "$eta"
  tui_progress dl "$hb of $ht · 44.1 MB/s · $he left" "$i/100"
  _tui_sleep_frame
  i=$((i + 4))
done
tui_ok dl "3.71 GB in 1m 28s"
tui_start ver "sha256"; for i in 1 2 3 4 5 6 7 8; do tui_tick; done
tui_ok ver "sha256 + minisign signature"
tui_start unz
i=0
while [ $i -le 100 ]; do
  tui_progress unz "9.4 GB of 11.2 GB unpacked" "$i/100"; _tui_sleep_frame; i=$((i + 5))
done
tui_ok unz "Omarchy.pvm · 11.2 GB"
tui_start imp "waiting for Parallels to register the VM"
for i in $(seq 1 14); do tui_tick; done
tui_ok imp "registered"
tui_start boot; for i in 1 2 3 4 5; do tui_tick; done
tui_ok boot "booting"
tui_commit
tui_panel "$TUI_OK" "Done — the VM is booting." \
  "login omarchy / omarchy — run passwd to change it" \
  "Super is Cmd. Menu: Cmd+Space. Terminal: Cmd+Ctrl+Return."
