import SwiftUI

extension MobileBrowserRootContent {
    func presentURLCopyFeedback(revision: Int) {
        guard revision > 0 else { return }
        withAnimation(chromeAnimation(CrestMotion.feedbackPresentation)) {
            visiblePageFeedback = nil
            isURLCopiedFeedbackVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(
                for: MobileBrowserRootLayout.feedbackVisibilityDuration
            )
            guard pages.urlCopyFeedbackRevision == revision else { return }
            withAnimation(chromeAnimation(CrestMotion.dismissal)) {
                isURLCopiedFeedbackVisible = false
            }
        }
    }

    func presentPageFeedback(revision: Int) {
        guard revision > 0 else { return }
        withAnimation(chromeAnimation(CrestMotion.feedbackPresentation)) {
            isURLCopiedFeedbackVisible = false
            visiblePageFeedback = pages.pageFeedback
        }
        Task { @MainActor in
            try? await Task.sleep(
                for: MobileBrowserRootLayout.feedbackVisibilityDuration
            )
            guard pages.pageFeedbackRevision == revision else { return }
            withAnimation(chromeAnimation(CrestMotion.dismissal)) {
                visiblePageFeedback = nil
            }
        }
    }

    func commitRegularSidebarWidth(_ width: CGFloat) {
        guard let committedWidth = model.commitSidebarWidth(width) else { return }
        storedRegularSidebarWidth = Double(committedWidth)
    }
}
