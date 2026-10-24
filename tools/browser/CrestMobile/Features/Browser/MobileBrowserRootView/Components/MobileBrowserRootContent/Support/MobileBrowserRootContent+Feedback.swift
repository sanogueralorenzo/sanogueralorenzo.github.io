import SwiftUI

extension MobileBrowserRootContent {
    func presentURLCopyFeedback(revision: Int) {
        guard revision > 0 else { return }
        withAnimation(chromeAnimation(CrestMotion.feedbackPresentation)) {
            visiblePageZoomFeedbackLabel = nil
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

    func presentPageZoomFeedback(revision: Int) {
        guard revision > 0 else { return }
        withAnimation(chromeAnimation(CrestMotion.feedbackPresentation)) {
            isURLCopiedFeedbackVisible = false
            visiblePageZoomFeedbackLabel = pages.pageZoomFeedbackLabel
        }
        Task { @MainActor in
            try? await Task.sleep(
                for: MobileBrowserRootLayout.feedbackVisibilityDuration
            )
            guard pages.pageZoomFeedbackRevision == revision else { return }
            withAnimation(chromeAnimation(CrestMotion.dismissal)) {
                visiblePageZoomFeedbackLabel = nil
            }
        }
    }

    func commitRegularSidebarWidth(_ width: CGFloat) {
        guard let committedWidth = model.commitSidebarWidth(width) else { return }
        storedRegularSidebarWidth = Double(committedWidth)
    }
}
