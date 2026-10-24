import AppKit

/// The page inside a Split View card, as WebKit already has it drawn.
///
/// A carried card has to read as the page it is, and the page is a `WKWebView`
/// that can only ever be in one place at a time — so what travels on the pointer
/// is a picture of it. Taking that picture is asynchronous and the carry is not:
/// the card is already moving by the time the answer arrives, and the image
/// crossfades in behind the pointer rather than gating the pickup on WebKit.
///
/// Deliberately not `async`. The request has to be *issued* inside the mouse-down
/// that started the pickup, before the row is told anything, and an `async`
/// entry point cannot promise that: awaiting it from a `Task` puts a main-actor
/// hop between the press and the request, and the row redraws in that hop. The
/// completion-handler form issues the request on the spot and answers whenever
/// WebKit is ready, which is the ordering the carry actually needs.
///
/// Measured on macOS 27 with a real window: a viewport-sized snapshot answers in
/// 0–2 ms and is unaffected by the card's presentation — an opacity of zero on
/// the hosting view, an opaque sibling drawn over it, a child window above it,
/// and a window ordered off screen entirely all still return the page's own
/// pixels. WebKit captures the renderer, not the screen. The only configuration
/// that returns a blank image is a degenerate `rect`, which is why this passes
/// none.
@MainActor
enum BrowserSplitCardSnapshotLoader {
    /// Asks for the card's current rendering and delivers it when WebKit answers,
    /// or delivers `nil` when it has none to give.
    ///
    /// `afterScreenUpdates` is off deliberately: a carry wants the frame somebody
    /// is looking at, not a fresh paint of it. The default configuration
    /// snapshots the visible viewport at its own size, which is the card the
    /// preview is drawn at.
    static func snapshot(
        of page: BrowserPage,
        then deliver: @escaping @MainActor (NSImage?) -> Void
    ) {
        page.captureViewport(completion: deliver)
    }
}
