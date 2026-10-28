import AppKit

/// What a shell window's content does with a mouse's Back or Forward button
/// and with a swipe no page took: the content knows its pages and where its
/// sidebar is. `BrowserMacMouseButtons` pairs each press it took with its
/// release, and the window asks it about swipes.
@MainActor
protocol BrowserMacWindowPointerNavigation: AnyObject {
    /// Acts on a press of `action`'s button at `event`, answering whether
    /// Crest took it. One it did not take goes on to the view under the
    /// pointer, with its drags and release.
    func takePress(_ action: BrowserSidebarMouseButtonAction, at event: NSEvent) -> Bool
    /// Acts on a swipe of `action` at `event` as on a press, and over neither
    /// a page nor the sidebar goes back or forward on the window's active
    /// page, answering whether Crest took it.
    func navigate(_ action: BrowserSidebarMouseButtonAction, swipedAt event: NSEvent) -> Bool
}
