import Foundation
import Network
import WebKit

/// Read-only requests over one origin's cookies in one WebKit profile. No web
/// view, shared cookie storage, HTTP-auth credentials or disk cache is involved.
@MainActor
final class BrowserGitHubSession {
    // MARK: - Types

    private struct CookieState: Equatable {
        let name: String
        let domain: String
        let path: String
        let value: String
        let expires: Date?
        let secure: Bool
        let httpOnly: Bool
        let sameSite: HTTPCookieStringPolicy?

        init(_ cookie: HTTPCookie) {
            name = cookie.name
            domain = cookie.domain
            path = cookie.path
            value = cookie.value
            expires = cookie.expiresDate
            secure = cookie.isSecure
            httpOnly = cookie.isHTTPOnly
            sameSite = cookie.sameSitePolicy
        }
    }

    // MARK: - Variables

    private static let host = "github.com"
    private static let dashboard = URL(string: "https://\(host)/pulls")!
    private var revision = 0
    private var store: WKWebsiteDataStore?
    private let isAuthorized: @MainActor () -> Bool
    private var knownCookies: [CookieState]?
    private var requests: [UUID: URLSession] = [:]
    private var stopped = false
    private var writingCookies = false
    private var observation: Task<Void, Never>?
    private let observer = CookieObserver()

    // MARK: - Initializers

    init(store: WKWebsiteDataStore, isAuthorized: @escaping @MainActor () -> Bool) {
        self.store = store
        self.isAuthorized = isAuthorized
        observer.owner = self
        store.httpCookieStore.add(observer)
    }

    deinit {
        observation?.cancel()
        for session in requests.values { session.invalidateAndCancel() }
        Task { @MainActor [store, observer] in store?.httpCookieStore.remove(observer) }
    }

    // MARK: - Actions - Requests

    func fetchPullRequests(query: String? = nil) async throws -> Data {
        let url =
            query.map {
                Self.dashboard.appending(queryItems: [URLQueryItem(name: "q", value: $0)])
            } ?? Self.dashboard
        try checkAuthorization()
        let cookies = await scopedCookies()
        try checkAuthorization()
        let state = cookies.map(CookieState.init)
        if let knownCookies, knownCookies != state { changed(to: state) }
        knownCookies = state
        let generation = revision
        let settings = URLSessionConfiguration.ephemeral
        settings.proxyConfigurations = store?.proxyConfigurations ?? []
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.urlCredentialStorage = nil
        settings.urlCache = nil
        settings.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        settings.timeoutIntervalForRequest = 15
        settings.timeoutIntervalForResource = 30
        let session = URLSession(configuration: settings)
        let id = UUID()
        requests[id] = session
        defer {
            session.invalidateAndCancel()
            requests[id] = nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("application/json,text/html", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let eligible = cookies.filter { cookie in
            let path = url.path.isEmpty ? "/" : url.path
            return path == cookie.path || path.hasPrefix(cookie.path.hasSuffix("/") ? cookie.path : cookie.path + "/")
        }.sorted { $0.path.count > $1.path.count }
        for (header, value) in HTTPCookie.requestHeaderFields(with: eligible) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        let (bytes, response) = try await session.bytes(for: request, delegate: RequestDelegate())
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, response.url == url,
            response.expectedContentLength <= 5 * 1_024 * 1_024
        else { throw BrowserGitHubFailure.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            if data.count.isMultiple(of: 8_192) {
                try checkAuthorization()
                guard revision == generation else { throw BrowserGitHubFailure.notSignedIn }
            }
            guard data.count < 5 * 1_024 * 1_024 else { throw BrowserGitHubFailure.invalidResponse }
            data.append(byte)
        }
        try await validate()
        guard revision == generation else { throw BrowserGitHubFailure.notSignedIn }
        try await acceptCookies(from: response, expecting: state)
        if (300..<400).contains(response.statusCode) || [401, 404].contains(response.statusCode) {
            throw BrowserGitHubFailure.notSignedIn
        }
        guard response.statusCode == 200 else { throw BrowserGitHubFailure.unavailable }
        return data
    }

    func validate() async throws {
        try checkAuthorization()
        let current = await scopedCookies().map(CookieState.init)
        try checkAuthorization()
        if let knownCookies, knownCookies != current {
            changed(to: current)
            throw BrowserGitHubFailure.notSignedIn
        }
        knownCookies = current
    }

    func invalidate() {
        guard !stopped else { return }
        stopped = true
        revision &+= 1
        observation?.cancel()
        store?.httpCookieStore.remove(observer)
        store = nil
        for session in requests.values { session.invalidateAndCancel() }
        requests = [:]
        knownCookies = nil
    }

    // MARK: - Actions - Cookies

    func isSignedIn() async -> Bool {
        guard let store else { return false }
        return await store.httpCookieStore.allCookies().contains {
            Self.belongsToGitHub($0) && $0.name == "logged_in" && $0.value == "yes"
        }
    }

    private func cookiesChanged() {
        guard !stopped, !writingCookies else { return }
        observation?.cancel()
        observation = Task { [weak self] in
            guard let self else { return }
            let current = await scopedCookies().map(CookieState.init)
            guard !Task.isCancelled, !stopped, !writingCookies else { return }
            if let knownCookies, knownCookies != current { changed(to: current) }
        }
    }

    private func changed(to cookies: [CookieState]) {
        knownCookies = cookies
        revision &+= 1
        for session in requests.values { session.invalidateAndCancel() }
    }

    private func scopedCookies() async -> [HTTPCookie] {
        guard let store, await allowsCookies() else { return [] }
        let cookies = await store.httpCookieStore.allCookies()
        return cookies.filter { cookie in
            Self.belongsToGitHub(cookie) && (cookie.expiresDate.map { $0 > Date() } ?? true)
        }.sorted { ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name) }
    }

    private func acceptCookies(from response: HTTPURLResponse, expecting baseline: [CookieState]) async throws {
        guard let store, let url = response.url, await allowsCookies() else { return }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
        }
        let updates = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).filter(Self.belongsToGitHub)
        guard !updates.isEmpty else { return }
        try await validate()
        guard knownCookies == baseline else { throw BrowserGitHubFailure.notSignedIn }
        writingCookies = true
        defer { writingCookies = false }
        for cookie in updates {
            try checkAuthorization()
            if cookie.expiresDate.map({ $0 <= Date() }) == true {
                await store.httpCookieStore.deleteCookie(cookie)
            } else {
                await store.httpCookieStore.setCookie(cookie)
            }
        }
        knownCookies = await scopedCookies().map(CookieState.init)
        try checkAuthorization()
    }

    private func allowsCookies() async -> Bool {
        guard let store else { return false }
        return await withCheckedContinuation { continuation in
            store.httpCookieStore.getCookiePolicy { continuation.resume(returning: $0 == .allow) }
        }
    }

    private func checkAuthorization() throws {
        try Task.checkCancellation()
        guard !stopped, isAuthorized() else { throw CancellationError() }
    }

    private static func belongsToGitHub(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
        return domain == host || domain == "." + host
    }

    // MARK: - Types - Engine callbacks

    private final class CookieObserver: NSObject, WKHTTPCookieStoreObserver {
        weak var owner: BrowserGitHubSession?
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { owner?.cookiesChanged() }
    }

    private final class RequestDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            completionHandler(
                challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                    ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }
    }
}
