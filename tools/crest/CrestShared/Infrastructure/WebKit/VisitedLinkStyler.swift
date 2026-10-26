import Foundation
import WebKit

@MainActor
enum BrowserVisitedLinkStyler {
    nonisolated private static let maximumVisitedURLCount = 5_000
    private static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.visited-links"
    )

    nonisolated static func supports(_ pageURL: URL) -> Bool {
        guard let scheme = pageURL.scheme?.lowercased(), pageURL.host() != nil else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    nonisolated static func normalizedVisitedURLStrings(
        _ history: [HistoryEntryState]
    ) -> [String] {
        // The core names the address history keeps for each entry, and none
        // for one it does not keep, such as a local file, in one call.
        let addresses = history.prefix(maximumVisitedURLCount).map(\.url)
        let kept = (try? CrestCore.answer(HistoryAddresses(addresses: addresses)))?.normalized ?? []
        return kept.compactMap { $0 }
    }

    static func apply(
        history: [HistoryEntryState],
        to webView: WKWebView
    ) async {
        guard let pageURL = webView.url, supports(pageURL) else { return }
        #if os(macOS)
            guard let store = BrowserNativeVisitedLinkStore(webView: webView) else {
                return
            }
            let visitedURLStrings = normalizedVisitedURLStrings(history)
            store.replace(with: visitedURLStrings.compactMap(URL.init(string:)))
            let pageURLVariants = await matchingPageURLVariants(
                visitedURLStrings: visitedURLStrings,
                in: webView
            )
            store.add(pageURLVariants)
        #endif
    }

    #if os(macOS)
        #if DEBUG
            static func containsVisitedURL(_ url: URL, in webView: WKWebView) -> Bool {
                BrowserNativeVisitedLinkStore(webView: webView)?.contains(url) == true
            }
        #endif

        private static func matchingPageURLVariants(
            visitedURLStrings: [String],
            in webView: WKWebView
        ) async -> [URL] {
            guard
                let result = try? await webView.callAsyncJavaScript(
                    pageURLVariantScript,
                    arguments: ["visitedURLs": visitedURLStrings],
                    in: nil,
                    contentWorld: contentWorld
                ) as? [String]
            else { return [] }
            return result.compactMap(URL.init(string:))
        }

        private static let pageURLVariantScript = #"""
            const normalized = (rawValue) => {
              try {
                const url = new URL(rawValue, document.baseURI);
                const labels = url.hostname.toLowerCase().split('.');
                const googleIndex = labels.lastIndexOf('google');
                const googlePrefix = labels.slice(0, googleIndex);
                const googleSuffixCount = labels.length - googleIndex - 1;
                const isGoogleRedirect = googleIndex >= 0
                  && (googlePrefix.length === 0
                    || googlePrefix.every((label) => label === 'www'))
                  && googleSuffixCount >= 1
                  && googleSuffixCount <= 2
                  && url.pathname === '/url';
                if (isGoogleRedirect) {
                  const destination = url.searchParams.get('q') || url.searchParams.get('url');
                  if (destination) return normalized(destination);
                }
                if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
                url.hash = '';
                return url.href;
              } catch (_) {
                return null;
              }
            };

            const normalizedVisitedURLs = new Set(
              visitedURLs.map(normalized).filter(Boolean)
            );
            return Array.from(document.querySelectorAll('a[href]'))
              .map((link) => ({
                destination: normalized(link.href),
                source: link.href
              }))
              .filter(({ destination, source }) =>
                destination !== source && normalizedVisitedURLs.has(destination)
              )
              .map(({ source }) => source);
            """#
    #endif
}

#if os(macOS)
    /// Runtime access to WebKit's native visited-link store.
    ///
    /// WKWebView does not publish this browser-facing facility. Crest's directly
    /// distributed macOS app already resolves WebKit browser SPI defensively;
    /// keeping it out of the iOS build preserves App Store compatibility there.
    @MainActor
    private struct BrowserNativeVisitedLinkStore {
        private typealias ContainsVisitedLink =
            @convention(c) (
                AnyObject,
                Selector,
                NSURL
            ) -> Bool

        private static let storeSelector = NSSelectorFromString("_visitedLinkStore")
        private static let addSelector = NSSelectorFromString("addVisitedLinkWithURL:")
        private static let containsSelector = NSSelectorFromString("containsVisitedLinkWithURL:")
        private static let removeAllSelector = NSSelectorFromString("removeAll")

        private let store: NSObject

        init?(webView: WKWebView) {
            let configuration = webView.configuration
            guard configuration.responds(to: Self.storeSelector),
                let store = configuration.perform(Self.storeSelector)?.takeUnretainedValue()
                    as? NSObject,
                store.responds(to: Self.addSelector),
                store.responds(to: Self.containsSelector),
                store.responds(to: Self.removeAllSelector)
            else { return nil }
            self.store = store
        }

        func replace(with urls: [URL]) {
            store.perform(Self.removeAllSelector)
            add(urls)
        }

        func add(_ urls: [URL]) {
            for url in urls {
                store.perform(Self.addSelector, with: url as NSURL)
            }
        }

        func contains(_ url: URL) -> Bool {
            let implementation = store.method(for: Self.containsSelector)
            let contains = unsafeBitCast(implementation, to: ContainsVisitedLink.self)
            return contains(store, Self.containsSelector, url as NSURL)
        }
    }
#endif
