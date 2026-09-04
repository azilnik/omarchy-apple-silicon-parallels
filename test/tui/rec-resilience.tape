# What a bad network and a bad download look like. The fake server drops the connection at
# 45% (--die-at), then a second run is served a checksum that will not match (--bad-sha).
Output docs/assets/install-resilience.gif
Set Shell bash
Set FontSize 15
Set Width 1000
Set Height 440
Set Padding 20
Set Theme "Catppuccin Mocha"
Set Framerate 24
Hide
Type "export OMARCHY_HARNESS_WORK=/tmp/omarchy-rec2" Enter
Type "clear" Enter
Show
Sleep 500ms
Type "./test/tui/harness.sh --size 120 --rate 20971520 --die-at 45 -- --quick"
Enter
Sleep 5s
Screenshot build/out/rec-r1.png
Sleep 14s
Screenshot build/out/rec-r2.png
Sleep 6s
Hide
Type "clear" Enter
Show
Type "./test/tui/harness.sh --size 30 --rate 62914560 --bad-sha -- --quick"
Enter
Sleep 9s
Screenshot build/out/rec-r3.png
Sleep 3s
