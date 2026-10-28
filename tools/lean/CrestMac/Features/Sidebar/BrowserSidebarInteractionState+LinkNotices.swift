import Foundation

extension BrowserSidebarInteractionState {
    // MARK: - Actions - Link Feedback

    /// Confirms a link or palette row that opened behind the page the person is using.
    func browserDidOpenBackgroundTab() {
        BrowserNoticeCenter.shared.post(.openedInBackgroundTab)
    }
}
