# Maintaining Crest's Chromium fork

The fork is the pinned recipe and patch set in Crest. `~/Dev/CrestChromium` is its
durable build workspace. A separate Git repository is unnecessary while the
Chromium host and Crest's C ABI evolve together. No product code belongs only in
the expanded Chromium tree: make changes in the overlay or patch set first.

## Build workspace

Install Python 3.11 or newer, Go, Xcode and its Metal toolchain. Retain the macOS
SDK named by `performanceInputs.macSDKVersion` in `source.lock.json`. Use one
tools environment and one source/output directory per pinned upstream recipe:

```sh
python3 -m venv ~/Dev/CrestChromium/tools
~/Dev/CrestChromium/tools/bin/python -m pip install schema==0.7.8 ninja==1.13.0
export PATH="$HOME/Dev/CrestChromium/tools/bin:/opt/homebrew/bin:$PATH"
python Scripts/control-plane/chromium-fork.py status
python Scripts/control-plane/chromium-fork.py build \
  --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

The command verifies upstream pins, prepares missing source, applies Crest's
host, configures the performance build, compiles, and checks JavaScript execution
in a headless browser with a temporary profile. It does not use installed Crest
or personal browser state. This smoke check covers engine startup and rendering;
native window, Space, input, extension, and persistence acceptance remains part
of approving the Chromium product for stable distribution.

The workspace contains `sources/<preparation-key>/upstream`, `profiles`, `tools`,
and the Actions runner. App and ABI updates reuse the same upstream build.
Changing the upstream recipe gets a new directory and preserves the previous
working engine. Before an update prepares its source, it removes every other
prepared source except the one its checkout builds from, so the workspace holds
at most the integration branch's source and one update's. Preparation requires
50 GiB free; compilation keeps a 15 GiB reserve. These are minimum gates, not a
maximum disk budget. Inspect incomplete preparations before resuming them.
Remove other obsolete source directories only when no process uses them and the
previous working engine is published.

To adopt an existing completed source/build directory on the same volume:

```sh
python Scripts/control-plane/chromium-fork.py adopt --upstream /path/to/ungoogled-chromium-macos
```

Adoption verifies the recipe and host before moving it, and leaves a compatibility
symlink at the previous path for references in generated build files. Keep that
link until the generated paths have been migrated and checked. Existing builds
may need a one-time rebuild if the relocation changes compiler arguments.
Subsequent builds reuse the managed workspace. Run maintenance through the
workspace command, which locks out other managed operations. Stop older direct
Ninja commands before changing the shared source; those commands predate the
workspace lock.

## Upstream updates

```sh
python Scripts/control-plane/chromium-fork.py check-upstream
python Scripts/control-plane/chromium-fork.py update \
  --tag 152.0.7977.82-1.2 \
  --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

Use a real newer tag reported by `check-upstream`; the tag above illustrates the
syntax. Start updates from a clean Crest checkout. The updater resolves the
released macOS recipe and its ungoogled submodule, pins the source checksum and
patch files, refreshes host hashes only after strict patch application, and pins
the new source's PGO profile. It restores the source lock and host hashes if
preparation fails. Build failures leave the candidate available for inspection.
An esbuild or TypeScript compiler version change stops for a toolchain review
instead of using a stale toolchain. New milestones need `--allow-major` here. The schedule builds a new
milestone for review once the pinned one has no newer fix, but it ships only when
its PR is merged. `fork.json.automaticMajorUpdates` can also let milestone
updates release automatically.

The immediate upstream is ungoogled-chromium for macOS. Updates therefore follow
its releases, not the first Google Chrome announcement. Pulling a Google security
fix ahead of that release requires a deliberate patch and normal engine review.

## Certificate trust backports

Chrome distrusts certificate authorities through components: CRLSets and Chrome
Root Store updates. Ungoogled's domain substitution points the component updater
at an unreachable host, so this engine receives neither, nor Certificate
Transparency log list updates. It trusts only the blocklist, root store and log
list compiled into its source. Chromium stops enforcing Certificate Transparency
70 days after the built-in log list's date, so the engine needs regular updates.

`native-host.patch` therefore carries upstream distrust changes that the pinned
source does not yet contain, copied hunk for hunk from Chromium:

| Files | Change | Upstream |
| --- | --- | --- |
| `net/cert/cert_verify_proc_blocklist.inc` | Blocks the keys of eight compromised eMudhra subordinate CAs | Chromium `da63b94c4ee2` |
| `net/data/ssl/chrome_root_store/root_store.textproto`, `root_store.certs` | Removes emSign ECC Root CA - G3 | Chrome Root Store version 43, Chromium `8793082f793c` |

