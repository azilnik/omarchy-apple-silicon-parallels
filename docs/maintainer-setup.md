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

1. Create a bucket, e.g. `omarchy-parallels`.
2. Connect a custom domain / public bucket URL, e.g. `https://dl.omarchy-parallels.zilnik.me`
   (R2 → Settings → Public access, or a Worker route). This is `PUBLIC_BASE`.
3. Create an R2 API token (Object Read & Write scoped to the bucket). Configure the `aws` CLI:

   ```sh
   aws configure   # use the R2 token's key id + secret; region us-east-1 is fine
   export R2_ENDPOINT="https://<account-id>.r2.cloudflarestorage.com"
   export R2_BUCKET="omarchy-parallels"
   export PUBLIC_BASE="https://dl.omarchy-parallels.zilnik.me"
   ```

4. Apply for **[Cloudflare Project Alexandria](https://blog.cloudflare.com/expanding-our-support-for-oss-projects-with-project-alexandria/)**
   once the project is public — free R2/Workers credits for OSS. (Precedent: Node.js and OpenTofu
   both serve release artifacts from R2.)


### Heads-up: GUI prompts during `package.sh`

On Standard/trial editions, cloning + booting the image VM triggers a couple of Parallels
dialogs the script can't dismiss for you — watch the Parallels window during `make image`:

- **"Duplicate MAC addresses detected"** → click **Create new** (the clone needs its own MAC).
- **Trial nag** (on the trial edition) → click **Continue Trial**.
- If the cloned VM shows a Play button instead of booting, click it.

The script waits for the clone to register and SSH up, so it pauses at exactly these moments.

## Cutting a release

```sh
build/refresh.sh                      # update builder VM + install payload, gate on verify
# shut down the builder VM (its window: power off) — package.sh needs it stopped
build/package.sh 0.1.0                # clone → sysprep clone → compact → strip → zip + sign
test/run-tests.sh dist/omarchy-parallels-v0.1.0.zip   # Tier 2 cold-import check
MINISIGN_KEY=~/.omarchy-parallels.key build/release.sh 0.1.0   # upload + latest.json + tag
git push origin main --tags
```

Update `CHANGELOG.md` before tagging.
