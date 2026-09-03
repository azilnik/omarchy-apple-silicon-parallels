-- ── BEGIN omarchy-parallels cursor ──
-- Parallels' virtual GPU exposes a hardware cursor plane, and the host draws its own pointer
-- over it — so the guest shows two cursors, most noticeably in XWayland / Electron apps (Zoom,
-- etc.) that push a cursor onto that plane. Rendering the cursor in software leaves exactly one
-- pointer. (Omarchy uses this same lever for nouveau; here it's for the Parallels virtual GPU.)
-- If a future Parallels/Hyprland release ever inverts this, flip the boolean below.
hl.config({ cursor = { no_hardware_cursors = true } })
-- ── END omarchy-parallels cursor ──
