import Foundation

extension ZoomPage {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.page(pageID).map { $0.webView.pageZoom = CGFloat(factor) } != nil
    }
}
