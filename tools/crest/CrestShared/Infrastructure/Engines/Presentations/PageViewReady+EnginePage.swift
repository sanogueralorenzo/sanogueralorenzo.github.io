import Foundation

extension PageViewReady {
    @MainActor func deliver(to page: EnginePage) {
        // Chromium clears isolated zoom when a document commits. These
        // presentations arrive after its navigation observers have finished,
        // so restore the page's own default or manual override at that point.
        // A recovered view and an engine-rendered error page need it too.
        page.restoreRequestedZoom()
    }
}
