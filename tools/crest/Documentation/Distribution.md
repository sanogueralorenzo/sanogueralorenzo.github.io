# Crest distribution

Crest has one official distribution path per platform:

- **macOS:** one app, Crest, with the Chromium and WebKit engines. It is
  distributed directly via GitHub Releases and official Homebrew cask (`crest-browser`),
  signed with Developer ID, notarized by Apple, and updated through Sparkle 2;
- **iPhone and iPad:** TestFlight and the App Store.

There is no Mac App Store build, and no separate WebKit-only download. Keeping
one macOS product avoids incompatible sandbox capabilities, duplicate update
behavior, and user confusion over which build supports extensions.

The Homebrew cask fetches un-modified binaries from GitHub Releases, 
thus it is still updated through Sparkle 2. 

Crest 0.8 opens the release line with `MARKETING_VERSION = 0.8.0` and stable
tag `v0.8.0`. User-facing release copy calls it Crest 0.8. Mac requires Apple
silicon and macOS 26.1 or later; iPhone and iPad remain WebKit apps with 26.1
deployment targets. The packaged Mac app and Sparkle feed take the higher
minimum macOS version required by the engine and the native UI framework.

The release build downloads a prebuilt Chromium engine instead of compiling
Chromium. Each engine is published once as a `chromium-engine-<key>` release,
keyed by its inputs; see "Releasing" in
[the Chromium engine README](../CrestEngines/Chromium/README.md). When a commit's
engine is missing, the **Ensure Chromium engine** job builds and publishes it on
the registered build Mac if `CHROMIUM_CI_ENABLED` is set, and otherwise stops the
release before signing.

## Release channels

| Channel | Trigger | GitHub Release | Sparkle channel |
| --- | --- | --- | --- |
| Stable | Push an exact `v<marketing-version>` tag | `v<version>`, Latest, non-prerelease | Default |
| Nightly | Daily schedule or manual dispatch, only when the source commit changes | New `nightly-<version>-<date>-<build>-r<run>.<attempt>` prerelease | `nightly` |
| Development | PR merged into `main`, or manual workflow dispatch | New `development-<version>-<date>-<build>-r<run>.<attempt>` prerelease | `development` |
| Experimental | Manual dispatch of **Publish experimental macOS release** for a branch | New `experimental-<version>-<branch>-<date>-<build>-r<run>.<attempt>` prerelease | `experimental` |

