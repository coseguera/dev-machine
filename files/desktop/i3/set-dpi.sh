#!/bin/sh
# set-dpi.sh - dev-machine desktop: keep i3/bar/font readable on any display.
# i3 + i3bar fonts are pango, so they scale with Xft.dpi. X often reports a flat
# 96 dpi even on a 4K panel (tiny UI) or omits the physical size. Compute the real
# dpi from the connected display's pixel width and physical mm, clamp + snap it to
# a crisp step, and set Xft.dpi. Re-run from i3 exec_always so it tracks hotplug.
# Single source of truth: the configs keep one font size; dpi does the scaling.

# Pull the active mode's pixel width and the panel's physical width (mm) from the
# primary (or first) connected output, e.g. "3840x2160+0+0 ... 608mm x 345mm".
read px mm <<EOF
$(xrandr 2>/dev/null | awk '
  / connected primary / { p=$0 }
  / connected / && q=="" { q=$0 }
  END {
    line = (p != "" ? p : q)
    w=0; m=0
    if (match(line, /[0-9]+x[0-9]+\+/)) { split(substr(line,RSTART,RLENGTH-1),a,"x"); w=a[1] }
    if (match(line, /[0-9]+mm x/))      { m=substr(line,RSTART,RLENGTH-3)+0 }
    print w, m
  }')
EOF

# Fallback to 96 if we could not read a width or a sane physical size.
if [ -z "$px" ] || [ "$px" -lt 1 ] 2>/dev/null || [ -z "$mm" ] || [ "$mm" -lt 50 ] 2>/dev/null; then
  dpi=96
else
  # dpi = px / (mm / 25.4)
  dpi=$(( px * 254 / (mm * 10) ))
fi

# Clamp to a sane range, then snap to a crisp step for sharp rendering.
[ "$dpi" -lt 96 ] && dpi=96
[ "$dpi" -gt 192 ] && dpi=192
for step in 96 120 144 168 192; do
  if [ "$dpi" -le "$step" ]; then dpi=$step; break; fi
done

printf 'Xft.dpi: %s\n' "$dpi" | xrdb -merge 2>/dev/null

# Pango fonts only pick up the new dpi on i3 (re)start. Restart once when the dpi
# actually changed, using a cache marker to avoid an exec_always restart loop.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/dev-machine-dpi"
prev=""; [ -f "$cache" ] && prev="$(cat "$cache" 2>/dev/null)"
if [ "$dpi" != "$prev" ]; then
  mkdir -p "$(dirname "$cache")"; echo "$dpi" > "$cache"
  i3-msg restart >/dev/null 2>&1 || true
fi

