# The README hero, replayed from a recording of a real install.
#
# The figures on screen (v0.1.0, 4.72 GB, the transfer rates, the 24 GB unpack) are the ones a
# real run produced — see test/tui/record-cast.py. Only the pacing is compressed, because the
# real thing takes about fifteen minutes.
#
#   python3 test/tui/record-cast.py --out /tmp/hero.cast --cols 100 --rows 30 -- bash install.sh --quick
#   vhs test/tui/rec-hero.tape
Output docs/assets/install-quick.gif
Set Shell bash
Set FontSize 15
Set Width 1080
Set Height 560
Set Padding 20
Set Theme "Catppuccin Mocha"
Set Framerate 24
Hide
Type "clear" Enter
Type "python3 test/tui/play-cast.py /tmp/hero.cast --speed 32 --fps 24 --max-gap 0.25"
Enter
Sleep 400ms
Show
Sleep 16s
Screenshot build/out/hero-mid.png
Sleep 12s
Screenshot build/out/hero-end.png
Sleep 2s
