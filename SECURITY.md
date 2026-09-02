# Security Policy

## Reporting a vulnerability

Email **ari@zilnik.com** with subject `[omarchy-parallels security]`, or use GitHub's
private vulnerability reporting on this repository. Please include the image version
(`latest.json` → `version`) and, if relevant, the output of `omarchy-parallels-verify`.

You'll get an acknowledgment within 72 hours. Please don't open public issues for
unpatched vulnerabilities.

## Scope

- The `install.sh` / `host/` scripts that run on your Mac
- The `guest/` payload (first-boot, autoresize, verify) inside the image
- The build pipeline's sysprep guarantees (no keys, no credentials, no identity in shipped images)

Vulnerabilities in Omarchy itself, Arch Linux ARM, Hyprland, or Parallels Desktop
belong upstream — we'll happily help route them.

## Verifying what you download

Every release is checksummed and signed:

```sh
shasum -a 256 -c omarchy-parallels-vX.Y.Z.zip.sha256
minisign -Vm omarchy-parallels-vX.Y.Z.zip -p minisign.pub
```

`install.sh` performs both checks automatically when minisign is available.
