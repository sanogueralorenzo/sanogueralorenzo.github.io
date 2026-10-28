import Foundation

extension BrowserPagePool {
    // MARK: - Actions - Screen Sharing

    /// The tab at the other end of the tab sharing `page` takes part in: the
    /// tab it shares, or the tab sharing it. Nil when Crest does not know it,
    /// as for a capture the picker did not start.
    func tabSharingCounterpart(of page: BrowserPage) -> UUID? {
        let counterpart = livePages.first { candidate in
            (page.isSharingTab && page.sharedTabPageIDs.contains(candidate.corePage.id))
                || (page.isSharedAsTab && candidate.isSharingTab
                    && candidate.sharedTabPageIDs.contains(page.corePage.id))
        }
        return counterpart?.navigationContext?.tabID
    }
}
