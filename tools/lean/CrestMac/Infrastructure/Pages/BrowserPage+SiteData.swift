import Foundation

extension BrowserPage {
    /// Clears what the page's site keeps in `category` in its Space, from
    /// every engine and only from memory in a private window, reloads the
    /// page, then says how it went through `notify`. A page that shows no site
    /// clears nothing.
    func clearSiteData(
        _ category: BrowsingDataCategory,
        notify: @MainActor (BrowserNotice) -> Void = { BrowserNoticeCenter.shared.post($0) }
    ) async {
        guard let cleared = await clearSiteData([category], ephemeral: isPrivateBrowsing) else { return }
        notify(.siteData(category, cleared: cleared))
    }
}
