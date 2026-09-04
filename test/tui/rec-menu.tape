# The interactive path: arrow-key mode menu, then the custom options toggle.
Output docs/assets/install-menu.gif
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
Type "curl -fsSL https://omarchy-apple-silicon.zilnik.me/install.sh | bash"
Sleep 500ms
Hide
Ctrl+C
Type "./test/tui/harness.sh --reuse --rate 94371840"
Show
Enter
Sleep 3s
Screenshot build/out/rec-m1.png
Down
Sleep 1200ms
Screenshot build/out/rec-m2.png
Enter
Sleep 1500ms
Enter
Sleep 1200ms
Screenshot build/out/rec-m3.png
Down
Sleep 600ms
Down
Sleep 600ms
Space
Sleep 900ms
Screenshot build/out/rec-m4.png
Enter
Sleep 12s
Screenshot build/out/rec-m5.png
Sleep 8s
Screenshot build/out/rec-m6.png
Sleep 2s
