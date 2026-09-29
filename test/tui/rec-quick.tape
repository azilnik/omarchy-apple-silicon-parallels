# The quick install, end to end. Uses the local harness (see test/tui/harness.sh) so the
# recording is reproducible and does not pull a real 4.7 GB image.
Output docs/assets/install-quick.gif
Set Shell bash
Set FontSize 15
Set Width 1000
Set Height 420
Set Padding 20
Set Theme "Catppuccin Mocha"
Set Framerate 24
Hide
Type "export OMARCHY_HARNESS_WORK=/tmp/omarchy-rec" Enter
Type "clear" Enter
Show
Sleep 500ms
Type "./test/tui/harness.sh --reuse --rate 62914560 -- --quick"
Sleep 400ms
Enter
Sleep 22s
Screenshot build/out/rec-q1.png
Sleep 12s
Screenshot build/out/rec-q2.png
Sleep 3s
