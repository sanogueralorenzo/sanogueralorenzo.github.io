import UIKit
import WebKit

/// UIKit owns the context-menu gestures and source animations. This controller
/// supplies only the visual page, using the originating profile and content rules.
@MainActor
final class MobileBrowserLinkPreviewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let url: URL
    private let isCurrent: () -> Bool

    init(url: URL, source: WKWebView, isCurrent: @escaping () -> Bool) {
        self.url = url
        self.isCurrent = isCurrent
        let configuration = source.configuration.copy() as! WKWebViewConfiguration
        configuration.preferences = source.configuration.preferences.copy() as! WKPreferences
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isUserInteractionEnabled = false
        webView.allowsLinkPreview = false
        webView.customUserAgent = source.customUserAgent
        webView.pageZoom = source.pageZoom
        preferredContentSize = CGSize(
            width: min(source.bounds.width, 600), height: min(source.bounds.height, 600)
        )
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = webView
        guard isCurrent() else { return }
        webView.load(URLRequest(url: url))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        webView.stopLoading()
        webView.setAllMediaPlaybackSuspended(true)
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard isCurrent(), !action.shouldPerformDownload, action.targetFrame != nil,
            let url = action.request.url,
            ExternalWebLink.accepts(url)
                || (action.targetFrame?.isMainFrame == false && url.scheme == "about")
        else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition =
            (response.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        decisionHandler(
            isCurrent() && response.canShowMIMEType && !disposition.hasPrefix("attachment") ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // A visual preview cannot ask for credentials or accept a certificate exception.
        completionHandler(
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                ? .performDefaultHandling : .cancelAuthenticationChallenge,
            nil
        )
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void
    ) {
        completionHandler()
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        completionHandler(false)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        completionHandler(nil)
    }

    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    @available(iOS 27.0, *)
    func webView(
        _ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }
}
