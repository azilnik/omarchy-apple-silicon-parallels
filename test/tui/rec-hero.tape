# The README hero, replayed from a recording of a real install of v0.1.0.
#
# Every figure on screen is one that run produced — see test/tui/record-cast.py. The real
# install takes ten minutes, so the parts worth watching play at 1x and the long monotonous
# middles are raced through at 500x while the camera looks away.
#
# Uniform time-compression was tried first and looked wrong for one specific reason: a spinner.
# Sped up, it cycles many times per recorded frame and aliases into noise, and no single speed
# avoids that — a spinner only reads as a spinner in real time. The progress bars were fine
# either way; it was always the spinner.
#
#   python3 test/tui/record-cast.py --out /tmp/hero.cast --cols 100 --rows 30 -- bash install.sh --quick
#   vhs test/tui/rec-hero.tape
Output docs/assets/install-quick.gif
Output build/out/installer.mp4
Set Shell bash
Set FontSize 15
Set Width 1080
Set Height 560
Set Padding 20
Set Theme "Catppuccin Mocha"
Set Framerate 24

Hide
Type "clear" Enter
Type "python3 test/tui/play-cast.py /tmp/hero.cast --fps 120 --max-gap 0.12 --plan '0-3@1,3-165@500,165-169@1,169-197@100,197-200@1,200-589@500,589-593@1,593-596@8,596-600@1' 2>/dev/null"
Enter
Sleep 400ms

# Hide/Show windows are timed against the plan's segment durations, which play-cast.py prints
# to stderr. Re-tune them together if the plan changes.
Show
Sleep 2800ms
Hide
Sleep 980ms
Show
Sleep 4050ms
Hide
Sleep 260ms
Show
Sleep 1050ms
Hide
Sleep 1220ms
Show
Sleep 4050ms
Hide
Sleep 430ms
Show
Sleep 4500ms
Screenshot build/out/hero-end.png
Sleep 500ms
