# Browser

![Browser — open sidebar, tabs, and abstract split browsing illustration](docs/banner.png)

A native macOS browser with separate Spaces for work and personal browsing.
Built with SwiftUI, AppKit, and WebKit.

[itsbrowser.com](https://itsbrowser.com)

- **Spaces** keep website sessions separate. Private Spaces stay in memory.
- **Sidebar** keeps pins, saved tabs, folders, GitHub live folders, and media controls together.
- **Browsing** includes split views, translation, Reader Mode, downloads, and history with recently closed tabs.
- **Content blocking** includes uBlock Origin Lite, with Complete mode and settings for each Space.

**Build and run** (Apple silicon, macOS 26.1+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```sh
cd browser
brew install xcodegen
xcodegen generate
xcodebuild -project Browser.xcodeproj -scheme Browser -configuration Release build
```

Open `Browser.xcodeproj` in Xcode to run the app. Local builds use ad hoc signing.
Passkeys require an Apple-authorized browser signing profile with
`CODE_SIGN_ENTITLEMENTS=Config/Browser.entitlements`.

## Everyday use

The sidebar opens when no tab is selected. While browsing, move to the left edge to reveal it
or use **⌥⌘S** to keep it open. Drag its right edge to resize it.
Use **⌘L** for addresses and commands, **⌘T** for a new tab, **⌃Tab** for recent tabs,
and **⌥⌘←/→** to switch Spaces. Swipe over a page to go back or forward,
or over the sidebar to switch Spaces.

Settings controls page zoom, content blocking, and data retention.
Browser saves the session atomically to `~/Library/Application Support/Browser/SwiftSession/session.json`.
For isolated review builds, set `BROWSER_REVIEW_DATA_DIRECTORY`
to a disposable directory and use a distinct bundle identifier.

Browser downloads and prepares the latest stable uBlock Origin Lite release from upstream
before loading pages on first launch.
Later stable updates download in the background and apply before browsing on the next launch.

## Command line

With Browser open, symlink its executable to `browser` in a directory on your `PATH`
or invoke `/Applications/Browser.app/Contents/MacOS/Browser --cli`.

```sh
ln -s /Applications/Browser.app/Contents/MacOS/Browser ~/.local/bin/browser
browser spaces create Research Reading Travel
browser tabs open https://example.com --space Research
browser --help
```

Commands return JSON and work with regular Spaces. Tab close requests use Browser’s usual closing safeguards.

Source is [MPL-2.0](LICENSE), derived from [Crest](https://github.com/pauljoda/Crest).
See [third-party notices](THIRD_PARTY_NOTICES.md) and [trademark terms](TRADEMARKS.md).