Browse [Stable](https://github.com/pauljoda/Crest/releases?q=prerelease%3Afalse),
[Nightly](https://github.com/pauljoda/Crest/releases?q=prerelease%3Atrue+%22Nightly+builds%22), or
[Development](https://github.com/pauljoda/Crest/releases?q=prerelease%3Atrue+%22Development+builds%22).
The README links to every channel, and each release's notes link to its own
channel. GitHub's
[release search](https://docs.github.com/en/repositories/releasing-projects-on-github/searching-a-repositorys-releases)
accepts `prerelease:false`, `prerelease:true "Nightly builds"`, and
`prerelease:true "Development builds"` to filter channels using their release-note
descriptions.
Only stable releases receive GitHub's Latest designation. Manual dispatch of
**Publish macOS release** offers development and nightly; stable publication
requires a tag push. Experimental builds test a branch before it reaches `main`.

**Publish macOS release** also runs when a PR is merged into `main`, including
PRs from forks, and publishes Development from the merge commit. Closing an
unmerged PR does nothing. It never checks out the PR's own code: it builds the
merge commit on `main` with the existing `production` environment and
serialized publication queue. A direct push to `main` publishes nothing.

The marketing version comes from `Config/Version.xcconfig`. Stable tags must
match it exactly. Distributed build numbers add the GitHub Actions run number
to Crest's public-repository build epoch. The epoch keeps Sparkle ordering
strictly increasing across the repository migration; the run number keeps every
subsequent published update newer than the prior build. Preflight also reads
every signed appcast and raises the build number above every published build,
so retries and delayed runs cannot publish an update that Sparkle considers older.

The appcast is hosted at:

`https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast.xml`

Development builds use a separate signed feed so frequent commits cannot prune
stable or nightly entries:

`https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-development.xml`

Experimental builds use `appcast-experimental.xml`. Each feed also has a
`-webkit` twin, such as `appcast-webkit.xml`, which WebKit-only builds of Crest
read. Those twins now offer the same Crest installer, so a WebKit-only copy
updates into the dual-engine app on its next check.

The `updates` branch is workflow-owned. It contains the appcasts, a short
README, and `release-note-publication.json`, whose independent stable, nightly,
and development cursors record the last successfully published catalog entry.
Every build gets its own GitHub Release and retains its assets. Nightly and
development tags include the version, UTC date, build number, workflow run, and
attempt, such as `nightly-0.5.25-2026-09-03-1061-r61.1`. Each run and rerun gets
a new tag, even after an interrupted appcast publication, so it cannot overwrite
an earlier attempt's installer. Release titles put the
channel first and include the version, date, and build. Each release therefore
keeps its actual publication date.

Asset filenames start with `Installer-`, `Checksum-`, or `Debug-Symbols-`
so their purpose is visible before GitHub truncates the remaining name.
Every filename carries the version; prerelease filenames also include the UTC
date and source commit. The workflow never moves existing channel tags or
deletes older releases. Existing `nightly` and `development` releases remain
available for old appcast links. GitHub Packages is not part of desktop
distribution.

Before allocating the macOS signing runner, a nightly preflight compares the
current source commit with the last nightly in the signed appcast. The appcast
is the completed-publication boundary. An
unchanged scheduled or manually dispatched nightly succeeds without building,
notarizing, creating a release, or advancing an appcast. If no nightly appcast
exists, preflight builds even if a GitHub Release exists, because that release
may belong to an interrupted publication.

Release notes come from the explicit `Documentation/ReleaseNotes.json` catalog.
Every product or architecture commit adds a stable entry ID, category, and
purpose-written message. The generator reads the selected channel's cursor,
groups the later public entries into New, Improved, and Fixed highlights, omits
`internal` entries, and limits long ranges to the 12 most recent highlights.
The catalog's immutable publication baselines name each channel's starting
entry until the workflow writes the live cursor file. Because entry identity and cursor position are independent
of commit hashes, rebases and other history rewrites do not repeat published
copy or block a nightly. The same concise notes appear on GitHub and as
structured Markdown in Sparkle's update interface.

## Publication order

Before publication, run the affected retained app tests and release-script
contract tests locally for the exact commit, following the
[repository guardrails](RepositoryGuardrails.md). The production workflow follows
these steps:

1. validate the exact source SHA through the reusable **Build Crest** workflow
   and find the Chromium engine for its engine key, building it on the registered
   Mac when it is missing and that builder is enabled. Signing waits for both;
2. regenerate the project and check version metadata, product identity, and
   cache hygiene;
3. import the Developer ID identity into a temporary keychain and install the
   matching release provisioning profile;
4. archive and export the WebKit composition as an arm64 Developer ID build.
   Xcode's export resolves Crest's production CloudKit, push, and keychain
   entitlements; the exported app only supplies them and is not published;
5. download and checksum the Chromium engine, build the native core and Crest's
   interface framework, and package them with the engine as `Crest.app`, signed
   with hardened runtime and those entitlements;
6. verify the app's signature, bundle identifier, update channel, and build
   number;
7. notarize and staple the app;
8. create, sign, notarize, staple, and Gatekeeper-check the disk image;
9. publish the build-provenance attestation, then reconcile and digest-verify
   the disk image, checksum, and dSYM;
10. sign the Sparkle appcast and its `-webkit` twin, advance only that channel's
    release-note cursor, and publish them in one `updates` branch commit after
    the release assets exist.

If any signing, notarization, appcast, or branch-push step fails, neither the
appcast nor its release-note cursor advances. An update therefore never points
at an absent or unverified disk image, and the next successful attempt retains
all unpublished release-note entries.

Prerelease publication is safe to repeat after an interrupted GitHub request. The
workflow reuses matching uploaded assets, removes only incomplete or mismatched
assets for the target build, and retries each replacement with state
verification. Older releases and their assets remain downloadable after the
new signed appcast is pushed. If a release is created but its appcast fails to
publish, the next run still uses the last successfully published channel cursor
for release notes and the signed appcast for nightly deduplication.

When a user chooses Download Update from an available update card, Crest ends
that undownloaded offer and asks Sparkle to check the selected channel again.
It downloads the newly selected compatible build without an extra click. A
failed or cancelled check does not install the old offer. Sparkle continues to
own signature verification, channel filtering, version selection, and installation.
Already downloaded, extracting, or prepared updates retain Sparkle's existing
installation lifecycle.

## GitHub production environment

The release job runs in the `production` environment and consumes the seven
GitHub Actions secrets below. They may be configured at repository scope or in
that environment. Their values are not kept in source, copied into forks, or
exposed to pull-request builds.

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Developer ID certificate and private key exported as an encrypted PKCS #12 archive, then base64 encoded |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used for that PKCS #12 archive |
| `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` | `Crest Developer ID` provisioning profile that grants the direct build access to Apple services |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect API issuer used by Xcode and `notarytool` |
| `APP_STORE_CONNECT_API_KEY_ID` | Identifier of the App Store Connect API key |
| `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64` | Downloaded `.p8` private key, base64 encoded |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Private key used only to sign appcast enclosures |

The corresponding Sparkle public key is embedded in the macOS app. The
Developer ID certificate and Sparkle key should be rotated deliberately, with
the old signing path retained long enough to update installed copies safely.

## Operator checklist

Before publishing a stable tag:

1. confirm `CHANGELOG.md`, `Documentation/ReleaseNotes.json`, and the marketing
   version are ready;
2. complete local app and release-script tests for the commit being published;
3. confirm **Build Crest** passed on the intended `main` commit and the Pages
   workflow is green. The stable release will validate its exact source again;
4. confirm the commit's Chromium engine is published:
   `gh release view "$(python3 Scripts/control-plane/chromium_engine.py tag)"`;
5. confirm all seven release secrets are available to the production job;
6. create and push the exact version tag;
7. inspect the workflow's signature, notarization, Gatekeeper, checksum, and
   attestation results;
8. install the published disk image on a clean macOS account and exercise both
   a manual update check and the normal relaunch path. For 0.7, cover an upgrade
   from the previous stable WebKit-only app and an existing Chromium build,
   preserving Space and tab identity, engine profiles, and unsaved-changes prompts.

For a new release line, explicitly set the intended version with
`Scripts/set-version.sh --release X.Y.Z`. Routine fixes use
`Scripts/set-version.sh --patch`. Keep `CURRENT_PROJECT_VERSION` unchanged;
the distribution workflows own build numbers. Update the changelog, refresh
the public roadmap with `Scripts/render-roadmap.py --write`, and review the
maintained [iPhone and iPad listing](../Marketing/AppStore/README.md) against
the release's mobile capabilities.

Commit the version and release documentation together, push that commit to
`main`, and wait for a **Build Crest** run on it to pass before creating and
pushing an annotated `vX.Y.Z` tag at that same commit. A new release line uses
`Scripts/check-version.sh` and the release-note catalog check;
`--fix-commit` applies only to patch increases on the existing line.
Pushing the stable tag starts macOS publication. App Store build selection,
submission, and release are separate steps in App Store Connect.

Nightly, development, and experimental builds use the same signing,
notarization, and verification gates as a stable build. Each prerelease retains
its own asset set after the signed appcast has advanced. Development
publication keeps only the latest queued public commit when dispatches arrive
faster than Apple notarization. Stable, nightly, and development builds default
to their own channel, and experimental builds default to Development. An
existing user choice remains authoritative.

## Local macOS iteration

Maintainers can build and install the dual-engine Release app, packaged the
way the release workflow packages it, without publishing an update:

```bash
Scripts/install-local-macos-release.sh
```

The command requires Crest's Developer ID identity and provisioning profile in
the local keychain/Xcode profile directory, the .NET SDK, and the GitHub CLI. It
downloads the published Chromium engine matching the checkout's engine inputs
and caches it in `~/Library/Caches/Crest-local-release`. Set
`CREST_CHROMIUM_APP` to a locally built `Chromium.app` to package that engine
instead. It then archives and exports the WebKit composition to resolve the
production iCloud, push, and keychain entitlements, builds the native core and
`CrestChromiumUIProduct`, and packages them with the engine, signed with
hardened runtime. Finally it quits the installed Crest, replaces
`/Applications/Crest.app`, and relaunches it. The app is signed but not
notarized. Builds reuse `~/Library/Developer/Xcode/DerivedData/Crest-LocalRelease`.

The build number defaults to the greater of the installed build number and the
current development appcast. That prevents the current public build from
immediately replacing a local iteration without outranking the next published
Sparkle build. Set `CREST_LOCAL_BUILD_NUMBER` only when a specific local bundle
version is needed.

Merging a PR into `main` automatically starts development publication. Direct
pushes to `main` do not publish or advance an appcast. To publish a separately
validated branch, dispatch **Publish macOS release** with the `development`
channel from that branch.

## Verify a downloaded release

After mounting a published disk image, users and maintainers can inspect it
with standard macOS tools:

```bash
shasum -a 256 -c Checksum-Crest-*.dmg.sha256
codesign --verify --deep --strict --verbose=2 /Volumes/Crest/Crest.app
spctl --assess --type execute --verbose=4 /Volumes/Crest/Crest.app
xcrun stapler validate /Volumes/Crest/Crest.app
```

GitHub's build-provenance attestation and the checksum file provide independent
links from the public workflow run to the exact disk image.
