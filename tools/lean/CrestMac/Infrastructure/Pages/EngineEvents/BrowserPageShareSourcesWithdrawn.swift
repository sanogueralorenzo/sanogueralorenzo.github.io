import Foundation

/// The request the offer `shareID` asked about ended first.
struct BrowserPageShareSourcesWithdrawn: BrowserPageEngineEvent {
    // MARK: - Variables

    let shareID: UUID

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        if page.shareSourceOffer?.id == shareID { page.shareSourceOffer = nil }
    }
}
