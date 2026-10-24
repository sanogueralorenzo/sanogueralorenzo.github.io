import SwiftUI

/// Shows each notice a window's chrome asks for at the top of the window, for
/// as long as the notice lasts. A newer notice replaces one still showing.
struct BrowserNoticeLayer: View {
    let chrome: BrowserChromeState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var visibleNotice: BrowserNotice?

    var body: some View {
        ZStack {
            if let visibleNotice {
                BrowserNoticeView(notice: visibleNotice)
                    .id(visibleNotice)
            }
        }
        .zIndex(BrowserRootMetrics.feedbackZIndex)
        .onChange(of: chrome.noticeRevision, initial: true) { _, revision in
            present(revision: revision)
        }
    }

    // MARK: - Actions - Presentation

    private func present(revision: Int) {
        guard revision > 0, let notice = chrome.notice else { return }
        withAnimation(CrestMotion.feedbackPresentation.unlessReducingMotion(reduceMotion)) {
            visibleNotice = notice
        }
        Task { @MainActor in
            try? await Task.sleep(for: notice.duration)
            guard chrome.noticeRevision == revision else { return }
            withAnimation(CrestMotion.dismissal.unlessReducingMotion(reduceMotion)) {
                visibleNotice = nil
            }
        }
    }
}
