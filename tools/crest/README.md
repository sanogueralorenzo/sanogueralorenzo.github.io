# Crest

A streamlined fork of [pauljoda/Crest](https://github.com/pauljoda/Crest), with system light/dark appearance, a frameless Mac window, a hover sidebar, and GitHub live folders. The Mac app uses WebKit in the local build; the upstream Chromium composition remains available separately.

## Setup

Requires Apple silicon, Xcode with macOS/iOS 26.1 SDKs, XcodeGen, and the .NET SDK pinned in `CrestCore/global.json`.

```sh
git clone git@github.com:sanogueralorenzo/Crest.git
cd Crest
Scripts/control-plane/install-dotnet.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/bootstrap.sh
Scripts/run-local.sh
```

The local runner uses an ad-hoc signature and the persistent `browser-local` profile, shared with the existing local Crest installation. Pass `--build-only` to avoid opening it. Use a different `CREST_ISOLATED_PERSISTENCE_ID` for testing so real tabs and logins stay untouched. No Apple developer team is required; local iCloud sync and upstream binary updates are disabled.

See [the fork differences](Documentation/ForkDifferences.md) for product decisions and upstream maintenance, [CONTRIBUTING.md](CONTRIBUTING.md) for checks, and [the architecture](Documentation/ARCHITECTURE.md) for implementation boundaries.

## License

Crest retains its [MPL-2.0 license](LICENSE), [NOTICE](NOTICE), [third-party notices](THIRD_PARTY_NOTICES.md), and [trademark requirements](TRADEMARKS.md).
