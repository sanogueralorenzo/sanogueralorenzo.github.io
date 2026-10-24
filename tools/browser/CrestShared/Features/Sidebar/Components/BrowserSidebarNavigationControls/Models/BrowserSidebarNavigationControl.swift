import Foundation

/// One direction of page history in the sidebar strip: its chevron, its
/// labels, and the port calls that ask about and walk that direction. The
/// history control reads them instead of switching over directions.
struct BrowserSidebarNavigationControl: Hashable, Sendable {
    // MARK: - Variables

    static let back = BrowserSidebarNavigationControl(
        name: "back", systemImage: "chevron.left", accessibilityLabel: "Back",
        accessibilityIdentifier: "browser-back-control", tooltip: "Back (⌘[)", emptyHistoryTitle: "No Earlier Pages",
        isAvailable: { $0.canGoBack() }, history: { $0.backHistory() }, navigate: { $0.goBack() },
        navigateToItem: { $0.goBackToHistoryItem($1) })
    static let forward = BrowserSidebarNavigationControl(
        name: "forward", systemImage: "chevron.right", accessibilityLabel: "Forward",
        accessibilityIdentifier: "browser-forward-control", tooltip: "Forward (⌘])",
        emptyHistoryTitle: "No Later Pages",
        isAvailable: { $0.canGoForward() }, history: { $0.forwardHistory() }, navigate: { $0.goForward() },
        navigateToItem: { $0.goForwardToHistoryItem($1) })

    let name: String
    let systemImage: String
    let accessibilityLabel: LocalizedStringResource
    let accessibilityIdentifier: String

    /// The tooltip, with the keyboard equivalent every shell that has a
    /// keyboard honors.
    let tooltip: LocalizedStringResource

    let emptyHistoryTitle: LocalizedStringResource

    /// Whether there is anywhere to go in this direction.
    let isAvailable: @MainActor @Sendable (BrowserSidebarNavigationPort) -> Bool

    /// The pages in this direction, nearest first.
    let history: @MainActor @Sendable (BrowserSidebarNavigationPort) -> [BrowserNavigationHistoryItem]

    let navigate: @MainActor @Sendable (BrowserSidebarNavigationPort) -> Void

    /// Jumps straight to one entry in this direction.
    let navigateToItem: @MainActor @Sendable (BrowserSidebarNavigationPort, BrowserNavigationHistoryItem) -> Void

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarNavigationControl, rhs: BrowserSidebarNavigationControl) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
