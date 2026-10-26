/// Mobile resolves the shared page seam to the UIKit-hosted `MobileBrowserPage`.
///
/// Shared code names this type instead of either concrete page, which lets one
/// extension or collaborator compile against whichever page its target owns.
typealias BrowserPlatformPage = MobileBrowserPage
