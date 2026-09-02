# AI disclosure

This project was built almost entirely by **Claude (Anthropic)**, driven interactively by
[Ari Zilnik](https://github.com/) as the human in the loop, who directed the work, made the
product and security calls, and cleared every destructive or outward-facing action.

**What the AI did:**
- Diagnosed the Apple-Silicon Parallels install path for Omarchy from scratch — including the
  IDE-vs-SATA disk trap, the HiDPI-pref-keyed-by-UUID problem, the `nr_cpus=1` red herring, and
  the SDDM empty-username lockout — by running and observing a real VM, not from documentation.
- Wrote the entire build pipeline, installer, guest payload, first-boot OOBE, and docs.
- Measured the Mac↔Omarchy keyboard conflicts empirically (rebinding keys to markers and probing
  each combo) rather than guessing, and implemented the fix.
- Ran an adversarial review of its own installer and OOBE (a separate AI reviewer fed only the
  artifacts) and fixed the blockers it found.
- Attempted the ARM package builds documented in [`packages/`](packages/).

**What the AI did not do unsupervised:** publish anything, spend money, sign releases, or push to
a public remote. Those remain human actions.

**How to trust it anyway:** don't trust the author, verify the artifact. Every release is
checksummed and signed ([SECURITY.md](SECURITY.md)), the image is reproducible from the public
scripts in [`build/`](build/) ([docs/rebuild-from-iso.md](docs/rebuild-from-iso.md)), and the
upstream `omarchy-arm` port was independently audited (see [README](README.md) → Security &
provenance). AI authorship raises the bar on verifiability; it doesn't replace it.

Model: Claude Opus. Sessions: September 2026.
