# Keyboard shortcuts: Mac ↔ Omarchy

Omarchy drives everything from the **Super** key. On an Apple Silicon Mac in Parallels,
**Super = ⌘ Cmd**, **Alt = ⌥ Option**, **Ctrl = ⌃ Control** — the natural mapping. Most
Cmd shortcuts reach Omarchy unchanged. A few are intercepted before the guest sees them;
this page is the complete picture and how the image handles each.

## What we measured

Tested on Parallels 27 with the VM focused (Cmd pressed as Super):

| macOS combo | Reaches Omarchy? | Why |
|---|---|---|
| Cmd+Space, Cmd+Tab | ✅ yes | the **Linux** keyboard profile forwards macOS *system* shortcuts to the guest |
| Cmd+W, and any two-modifier combo (Cmd+Opt+*, Cmd+Ctrl+*, Cmd+Shift+*) | ✅ yes | not claimed by macOS or Parallels |
| **Cmd+Return** | ❌ no | Parallels **app** shortcut → Enter/Exit Full Screen |
| **Cmd+Q** | ❌ no | Parallels **app** shortcut → Quit (shows a confirm; does **not** silently kill the VM) |
| Cmd+H, Cmd+M, Cmd+Shift+3/4 | ❌ no | macOS app/system shortcuts (Hide, Minimize, Screenshot) |

So the only Omarchy binding that a Mac user actually loses by default is **Super+Return
(open terminal)**, because Parallels grabs Cmd+Return for fullscreen.

## What the image does about it

1. **Assigns the Linux profile** (via `host/post-import.sh`, keyed to the VM's UUID) so
   Cmd+Space opens the Omarchy menu instead of Spotlight — no macOS settings changed.
2. **Ships a Mac-safe terminal shortcut**: `herdr` has no aarch64 build, so its
   `Super+Ctrl+Return` binding is dead on ARM. The image reuses it for the terminal
   (`guest/hypr/parallels-mac.bindings.lua`). **Cmd+Ctrl+Return opens a terminal**, always,
   with zero host configuration.

## If you want the *native* bindings back

Turn off the two Parallels application shortcuts, one time (30 seconds):

**Parallels → Preferences → Shortcuts → Application Shortcuts** — uncheck / clear:
- **Enter Full Screen** (Cmd+Return) → restores Omarchy's **Super+Return = terminal**
- **Quit** (Cmd+Q) → restores Omarchy's **Super+Q = close window** (optional; the Quit
  confirm is a safety net, so leaving it is fine)

Everything else already works: **Cmd+Space** (menu), **Cmd+Opt+Space** (apps), **Cmd+K**
(keybindings cheatsheet), **Cmd+Esc** (system menu), workspace and window bindings.

## Reference: Omarchy essentials on a Mac keyboard

| Do this | Press |
|---|---|
| Open the menu | **Cmd+Space** |
| Open the app launcher | **Cmd+Opt+Space** |
| Open a terminal | **Cmd+Ctrl+Return** (or Cmd+Return after the tweak above) |
| See all keybindings | **Cmd+K** |
| System / power menu | **Cmd+Esc** |
