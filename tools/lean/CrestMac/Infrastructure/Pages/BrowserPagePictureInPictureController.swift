import Foundation

/// The page's PiP lifecycle follows tab presentation, regardless of which
/// engine owns the video and its floating window. The controller asks for
/// automatic entry as its tab leaves the screen, and withdraws a request still
/// pending as the tab returns. A video already floating returns to the page
/// because the core ends it once a window shows the page again.
@MainActor
protocol BrowserPagePictureInPictureController: AnyObject {
    var canRestoreSource: Bool { get }
    var protectsPageResidency: Bool { get }
    func leaveTab()
    func returnToTab()
    func navigationDidCommit()
    func nativePresentationDidChange(isActive: Bool)
    func invalidate()
}

extension BrowserPagePictureInPictureController {
    var canRestoreSource: Bool { false }
    var protectsPageResidency: Bool { false }
    func navigationDidCommit() {}
    func nativePresentationDidChange(isActive: Bool) {}
}
