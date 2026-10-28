import Foundation

extension PageLiveState {
    // MARK: - Variables

    /// The address of the document the page shows.
    var documentURL: URL? { url.flatMap(URL.init(string:)) }

    /// Where a navigation that has not committed is heading.
    var pendingNavigationURL: URL? { pendingURL.flatMap(URL.init(string:)) }

    /// The address the page shows the person, as the core resolved it.
    var displayURL: URL? { address.flatMap(URL.init(string:)) }
}
