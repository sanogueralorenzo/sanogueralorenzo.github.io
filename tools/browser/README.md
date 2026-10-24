# Browser

A local copy of [Crest](https://github.com/pauljoda/Crest), an Apple-platform browser with isolated Spaces, Chromium and WebKit on Mac, and WebKit on iPhone and iPad. This project stays separate from `tools/assistant`; no Assistant integration is configured.

Imported from upstream commit [`36ed0821b08b6373775208aa9bb104596f1184a1`](https://github.com/pauljoda/Crest/commit/36ed0821b08b6373775208aa9bb104596f1184a1). Source, assets, tests, tooling, and upstream metadata are preserved without nested Git history. The nested `.github` workflows are upstream references; this repository's CI remains site-only.

## Setup

Requires an Apple silicon Mac, Xcode with macOS/iOS SDKs supporting the 26.1 deployment targets, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and the .NET SDK pinned in `CrestCore/global.json`.

```sh
cd tools/browser
Scripts/control-plane/install-dotnet.sh
Scripts/bootstrap.sh
open Crest.xcodeproj
```

If Command Line Tools is selected instead of Xcode, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the build commands.

The `Crest` scheme builds the Mac app with WebKit. Chromium packaging requires a prebuilt engine; see [the engine setup](CrestEngines/Chromium/README.md). `project.yml` is authoritative; run `xcodegen generate` after changing targets or project configuration.

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation and [the architecture overview](Documentation/ARCHITECTURE.md) for the SwiftUI apps, C# NativeAOT core, and engine boundaries.

## License

Copyright 2026 Paul Davis. Browser retains Crest's [MPL-2.0 license](LICENSE), [NOTICE](NOTICE), and [third-party notices](THIRD_PARTY_NOTICES.md), independently of this repository's root MIT license. The imported app still uses Crest's identity; modified distributions must follow [TRADEMARKS.md](TRADEMARKS.md).
