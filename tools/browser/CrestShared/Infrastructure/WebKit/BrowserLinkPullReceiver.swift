import WebKit

/// Takes what a page's link-pull bridge reports, one method per phase it acts
/// on.
@MainActor
protocol BrowserLinkPullReceiver: AnyObject {
    /// A frame's document is ready to report pulls.
    func ready(_ message: BrowserLinkPullMessage, from frame: WKFrameInfo)
    /// A frame's document went away.
    func retire(_ message: BrowserLinkPullMessage)
    /// The person began pulling a link.
    func begin(_ message: BrowserLinkPullMessage)
}
