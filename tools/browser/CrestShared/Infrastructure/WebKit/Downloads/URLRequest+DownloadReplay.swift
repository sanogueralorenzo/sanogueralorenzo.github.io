import Foundation

extension URLRequest {
    // MARK: - Variables

    /// The request a retry of this blocked download replays, or nil when it
    /// cannot be replayed: anything but HTTP or HTTPS, or a streamed body.
    var replayableDownloadRequest: URLRequest? {
        guard let url,
            ["http", "https"].contains(url.scheme?.lowercased()),
            httpBodyStream == nil
        else { return nil }

        // WKDownload.originalRequest contains WebKit-private, one-shot request
        // properties. Reusing that object after returning nil from the first
        // destination decision makes WebKit cancel the replacement before its
        // delegate can choose a destination. Rebuild only the public network
        // contract needed to replay the request in the same WKWebView session.
        var request = URLRequest(
            url: url,
            cachePolicy: cachePolicy,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = httpMethod
        request.allHTTPHeaderFields = allHTTPHeaderFields
        request.httpBody = httpBody
        request.mainDocumentURL = mainDocumentURL
        request.httpShouldHandleCookies = httpShouldHandleCookies
        request.networkServiceType = networkServiceType
        request.allowsCellularAccess = allowsCellularAccess
        return request
    }
}
