import Foundation
import WebKit

@MainActor
final class BrowserPopupCoordinator {
    /// Routes a popup destination another application owns into the
    /// external-scheme consent path.
    typealias ExternalSchemeHandOff =
        @MainActor (
            URL,
            BrowserPopupTrigger,
            SiteOrigin?
        ) -> Void

    private let handOffExternalScheme: ExternalSchemeHandOff

    init(handOffExternalScheme: @escaping ExternalSchemeHandOff = { _, _, _ in }) {
        self.handOffExternalScheme = handOffExternalScheme
    }

    /// Resolves one new-window request while WebKit waits. The scheme settles
    /// first. Any other request goes to `offer`, which receives the requested
    /// URL — nil for `window.open()` without a destination — offers the popup
    /// WebKit made to the core and answers its web view once the core adopted
    /// it. The core decides where the popup shows, and the popup runs on its
    /// opener's engine. A refused popup gets no window: nothing here opens a
    /// tab of its own, so one request never becomes two pages.
    func resolveOpen(
        for navigationAction: WKNavigationAction,
        currentURL: URL?,
        offer: (URL?) -> WKWebView?
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        // The scheme settles first, before any page exists. A destination another
        // app owns goes straight to the hand-off consent path, and one nothing may
        // open is dropped — neither leaves a page behind.
        return BrowserPopupSchemeRouting.classify(destinationURL: navigationAction.request.url)
            .resolve(navigationAction, currentURL: currentURL, on: self, offer: offer)
    }

    /// Hands `url`, a popup destination another application owns, to the
    /// external-scheme consent path.
    func handOff(_ url: URL, for navigationAction: WKNavigationAction, currentURL: URL?) {
        handOffExternalScheme(
            url,
            BrowserPopupTrigger.classify(navigationAction.navigationType),
            sourceOrigin(for: navigationAction, currentURL: currentURL)
        )
    }

    /// The origin that asked for the window. WebKit annotates `sourceFrame` as
    /// non-null and every real popup has one, so it is read as an optional purely
    /// so a missing frame falls back to the page the user is looking at instead of
    /// trapping. A frame WebKit reports without a host — `about:blank`, a
    /// sandboxed frame — takes the same fallback, which is the origin a prompt
    /// would name anyway.
    private func sourceOrigin(
        for navigationAction: WKNavigationAction,
        currentURL: URL?
    ) -> SiteOrigin? {
        if let provider = navigationAction
            as? any BrowserNavigationActionSourceOriginProviding
        {
            return provider.browserSourceOrigin
                ?? currentURL.flatMap(SiteOrigin.init(url:))
        }
        let sourceFrame: WKFrameInfo? = navigationAction.sourceFrame
        if let sourceFrame {
            let frameOrigin = SiteOrigin(sourceFrame.securityOrigin)
            if !frameOrigin.host.isEmpty {
                return frameOrigin
            }
        }
        return currentURL.flatMap(SiteOrigin.init(url:))
    }
}
