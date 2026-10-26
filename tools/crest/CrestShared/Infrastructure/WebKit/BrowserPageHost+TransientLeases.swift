import Foundation
import WebKit

// MARK: - Actions - Leases

extension BrowserPageHost {
    /// A lease on a page the core opens in `space` for a transient request
    /// presenting as `presentation`, which loads `url` and rebuilds its page
    /// from `makePage` after memory pressure. Only the first page replays
    /// `engineNavigation`. Nil when the core refuses the page.
    func makeTransientPageLease(
        url: URL, in space: SpaceModel, presentation: TransientPresentation,
        engineNavigation: BrowserEngineNavigation?, balancedContentRuleLists: [WKContentRuleList],
        onUserActivity: @escaping () -> Void, onDownloadOnlyNavigation: (() -> Void)?,
        makePage: @escaping @MainActor () -> BrowserPlatformPage?
    ) -> BrowserPlatformTransientPageLease? {
        // The core decides whether the Space may host a page, for the first
        // page and for every page memory pressure makes the lease rebuild.
        guard let initialPage = makePage() else { return nil }
        if let engineNavigation, !initialPage.pageEngine.stageNavigation(engineNavigation, expecting: url) {
            initialPage.release(keepingState: false)
            return nil
        }
        let lease = BrowserPlatformTransientPageLease(
            page: initialPage, url: url, contentBlockingPolicy: space.settings.browsingPreferences.contentBlocking,
            balancedContentRuleLists: balancedContentRuleLists, rebuild: makePage, userActivity: onUserActivity,
            onDownloadOnlyNavigation: onDownloadOnlyNavigation)
        keep(lease)
        return lease
    }
}