The root store keeps its pinned version number. Once an upstream release
contains a change, its hunks no longer apply and the update stops there: remove
those sections from the host patch and refresh the host inputs.

## GitHub Actions

Install the repository-scoped runner on the build Mac:

```sh
python Scripts/control-plane/install-chromium-runner.py
```

This verifies GitHub's runner archive checksum and installs a user LaunchAgent
with the `crest-chromium` label. It starts at login; the Mac must remain awake and
online to accept builds. Use `~/Dev/CrestChromium/runner/svc.sh stop` and `start`
from that directory to control it. Signing keys stay in the existing release
environment. The maintenance workflow has no pull-request trigger; never run
untrusted pull-request code on this persistent personal Mac.

Configure these repository variables:

| Variable | Purpose |
| --- | --- |
| `CHROMIUM_WORKSPACE` | Absolute persistent workspace path on the Mac |
| `CHROMIUM_SDK` | Absolute path to the SDK pinned by the source lock |
| `CHROMIUM_BUILD_JOBS` | Compiler parallelism, default 4 |
| `CHROMIUM_CI_ENABLED` | `true` allows manual and scheduled engine builds |
| `CHROMIUM_UPSTREAM_ENABLED` | `true` builds new upstream releases every six hours and opens a PR for each |
| `CHROMIUM_AUTO_RELEASE` | `true` permits successful updates to merge and publish experimental |

The workflow must be present on the default branch for its schedule to run. Its
`fork.json` integration branch must also contain the maintenance scripts. Use the
Actions UI or `gh workflow run chromium.yml --ref <workflow-branch> -f operation=check`
to check upstream. `operation=build` builds and publishes the pinned engine;
`operation=update` builds a released update and opens a PR. `upstream_tag` can
select a specific release, and `allow_major=true` allows manual milestone review.
The repository must allow Actions to create pull requests, and automatic merging
must be enabled before automatic experimental publication can merge update PRs.

An update PR contains the new pins, host hashes, a patch version increment, and
a release-note entry. Its engine is published before the branch is pushed.
App release jobs consume only the artifact whose engine key matches their own
source. No signing job reads a mutable local build directory.

## Publishing experimental builds

Enable `CHROMIUM_CI_ENABLED=true` after registering the Mac, then publish the
experimental branch with its own workflow definition:

```sh
gh workflow run experimental-release.yml --ref chromium-control-plane \
  -f source_ref=chromium-control-plane
```

The release resolves the branch to one commit. The reusable `Ensure Chromium
engine` workflow checks for its published engine, including the full input key,
archive, and checksum. If missing, it builds and publishes that engine on the
Mac. An existing artifact skips the Mac entirely. The signing job then downloads
that engine, verifies its checksum, builds Crest's native core and UI from the
same commit, and signs and notarizes the installer. It publishes the
experimental feed and its `-webkit` twin, which offers the same installer.

## Enabling automatic upstream releases

Keep `CHROMIUM_UPSTREAM_ENABLED=false` and `CHROMIUM_AUTO_RELEASE=false` during
initial setup. Manual upstream updates can still build a candidate for review.
The six-hour schedule runs from `chromium.yml` on the default branch and updates
the integration branch named in `fork.json`. Every run reports the newest
upstream release and why it did or did not build it.

Set `CHROMIUM_UPSTREAM_ENABLED=true` to build new releases and open a PR for
each. A release gets one PR; later commits on the integration branch do not
rebuild it, and a closed PR stays closed. While an update PR is open, the
schedule waits for it instead of building the next release. Check out the PR branch and run
`Scripts/install-local-macos-release.sh` to try its published engine; merging
publishes Development. Set `CHROMIUM_AUTO_RELEASE=true` when those updates may
also merge and ship to Development on their own. Automation uses normal PR merge
rules. It checks the PR head has
not changed, then explicitly dispatches the experimental release at the merged
commit. Publication fails if the branch moves again before release preflight.
New milestones still wait for a merge unless `automaticMajorUpdates` is enabled.

Stable and development Chromium releases need a separate readiness decision and
implementation. Changing `automaticChannel` to either one fails the current gate.

Turn `CHROMIUM_AUTO_RELEASE=false` to stop future automatic publication, or
`CHROMIUM_CI_ENABLED=false` to stop new engine builds. Cancel a running workflow
separately if it must stop immediately. Failed or conflicting updates keep the
previous appcast in service. To roll back an engine, restore its reviewed pins
in a new patch-version commit and publish a newer app build; do not replace an
existing engine artifact or decrease the Sparkle build number. Toggle values
apply to newly started runs; cancel an in-progress run to stop it immediately.
