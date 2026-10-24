import Foundation

extension StopLoading {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.page(pageID).map { $0.webView.stopLoading() } != nil
    }
}
