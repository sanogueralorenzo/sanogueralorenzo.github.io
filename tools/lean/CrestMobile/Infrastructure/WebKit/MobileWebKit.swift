import UIKit
import WebKit

/// What only iPhone and iPad WebKit pages need, which WebKit's binding applies
/// as it builds a page: the presentation WebKit recommends, inline media that
/// waits for the person, and the web view.
@MainActor
enum MobileWebKit {
    // MARK: - Static Variables

    static let preferredContentMode = WKWebpagePreferences.ContentMode.recommended

    /// Keeps every video, including ones a page adds later, playing inline
    /// rather than taking over the screen.
    static let inlineVideoScript = WKUserScript(
        source: """
            (() => {
              const keepInline = (root) => {
                if (root instanceof HTMLVideoElement) {
                  root.setAttribute('playsinline', '');
                  root.setAttribute('webkit-playsinline', '');
                }
                root.querySelectorAll?.('video').forEach((video) => {
                  video.setAttribute('playsinline', '');
                  video.setAttribute('webkit-playsinline', '');
                });
              };

              keepInline(document);
              new MutationObserver((records) => {
                records.forEach((record) => {
                  record.addedNodes.forEach((node) => {
                    if (node instanceof Element) keepInline(node);
                  });
                });
              }).observe(document.documentElement, { childList: true, subtree: true });
            })();
            """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    // MARK: - Actions - Pages

    /// Adds the mobile media policy to a new page's configuration, on top of
    /// the settings both platforms share: the inactive scheduling policy above
    /// all, which lets WebKit suspend a resident background tab on the
    /// platform that jetsams.
    static func decorate(_ configuration: WKWebViewConfiguration) {
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.addUserScript(inlineVideoScript)
    }

    /// The web view over `configuration`, one the binding assembled or one
    /// WebKit made for a popup.
    static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        return webView
    }
}
