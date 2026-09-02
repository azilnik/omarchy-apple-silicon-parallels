# Security

Found a security issue — a bad default, a way to bypass the checksum/signature, something in the
install scripts or the shipped image? Please report it privately: email **ari@zilnik.com** or use
**Report a vulnerability** on this repo's Security tab, rather than opening a public issue. Include
the image version from `latest.json`.

Every release is checksummed and minisign-signed — `install.sh` verifies both, or check by hand:

```sh
shasum -a 256 -c omarchy-apple-silicon-parallels-vX.Y.Z.zip.sha256
minisign -Vm omarchy-apple-silicon-parallels-vX.Y.Z.zip -p minisign.pub
```

Issues in Omarchy, Arch, Hyprland, or Parallels themselves belong upstream — happy to help route them.
