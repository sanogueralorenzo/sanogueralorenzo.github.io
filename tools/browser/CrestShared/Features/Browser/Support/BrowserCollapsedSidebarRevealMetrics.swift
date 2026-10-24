import CoreGraphics

/// The leading-edge strip that brings a collapsed sidebar back, resolved once
/// per shell rather than spelled out by each fork of the control.
///
/// Everything the strip claims is taken from the page underneath it, so a shell
/// reserves the least its inputs need and no more. On touch, the middle of the
/// edge stays the page's, where a swipe in goes back or forward.
struct BrowserCollapsedSidebarRevealMetrics: Equatable, Sendable {
    /// How much of the leading edge the strip occupies.
    let width: CGFloat

    /// How far a finger travels inward before the strip reads it as a reveal,
    /// or `nil` where the shell has no edge swipe to spend.
    let swipeDistance: CGFloat?

    /// Whether a pointer resting on the strip is enough on its own.
    let revealsOnHover: Bool

    /// The share of the strip's height, centred on the edge, that the strip
    /// leaves to the page: a swipe in there steps the page's history, and only
    /// the top and bottom of the edge bring the sidebar back.
    let pageNavigationShare: CGFloat

    /// A pointer shell: a strip only as wide as a cursor needs, answering a
    /// pointer that comes to rest on it.
    static let pointer = BrowserCollapsedSidebarRevealMetrics(
        width: 14,
        swipeDistance: nil,
        revealsOnHover: true,
        pageNavigationShare: 0
    )

    /// A touch shell: a strip wide enough to aim a finger at, opened by an
    /// inward swipe at the top or bottom of the edge.
    ///
    /// Hover is deliberately unspent here even where a trackpad is attached.
    /// The same strip still has to answer a finger, and a pointer brushing the
    /// leading edge on its way into the page would otherwise throw the sidebar
    /// over whatever it was reaching for.
    static let touch = BrowserCollapsedSidebarRevealMetrics(
        width: 26,
        swipeDistance: 10,
        revealsOnHover: false,
        pageNavigationShare: 0.5
    )

    /// The profile a shell reserves its strip with.
    ///
    /// Touch decides it, for the same reason it decides the sidebar's rows: the
    /// strip is a hit target before it is anything else, so it follows the
    /// least precise input the shell accepts.
    static func resolve(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserCollapsedSidebarRevealMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }
}
