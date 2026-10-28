import AppKit
import Foundation

/// What Crest contributes to WebKit's own web-content context menu.
///
/// AppKit builds and tears the menu down on the main thread while the
/// right-click is still being handled, so every answer here is synchronous.
@MainActor
protocol BrowserDesktopWebViewMenuHost: BrowserPageContextMenuHost {
    var opensLinksInCurrentSpace: Bool { get }

    /// The content the right-click that is opening this menu landed on.
    ///
    /// Consumes the capture: nil means no fresh page report arrived, and
    /// the same report is never handed to a second menu.
    func takeMenuContext() -> BrowserDesktopWebViewMenuContext?

    /// Starts a person-requested image transfer in this page's WebKit context.
    func downloadImage(from url: URL)

    /// Drops a capture the closing menu never used.
    func discardSplitViewLinkCapture()
}

struct BrowserDesktopWebViewMenuContext: Equatable, Sendable {
    let linkURL: URL?
    let imageDownloadURL: URL?
    let selectionText: String?
    /// Whether the right-click landed in editable content.
    let isEditable: Bool
}
