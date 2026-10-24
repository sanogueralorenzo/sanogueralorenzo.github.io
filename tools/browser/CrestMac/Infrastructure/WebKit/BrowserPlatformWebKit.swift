/// macOS resolves the shared WebKit platform seam to `BrowserDesktopWebKit`.
///
/// WebKit's binding names this type instead of either platform's, which lets
/// it build pages with whichever platform its target runs on.
typealias BrowserPlatformWebKit = BrowserDesktopWebKit
