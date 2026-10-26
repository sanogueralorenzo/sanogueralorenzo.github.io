import Foundation

extension ExitPictureInPicture {
    /// WebKit returns the page's video from Picture in Picture to its place in
    /// the page. A page with no video there keeps its other presentations.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let page = binding.page(pageID), page.engine.hasVideoInPictureInPicture else { return }
        page.webView.closeAllMediaPresentations(completionHandler: {})
    }
}
