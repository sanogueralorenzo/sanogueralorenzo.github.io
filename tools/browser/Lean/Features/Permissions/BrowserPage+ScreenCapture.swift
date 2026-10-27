import WebKit

extension BrowserPage {
    // WebKit's browser delegate still presents the native source picker for every granted request.
    @objc(_webView:requestDisplayCapturePermissionForOrigin:initiatedByFrame:withSystemAudio:decisionHandler:)
    func requestDisplayCapture(
        _ view: WKWebView, origin: WKSecurityOrigin, frame: WKFrameInfo,
        withSystemAudio: Bool, decisionHandler: @escaping @MainActor @Sendable (Int) -> Void
    ) {
        Task {
            guard view === webView, let siteController,
                await siteController.decide(.screenCapture, origin: origin, frame: frame)
            else {
                decisionHandler(0)
                return
            }
            if let value = BrowserSiteController.origin(origin) {
                siteController.recordCapture([.screenCapture], origin: value)
            }
            decisionHandler(1)
        }
    }

    @objc(_webView:decidePolicyForScreenCaptureUnmutingForOrigin:initiatedByFrame:decisionHandler:)
    func unmuteDisplayCapture(
        _ view: WKWebView, origin: WKSecurityOrigin, frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        Task { decisionHandler(await siteController?.decide(.screenCapture, origin: origin, frame: frame) == true) }
    }

}
