# Maintainer setup (one-time)

Everything a maintainer needs to cut and publish a release. None of this is needed to *use* the image.

## Signing key (minisign)

Releases are signed so users can prove an image is genuinely yours.

```sh
brew install minisign
minisign -G -p minisign.pub -s ~/.omarchy-parallels.key   # prompts for a passphrase — use one
```

- Commit **`minisign.pub`** to the repo root (public — safe).
- Keep **`~/.omarchy-parallels.key`** private; never commit it. `build/package.sh` reads it via
  `MINISIGN_KEY=~/.omarchy-parallels.key`.
- Paste the public key string into `install.sh`'s `PUBKEY` default (or ship it via
  `OMARCHY_PARALLELS_PUBKEY`) so the installer verifies signatures automatically.

## Cloudflare R2

1. Create a bucket, e.g. `omarchy-apple-silicon-parallels`.
2. Connect a custom domain / public bucket URL, e.g. `https://dl.omarchy-apple-silicon.zilnik.me`
   (R2 → Settings → Public access, or a Worker route). This is `PUBLIC_BASE`.
3. Create an R2 API token (Object Read & Write scoped to the bucket). Configure the `aws` CLI:

   ```sh
   aws configure   # use the R2 token's key id + secret; region us-east-1 is fine
   export R2_ENDPOINT="https://<account-id>.r2.cloudflarestorage.com"
   export R2_BUCKET="omarchy-apple-silicon-parallels"
   export PUBLIC_BASE="https://dl.omarchy-apple-silicon.zilnik.me"
   ```

4. Apply for **[Cloudflare Project Alexandria](https://blog.cloudflare.com/expanding-our-support-for-oss-projects-with-project-alexandria/)**
   once the project is public — free R2/Workers credits for OSS. (Precedent: Node.js and OpenTofu
   both serve release artifacts from R2.)


### Fully headless — no GUI clicks

`package.sh` and `test/run-tests.sh` drive Parallels entirely through `prlctl`
(`clone` / `start` / `register` / `exec` / `stop` / `unregister`), all of which work on the
trial and Standard editions of Parallels Desktop 27. `prlctl clone` mints a fresh UUID + MAC
with no "duplicate MAC" dialog, `prlctl start` boots with no Play button, and the cold-import
test asserts every invariant from inside the guest via `prlctl exec` — so no sshd, no console
automation, and no dialog-clicking are needed. Run `make image` and `make test` unattended.

If a future Parallels release gates any of these behind Pro again, the fallback is the manual
`open`-and-click path; the scripts would need the pre-`prlctl` version restored from git history.

## Cutting a release

```sh
build/refresh.sh                      # update builder VM + install payload, gate on verify
# shut down the builder VM (its window: power off) — package.sh needs it stopped
build/package.sh 0.1.0                # clone → sysprep clone → compact → strip → zip + sign
test/run-tests.sh dist/omarchy-apple-silicon-parallels-v0.1.0.zip   # Tier 2 cold-import check
MINISIGN_KEY=~/.omarchy-parallels.key build/release.sh 0.1.0   # upload + latest.json + tag
git push origin main --tags
```

Update `CHANGELOG.md` before tagging.
