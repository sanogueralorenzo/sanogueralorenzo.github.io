import Foundation
import WebKit

/// A site's request for a capability WebKit enforces, answered through the
/// core.
extension BrowserPlatformPage {
    /// Answers WebKit's request that `origin` capture `type` in `webView`,
    /// which only this page's own web view may ask.
    func answerMediaCapture(
        _ type: WKMediaCaptureType, origin: WKSecurityOrigin, in webView: WKWebView,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard webView === webKitEnginePage?.webView,
            let topLevelOrigin = webView.url.flatMap(SiteOrigin.init(url:))
        else {
            decisionHandler(.deny)
            return
        }
        answerPermission(
            SitePermission(type), origin: SiteOrigin(origin), topLevelOrigin: topLevelOrigin, from: webKitEnginePage,
            decisionHandler: decisionHandler)
    }

    /// Answers WebKit's request that `origin`, in `frame` of `webView`, know
    /// the device's location.
    func answerLocation(
        origin: WKSecurityOrigin, frame: WKFrameInfo, in webView: WKWebView,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard frame.webView === webView,
            let topLevelOrigin = webView.url.flatMap(SiteOrigin.init(url:))
        else {
            decisionHandler(.deny)
            return
        }
        answerPermission(
            .location, origin: SiteOrigin(origin), topLevelOrigin: topLevelOrigin, from: webKitEnginePage,
            decisionHandler: decisionHandler)
    }

    /// Answers WebKit's request that `origin`, in a page showing
    /// `topLevelOrigin`, use `permission`. The core answers from the Space's
    /// choices, or asks the person through the page's host. A granted capture
    /// is remembered for this page, so a later block can stop it.
    func answerPermission(
        _ permission: SitePermission, origin: SiteOrigin, topLevelOrigin: SiteOrigin,
        from webKitPage: WebKitEnginePage?,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard let webKitPage else {
            decisionHandler(.deny)
            return
        }
        let question = PermissionQuestion(permission: permission, origin: origin, topLevelOrigin: topLevelOrigin)
        webKitPage.ask(question) { [weak self] grants in
            if grants, permission.isMedia {
                self?.sitePermissionSession.recordMediaGrant(permission, origin: origin)
            }
            decisionHandler(grants ? .grant : .deny)
        }
    }
}
