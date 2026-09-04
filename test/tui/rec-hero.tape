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
Type "python3 test/tui/play-cast.py /tmp/hero.cast --fps 120 --max-gap 0.12 --plan '0-4@1,4-164@500,164-170@1,170-197@100,197-202@1,202-588@500,588-594@1,594-597@10,597-600@1' 2>/dev/null"
Enter
Sleep 400ms

Show
Sleep 4s
Hide
Sleep 650ms
Show
Sleep 6400ms
Hide
Sleep 260ms
Show
Sleep 3s
Hide
Sleep 1430ms
Show
Sleep 6500ms
Hide
Sleep 490ms
Show
Sleep 3s
Screenshot build/out/hero-end.png
Sleep 1500ms
