# Third-party notices

Crest ships these third-party runtime components:

| Component | Version | Use | License |
| --- | --- | --- | --- |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.5 | Signed software updates on macOS | MIT-style license with bundled BSD, MIT, and zlib-style notices |
| [.NET runtime](https://github.com/dotnet/runtime) (Native AOT) | 10.0.5 | Crest's core, compiled ahead of time into every app | MIT, with bundled third-party notices |
| [Chromium](https://www.chromium.org/), built with [ungoogled-chromium-macos](https://github.com/ungoogled-software/ungoogled-chromium-macos) | 152.0.7977.82 | The Chromium engine in Crest's Chromium build for macOS | BSD-3-Clause, with bundled third-party licenses |

The complete notices are preserved in
[`ThirdParty/Sparkle-LICENSE.txt`](ThirdParty/Sparkle-LICENSE.txt),
[`ThirdParty/DotNet-LICENSE.txt`](ThirdParty/DotNet-LICENSE.txt) and
[`ThirdParty/Chromium-LICENSE.txt`](ThirdParty/Chromium-LICENSE.txt).
Chromium includes many third-party components under their own licenses; the
Chromium build lists every one of them, with its license text, at
`chrome://credits`.

Crest's emoji picker catalog is generated from the official
[Unicode Emoji 17.0 test data](https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt).
The Unicode data notice is preserved in
[`ThirdParty/Unicode-LICENSE.txt`](ThirdParty/Unicode-LICENSE.txt).

Beyond these, the apps link only Apple platform frameworks supplied by the macOS
and iOS SDKs: AuthenticationServices, CloudKit, LocalAuthentication, Security,
SwiftUI, and WebKit.

## Development and release tooling

Crest's source tree is generated with MIT-licensed
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The optional dead-code audit
uses MIT-licensed [Periphery](https://github.com/peripheryapp/periphery). These
tools are not linked into or redistributed with Crest.

The GitHub workflows use pinned MIT-licensed actions from `actions/*`,
including `actions/setup-dotnet` for the core, and the MIT-licensed source in
`github/codeql-action`. The CodeQL CLI downloaded by that action is
subject to GitHub's CodeQL terms and is used only as a hosted source-analysis
service; it is not part of Crest's distributed app or source. The license audit
keeps the exact workflow-action repository inventory synchronized with
`Config/ThirdPartyDependencies.json`.

## Help Center toolchain

The Help Center is built with Docusaurus 3.10.2, React 19.2.8, React DOM
19.2.8, MDX React 3.1.1, clsx 2.1.1, and prism-react-renderer 2.4.1. These direct
dependencies are MIT-licensed. Their exact transitive dependency versions and
declared licenses are recorded in `HelpCenter/package-lock.json`.

The build graph also includes the CC BY 4.0 `caniuse-lite` browser-support
dataset. It is used by the documentation build toolchain and is not linked into
the Crest application. Attribution: caniuse-lite contributors,
<https://github.com/browserslist/caniuse-lite>.

`eval` 0.1.8, `format` 0.2.2, and `require-like` 0.1.2 omit a machine-readable
license field in their package metadata; their distributed license files or
project documentation identify the MIT license. The repository license audit
records those exceptions explicitly.

Third-party names and logos remain the property of their respective owners.
