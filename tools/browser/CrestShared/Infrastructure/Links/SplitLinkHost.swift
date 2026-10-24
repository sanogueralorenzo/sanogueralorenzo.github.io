import Foundation

/// Split-level link operations a page needs from whatever owns its tabs. Both
/// are synchronous because AppKit is building a context menu on the main thread
/// when it asks, and a menu cannot wait for an answer.
@MainActor
struct BrowserSplitLinkHost {
    var canOpenLink: (UUID, BrowserSpaceRuntimeAssignment) -> Bool
    /// Opens the link as a new tab beside the tab it came from, presenting as
    /// one split, and answers the new tab.
    var openLink: (URL, UUID, BrowserSpaceRuntimeAssignment) -> UUID?

    init(
        canOpenLink: @escaping (UUID, BrowserSpaceRuntimeAssignment) -> Bool,
        openLink: @escaping (URL, UUID, BrowserSpaceRuntimeAssignment) -> UUID?
    ) {
        self.canOpenLink = canOpenLink
        self.openLink = openLink
    }

    /// Offers no split at all. Pools built without a store (tests, previews)
    /// simply leave the menu item out.
    static let unavailable = BrowserSplitLinkHost(
        canOpenLink: { _, _ in false },
        openLink: { _, _, _ in nil }
    )
}
