import Foundation

/// Resolves a tab's address without selecting it or creating a page.
@MainActor
protocol BrowserTabLinkProviding: AnyObject {
    /// The address the tab's resident page shows, or nil when the tab has no
    /// page here for that Space and profile.
    func liveLinkURL(for assignment: BrowserTabRuntimeAssignment) -> URL?
}
