# Rebuilding the image from scratch

For auditors and maintainers: the shipped image is reproducible from public sources.
Time: ~60–90 min. This is also the Tools-free path (skip step 7).

1. **Create the VM** (Parallels wizard, Standard edition is fine): Other Linux, 4 CPU / 6 GB /
   64 GB. Two wizard traps to fix in `config.pvs` afterward (VM stopped, Parallels quit):
   the disk is created **disabled** (`<Enabled>0`) and on **IDE** (`<InterfaceType>0`), which
   Apple Silicon Parallels does not emulate → set `Enabled=1`, `InterfaceType=2` (SATA).
   Attach the ISO by hand (the wizard only sniffs it) and put CD first in boot order.
2. **Boot [Archboot](https://release.archboot.com/aarch64/latest/iso/) aarch64**, Ctrl-C to a shell.
   Note: Archboot's sshd listens on **11838**, publickey-only; the console drops typed digits
   from some hosts — install your key via the console using key codes if scripting it.
3. **Partition + base install**: GPT, 1 GB ESP (vfat) + rest ext4;
   `pacstrap -K /mnt base linux-aarch64 linux-firmware sudo networkmanager openssh vim git base-devel`.
4. **Configure**: `genfstab`, locale/hostname/user, `bootctl install`, a loader entry pointing at
   `/Image` + `/initramfs-linux.img` with `root=UUID=<sda2>`. Reboot to disk.
5. **Omarchy**: as the normal user,
   `git clone -b arm64 https://github.com/alexisraitano-myffu/omarchy-arm && cd omarchy-arm && ./install.sh --yes`.
   (Audit it first — see README provenance section. `--yes` matters: detached stdin otherwise
   dies at a confirm prompt.) Then `systemctl enable sddm`.
6. **SDDM fix**: the Omarchy theme submits an empty username without state —
   write `/var/lib/sddm/state.conf` (`[Last] User=... Session=hyprland-uwsm.desktop`).
7. **Parallels Tools** (optional): Actions → Install Parallels Tools in the Parallels UI, or pipe
   `prl-tools-lin-arm.iso` in over SSH; `./install --install`. Userspace only on ARM — no kernel modules.
8. **Payload + image**: from this repo, `build/refresh.sh` (installs firstboot/autoresize/verify,
   gates on verify), then `build/package.sh <version>`.
