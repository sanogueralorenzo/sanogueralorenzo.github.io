/// macOS resolves the shared page seam to the AppKit-hosted `BrowserPage`.
///
/// Shared code names this type instead of either concrete page, which lets one
/// extension or collaborator compile against whichever page its target owns.
typealias BrowserPlatformPage = BrowserPage
