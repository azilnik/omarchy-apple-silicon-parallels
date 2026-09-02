# Cross-machine verification checklist (~10 minutes)

For verifying a release on a Mac we don't have (especially M4). Report results in an issue
titled `verify: vX.Y.Z on <chip> / <display>`.

1. **Install**: run the README one-liner, choose YOLO. ☐ completes without errors
2. **Import**: ☐ no "Copied or Moved?" dialog (or you chose Copied) ☐ VM boots on its own
3. **First boot**: ☐ countdown appears ☐ defaults apply ☐ shows default password "omarchy"
4. **Desktop**: ☐ SDDM autologin lands in Hyprland ☐ top bar (Quickshell) renders
5. **HiDPI**: text is crisp, not soft/blurry. ☐ (if soft: View → Retina Resolution → More Space fixed it? ☐)
6. **Resize**: drag the Parallels window smaller/larger. ☐ desktop reflows within ~3 s ☐ stays crisp
7. **Fullscreen**: ☐ fills the screen edge-to-edge, no letterboxing
8. **Health**: open a terminal (Cmd+Option+O → terminal, or Super+Return if forwarded),
   run `sudo omarchy-parallels-verify`. ☐ verdict "pass" — paste the JSON in your report
9. **Update**: run `omarchy-update`. ☐ completes (the ARM keyring warning is expected)
10. **Password**: ☐ the default-password reminder appears in a terminal; ☐ running `passwd` clears it (YOLO path)

Also note: chip, RAM, display(s) + resolution, Parallels version/edition, anything surprising.
