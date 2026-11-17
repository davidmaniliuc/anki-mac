# Releasing AnkiMac

AnkiMac is **alpha**. Releases exist so people can try it, and every release
says so.

## Cutting a release

A release is a **tag**. On an up-to-date master:

```sh
scripts/release.sh            # the next patch: v0.1.0 first, then v0.1.1, v0.1.2...
scripts/release.sh 0.2        # start a new series at v0.2.0
scripts/release.sh 1.0.0      # exactly this version
```

The script checks that HEAD is a clean master that GitHub already has, shows
the version, build and commit, and asks before it tags and pushes. Pushing a
`vMAJOR.MINOR.PATCH` tag runs `.github/workflows/release.yml`, which, on an
`xcode-27` runner:

1. refuses a tag that is not `vMAJOR.MINOR.PATCH` or not on master,
2. checks the Sparkle keys and imports the signing certificate, if stored,
3. installs protobuf, swift-protobuf, ninja, xcodegen and the pinned Rust,
4. runs `scripts/build-backend.sh` (cached per anki submodule commit) and
   `scripts/build-app.sh` with the tag's version stamped in,
5. packs `out/app/AnkiMac.app` into `AnkiMac-<version>.dmg` with
   `scripts/package-dmg.sh`,
6. publishes a GitHub release on the tag carrying the DMG and its `.sha256`,
7. publishes the release to the in-app update feed, if the Sparkle keys are
   stored, and
8. bumps the Homebrew cask, if the tap token is stored.

A pushed tag that fails the build publishes nothing: delete it
(`git push origin :v0.1.1 && git tag -d v0.1.1`), fix master, and tag again.

**Versions.** A release is titled with its version and commit, **AnkiMac
0.1.0 (a3f91c2)**. The version (`CFBundleShortVersionString`) comes from the
tag; the build (`CFBundleVersion`) is the commit count, `git rev-list --count
HEAD`. Sparkle compares the build, and the commit count only goes up along
master, which is why a release tag must be on master and master's history
must never be rewritten. The version has to be three integers.

`App/project.yml` maps those keys to `$(MARKETING_VERSION)` and
`$(CURRENT_PROJECT_VERSION)`, and `scripts/build-app.sh` sets them. A local
build keeps the project's `MARKETING_VERSION` and still stamps the build; set
`ANKIMAC_VERSION` to override the version. Raise `MARKETING_VERSION` when a new
series starts.

**Without releasing.** *Actions ▸ Release ▸ Run workflow* builds
`AnkiMac-<version>-dev.<build>.dmg` and attaches it to the run. Nothing is
tagged or published.

**Locally.** `scripts/build-app.sh && scripts/package-dmg.sh` writes
`out/AnkiMac-<version>.dmg`.

## The Homebrew tap

The cask is `Casks/anki-mac.rb` in `davidmaniliuc/homebrew-tap`, beside
Substation's. Edit it there. Each release rewrites only its `version` and
`sha256` lines. One-time setup:

1. Commit the cask to the tap as `Casks/anki-mac.rb`; its `version` and
   `sha256` can be placeholders until the first release.
2. Give a fine-grained token **Contents: Read and write** on the tap (the one
   Substation uses works) and store it in this repo as the Actions secret
   **`HOMEBREW_TAP_TOKEN`**.

Until the secret exists the `homebrew` job is skipped, not failed. Users
install with:

```sh
brew install --cask davidmaniliuc/tap/anki-mac
```

The cask has `auto_updates true`, so `brew upgrade` leaves the app to Sparkle.

## In-app updates (Sparkle)

The app updates itself through [Sparkle](https://sparkle-project.org), pinned
in `App/project.yml`. It checks once a day from the first launch
(`SUEnableAutomaticChecks`), and *AnkiMac ▸ Check for Updates…* checks by
hand. A found update is shown, not installed without asking.

The workflow signs the DMG with an EdDSA private key and writes a one-item
`appcast.xml` to the orphan **`appcast`** branch, which the app reads from
`raw.githubusercontent.com/davidmaniliuc/anki-mac/appcast/appcast.xml`
(`SUFeedURL`). That URL only works while the repo is public. The app carries
the matching public key (`SUPublicEDKey`) and installs only an update that
key verifies.

**Only release builds update themselves.** The public key reaches the app
through `scripts/build-app.sh` only when the workflow sets it, so a local
build never starts Sparkle and has no *Check for Updates…* item.

**One-time setup**, on your Mac:

1. Download `Sparkle-2.10.0.tar.xz` from
   [Sparkle's releases](https://github.com/sparkle-project/Sparkle/releases)
   and run **`./bin/generate_keys --account anki-mac`**. It stores the private
   key in your login keychain and prints the public key. (The `--account`
   keeps it apart from Substation's key.)
2. `gh variable set SPARKLE_PUBLIC_ED_KEY --body '<public key>'`
3. `./bin/generate_keys --account anki-mac -x key.txt && gh secret set
   SPARKLE_PRIVATE_KEY < key.txt && rm key.txt`

The workflow checks that the two halves match before it builds. With neither
stored it builds an app without updates and says so; with only one it fails.

**Never lose the private key, and never change it.** Every installed copy
trusts only the key it shipped with; a release signed with another key is
rejected, and those users must download a new DMG by hand.

## Signing and Gatekeeper

Without a certificate the app is **ad-hoc signed**, and its signature changes
with every build. The keychain only trusts the exact binary that saved the
AnkiWeb login, so each update would ask for the login again. Releases sign
with the same self-signed **AnkiMac Development** certificate local builds
use, once it is stored:

1. In Keychain Access, *My Certificates* ▸ **AnkiMac Development** ▸ *Export*,
   as `AnkiMac.p12` with a password.
2. `base64 -i AnkiMac.p12 | gh secret set ANKIMAC_SIGNING_CERT`,
   `gh secret set ANKIMAC_SIGNING_CERT_PASSWORD`, then delete the file.

The app is **not notarized** either way, so macOS blocks a downloaded copy
until the user clicks *Open Anyway* in System Settings ▸ Privacy & Security.
The release notes say so, and the cask strips the quarantine attribute in a
`postflight_steps` block, as Substation's does.

Notarizing needs an Apple Developer Program membership: sign with a
**Developer ID Application** certificate with the hardened runtime on, notarize
and staple the DMG in the workflow, then drop the cask's quarantine strip and
the release notes' *Open Anyway* paragraph.
