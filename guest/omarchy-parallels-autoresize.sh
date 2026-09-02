#!/bin/bash
# omarchy-parallels-autoresize — follow the resolution Parallels advertises as its window resizes.
#
# Parallels re-advertises the DRM preferred mode when its window changes size. With host
# Retina set to "More Space" the advertised mode is 2x the window's point size (HiDPI);
# on a non-Retina display it is 1x. Hyprland resolves `preferred` once at startup and
# never re-checks, so this loop polls the connector and applies changes.
#
# Scale is derived, not hardcoded: a mode wide enough to be a 2x advertisement gets
# scale 2, anything else scale 1. Override via /etc/omarchy-parallels.conf (SCALE=1|2|auto).
#
# Omarchy 4 parses its config with Lua and rejects `hyprctl keyword`
# ("keyword can't work with non-legacy parsers") — changes must go through `hyprctl eval`.

: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
CONF=/etc/omarchy-parallels.conf
HIDPI_MIN_WIDTH=3200   # narrowest plausible 2x advertisement (2x of a 1600pt-wide window)

last=""
while true; do
  # first connected DRM output; connector naming can change between boots
  conn=""
  for s in /sys/class/drm/card*-*/status; do
    [[ -r $s && $(<"$s") == connected ]] || continue
    conn="${s%/status}"; break
  done
  if [[ -n $conn && -r $conn/modes ]]; then
    cur=$(head -1 "$conn/modes" 2>/dev/null || true)
    name=${conn##*/}; name=${name#card*-}
    if [[ -n $cur && "$cur|$name" != "$last" ]]; then
      width=${cur%x*}
      scale_pref="auto"
      [[ -r $CONF ]] && scale_pref=$(awk -F= '$1=="SCALE"{print $2}' "$CONF" 2>/dev/null | tail -1)
      case "$scale_pref" in
        1|2) scale=$scale_pref ;;
        *)   scale=$(( width >= HIDPI_MIN_WIDTH ? 2 : 1 )) ;;
      esac
      sig=$(ls -1t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1 || true)
      if [[ -n $sig ]]; then
        HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl eval \
          "hl.monitor({ output = \"$name\", mode = \"$cur\", position = \"0x0\", scale = $scale })" \
          >/dev/null 2>&1 && last="$cur|$name"
      fi
    fi
  fi
  sleep 2
done
