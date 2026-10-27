# Crest

A native macOS browser built with SwiftUI, AppKit, and WebKit.
Spaces have separate website sessions; private Spaces stay in memory.
The hover sidebar contains pins, saved tabs, folders, GitHub live folders,
and compact media controls. Split views, translation, content blocking,
Reader Mode, downloads, history, Archive, and browser import/export are included.

## Build

Requires Apple silicon, macOS 26.1+, Xcode, and XcodeGen (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project Crest.xcodeproj -scheme Crest -configuration Release build
```

Open `Crest.xcodeproj` to build and run in Xcode.
Local builds use ad hoc signing and require no .NET, package downloads, or engine build.
Passkeys require an Apple-authorized browser signing profile and
`CODE_SIGN_ENTITLEMENTS=Config/Browser.entitlements`; local builds show their availability in Settings.

## Browsing

Reveal the sidebar within 32 points of the left edge; empty Spaces keep it visible.
Use ⌘L for addresses and commands, ⌘T for a new tab, ⌃Tab for recent tabs,
and ⌥⌘←/→ to switch Spaces. On saved tabs, ⌘W returns to the saved address,
then sleeps the page and selects another loaded tab.
Background pages unload after five idle minutes, protecting media and unsaved edits.

Session checkpoints live in `~/Library/Application Support/Crest/SwiftSession`.
A validated previous checkpoint supports recovery from a damaged write.
For isolated review builds, set `CREST_REVIEW_DATA_DIRECTORY` to a disposable directory
and use a distinct bundle identifier; never launch fixtures against a personal session.

Source is [MPL-2.0](LICENSE), derived from [Crest](https://github.com/pauljoda/Crest).
See [third-party notices](THIRD_PARTY_NOTICES.md) and [trademark terms](TRADEMARKS.md).
