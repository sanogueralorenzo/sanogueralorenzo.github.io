import WebKit

/// WebKit's public find reports only whether a match was found; it has no
/// match count, so results carry none.
extension WKWebView: BrowserFindExecuting {
    func performFind(
        _ query: String,
        configuration: BrowserFindConfiguration,
        completion: @escaping @MainActor (BrowserFindResult) -> Void
    ) {
        let native = WKFindConfiguration()
        native.backwards = configuration.backwards
        native.caseSensitive = configuration.caseSensitive
        native.wraps = true
        find(query, configuration: native) { result in
            completion(BrowserFindResult(matchFound: result.matchFound))
        }
    }
}
