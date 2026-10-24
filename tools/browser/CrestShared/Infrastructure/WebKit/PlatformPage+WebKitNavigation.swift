import Foundation
import WebKit

/// The page's navigation gates that read WebKit's own navigation objects.
extension BrowserPlatformPage {
    /// The WebKit port behind this page, or nil when another engine hosts it.
    var webKitEngine: BrowserWebKitPageEngine? { (pageEngine as any BrowserPageEngine) as? BrowserWebKitPageEngine }

    /// Tells the core WebKit ended the page's web content process. The core
    /// decides whether WebKit reloads it now, once a window shows it, or
    /// whether the page shows the failure.
    func reportWebContentProcessStopped() {
        corePage.report(
            PageCrashed(
                pageID: corePage.id, domain: WKError.errorDomain,
                code: Int64(WKError.Code.webContentProcessTerminated.rawValue)))
    }

    /// True when Crest, not web content, asked for this navigation. Two signals
    /// answer that: the exact URL Crest last passed to `load(_:)`, which web
    /// content never reaches, and a source frame that is not a web document —
    /// WebKit reports an empty origin for a load the app started against a web
    /// view with no page yet, and a `file:` origin for a local document's own
    /// links. Only such a navigation may reach a `file:` URL.
    func isAppInitiated(_ navigationAction: WKNavigationAction) -> Bool {
        if let appInitiatedURL, navigationAction.request.url == appInitiatedURL {
            return true
        }
        if let sourceOriginProvider = navigationAction as? any BrowserNavigationActionSourceOriginProviding {
            guard let origin = sourceOriginProvider.browserSourceOrigin else {
                return false
            }
            if origin.scheme.isEmpty, origin.host.isEmpty {
                return true
            }
            return origin.scheme == "file"
        }
        let origin = navigationAction.sourceFrame.securityOrigin
        let scheme = origin.protocol.lowercased()
        if scheme.isEmpty, origin.host.isEmpty {
            return true
        }
        return scheme == "file"
    }

    func isCurrentNavigation(_ navigation: WKNavigation?) -> Bool {
        // WebKit can deliver a callback late, after its navigation finished or
        // was replaced. An identified navigation is only current while it is
        // still the active one, so a stale failure cannot paint an error over a
        // page that already loaded. Callbacks that identify no navigation stay
        // accepted because WebKit reports unattributed loads that way.
        guard let navigation else { return true }
        return activeNavigation === navigation
    }
}
