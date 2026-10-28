import Foundation
import WebKit

extension BrowserExternalSchemeCoordinator {
    /// The origin that asked for the hand-off. A frame WebKit reports without a
    /// host — an `about:blank` or sandboxed frame — falls back to the page the
    /// user is looking at, which is the origin a prompt would name anyway.
    func sourceOrigin(
        for navigationAction: WKNavigationAction,
        currentURL: URL?
    ) -> SiteOrigin? {
        if let provider = navigationAction
            as? any BrowserNavigationActionSourceOriginProviding
        {
            return provider.browserSourceOrigin
                ?? currentURL.flatMap(SiteOrigin.init(url:))
        }
        let frameOrigin = SiteOrigin(navigationAction.sourceFrame.securityOrigin)
        if !frameOrigin.host.isEmpty {
            return frameOrigin
        }
        return currentURL.flatMap(SiteOrigin.init(url:))
    }
}
