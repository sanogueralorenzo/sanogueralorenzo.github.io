import Foundation

/// Everything the sidebar's navigation controls need from the page layer, and
/// nothing else.
///
/// The two shells reach different things — one drives a pool of windowed pages
/// through a session, the other a single compact page through `MobilePageActions`
/// — but the back, forward, and reload controls only ever ask the same eleven
/// questions. Those live here as closures rather than behind a protocol, for the
/// same reason `BrowserSidebarPageAccess` does: there is no third implementation
/// to swap in, only two concrete surfaces each shell binds in its own
/// convenience initializer.
///
/// Every closure reads through its surface at call time rather than capturing a
/// snapshot, so Observation still tracks what the controls touched — the
/// disabled states in particular are read inside a view body and have to
/// invalidate when the page's history changes.
///
/// None of the closures carries an isolation annotation, exactly like
/// `BrowserSidebarUtilityPlatformActions`: annotating them `@MainActor` would
/// also make them `@Sendable`, which the plain function values a View hands over
/// are not. The struct itself is isolated instead.
@MainActor
struct BrowserSidebarNavigationPort {
    /// Whether there is anywhere to go back to.
    let canGoBack: () -> Bool

    /// Whether there is anywhere to go forward to.
    let canGoForward: () -> Bool

    /// The pages behind the current one, nearest first.
    let backHistory: () -> [BrowserNavigationHistoryItem]

    /// The pages ahead of the current one, nearest first.
    let forwardHistory: () -> [BrowserNavigationHistoryItem]

    let goBack: () -> Void

    let goForward: () -> Void

    /// Jumps straight to one entry behind the current page. Spelled apart from
    /// `goBack` because a stored closure cannot be overloaded on its argument
    /// the way the two methods it binds are.
    let goBackToHistoryItem: (BrowserNavigationHistoryItem) -> Void

    let goForwardToHistoryItem: (BrowserNavigationHistoryItem) -> Void

    /// Opens History, which keeps every visit the history menus leave out.
    let showHistory: () -> Void

    /// Whether the current page is still loading, which is what turns the
    /// reload control into a stop control.
    let isLoading: () -> Bool

    /// Whether there is a page to act on at all. Everything but the history
    /// menus is disabled while there is not.
    let hasActivePage: () -> Bool

    /// What the current page is showing, read only to decide whether the
    /// developer reload menu belongs beside the reload control.
    let activeURL: () -> URL?

    /// Reloads, or stops a load already in flight.
    let reloadOrStop: () -> Void

    /// Reloads unconditionally, ignoring a load in flight.
    let reload: () -> Void

    /// Reloads ignoring every cached response.
    let reloadFromOrigin: () -> Void

    /// Clears the site's cookies and storage, then reloads it.
    let clearSiteDataAndReload: () async -> Void
}
