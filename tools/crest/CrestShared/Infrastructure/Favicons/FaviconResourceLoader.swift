import Foundation

/// Native loading is only a public-resource fallback. Authenticated resources
/// belong to the live page's WebKit context, never an exported cookie snapshot.
enum BrowserFaviconResourceLoader {
    struct Resource: Sendable {
        let data: Data
        let mimeType: String?
        let url: URL

        var isImage: Bool {
            mimeType?.hasPrefix("image/") == true || mimeType == "application/octet-stream"
        }
    }

    static let iconAccept = "image/avif,image/webp,image/png,image/svg+xml,image/*,*/*;q=0.5"
    static let manifestAccept = "application/manifest+json,application/json,*/*;q=0.5"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    static func download(
        _ url: URL,
        maximumByteCount: Int,
        accept: String,
        userAgent: String? = nil,
        session requestedSession: URLSession? = nil
    ) async -> Resource? {
        guard let url = publicResourceURL(url) else { return nil }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.httpShouldHandleCookies = false
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let userAgent, !userAgent.isEmpty, userAgent.utf8.count <= 1_024,
            !userAgent.contains("\r"), !userAgent.contains("\n")
        {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        do {
            let (bytes, response) = try await (requestedSession ?? session).bytes(
                for: request, delegate: PublicResourceDelegate()
            )
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse,
                (200..<300).contains(response.statusCode),
                response.expectedContentLength <= maximumByteCount,
                let responseURL = response.url
            else {
                // A response rejected before iteration can leave AsyncBytes'
                // task retained in its session. Finish its response callback
                // in an independent cancellation scope, even if the page left.
                let cleanup = Task {
                    bytes.task.cancel()
                    var iterator = bytes.makeAsyncIterator()
                    _ = try? await iterator.next()
                }
                await cleanup.value
                return nil
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumByteCount, !Task.isCancelled else { return nil }
                data.append(byte)
            }
            guard !data.isEmpty else { return nil }
            return Resource(data: data, mimeType: response.mimeType?.lowercased(), url: responseURL)
        } catch {
            return nil
        }
    }

    private static func publicResourceURL(_ url: URL) -> URL? {
        guard ["http", "https"].contains(url.scheme?.lowercased()),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            components.host != nil
        else { return nil }
        components.user = nil
        components.password = nil
        components.fragment = nil
        return components.url
    }

    private final class PublicResourceDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            guard let url = request.url.flatMap(BrowserFaviconResourceLoader.publicResourceURL) else {
                completionHandler(nil)
                return
            }
            var request = request
            request.url = url
            request.httpShouldHandleCookies = false
            for header in ["Cookie", "Referer", "Authorization", "Proxy-Authorization"] {
                request.setValue(nil, forHTTPHeaderField: header)
            }
            completionHandler(request)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                completionHandler(.performDefaultHandling, nil)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}
