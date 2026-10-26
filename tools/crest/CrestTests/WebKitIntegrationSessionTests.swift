import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class WebKitIntegrationSessionTests: XCTestCase {
    private let origin = URL(string: "https://github.com")!

    override func tearDown() {
        IntegrationURLProtocol.control.reset()
        super.tearDown()
    }

    func testRequestsUseOnlyOwningProfileCookiesWithoutAnyWebView() async throws {
        let first = WKWebsiteDataStore.nonPersistent()
        let second = WKWebsiteDataStore.nonPersistent()
        await first.httpCookieStore.setCookie(cookie("session", value: "first"))
        await first.httpCookieStore.setCookie(cookie("parent", value: "yes", domain: ".github.com"))
        await first.httpCookieStore.setCookie(cookie("foreign", value: "no", domain: "example.com"))
        await first.httpCookieStore.setCookie(cookie("otherPath", value: "no", path: "/settings"))
        await second.httpCookieStore.setCookie(cookie("session", value: "second"))
        let a = makeSession(first)
        let b = makeSession(second)
        defer {
            a.invalidate()
            b.invalidate()
        }
        _ = try await a.get(origin.appending(path: "pulls"), accept: "application/json")
        _ = try await b.get(origin.appending(path: "pulls"), accept: "application/json")
        let requests = IntegrationURLProtocol.control.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Cookie")?.contains("session=first") == true)
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Cookie")?.contains("parent=yes") == true)
        XCTAssertFalse(requests[0].value(forHTTPHeaderField: "Cookie")?.contains("foreign=") == true)
        XCTAssertFalse(requests[0].value(forHTTPHeaderField: "Cookie")?.contains("otherPath=") == true)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Cookie"), "session=second")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Referer"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
    }

    func testResponseCookiesStayInOwningStoreAndCannotBroadenTheirDomain() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        let other = WKWebsiteDataStore.nonPersistent()
        let session = makeSession(store)
        defer { session.invalidate() }
        IntegrationURLProtocol.control.respond(headers: ["Set-Cookie": "session=renewed; Path=/; Secure; HttpOnly"])
        _ = try await session.get(origin.appending(path: "pulls"), accept: "application/json")
        let cookies = await store.httpCookieStore.allCookies()
        XCTAssertEqual(cookies.first { $0.name == "session" }?.value, "renewed")
        let foreign = await other.httpCookieStore.allCookies()
        XCTAssertTrue(foreign.isEmpty)
        IntegrationURLProtocol.control.respond(headers: ["Set-Cookie": "leaked=no; Domain=com; Path=/; Secure"])
        _ = try await session.get(origin.appending(path: "pulls"), accept: "application/json")
        let updated = await store.httpCookieStore.allCookies()
        XCTAssertFalse(updated.contains { $0.name == "leaked" })
    }

    func testForeignOriginsAndCredentialedURLsNeverReachTheNetwork() async throws {
        let session = makeSession(.nonPersistent())
        defer { session.invalidate() }
        for address in [
            "https://github.com.example/pulls", "http://github.com/pulls", "https://user:password@github.com/pulls",
            "https://github.com:444/pulls",
        ] {
            do {
                _ = try await session.get(try XCTUnwrap(URL(string: address)), accept: "application/json")
                XCTFail("An origin-bound session must reject this request.")
            } catch { XCTAssertEqual(error as? BrowserIntegrationSessionFailure, .invalidRequest) }
        }
        XCTAssertTrue(IntegrationURLProtocol.control.requests.isEmpty)
        IntegrationURLProtocol.control.respond(status: 302, headers: ["Location": "https://example.com/login"])
        let response = try await session.get(origin.appending(path: "pulls"), accept: "application/json")
        XCTAssertEqual(response.status, 302)
        XCTAssertEqual(IntegrationURLProtocol.control.requests.count, 1)
    }

    func testLogoutDuringRequestCancelsItAndCannotRestoreTheOldCookie() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        let cookie = cookie("session", value: "old")
        await store.httpCookieStore.setCookie(cookie)
        let session = makeSession(store)
        defer { session.invalidate() }
        let started = expectation(description: "Request started")
        IntegrationURLProtocol.control.pause(started: started)
        let pending = Task { try await session.get(origin.appending(path: "pulls"), accept: "application/json") }
        await fulfillment(of: [started], timeout: 2)
        await store.httpCookieStore.deleteCookie(cookie)
        // Cookie-store notifications can be delayed without a web process. The
        // response must still revalidate cookies before publishing or renewing.
        IntegrationURLProtocol.control.release(headers: ["Set-Cookie": "session=old; Path=/; Secure"])
        do {
            _ = try await pending.value
            XCTFail("Logout must cancel the old request.")
        } catch {}
        XCTAssertGreaterThan(session.revision, 0)
        let cookies = await store.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.isEmpty)
    }

    func testRevocationAndOversizedResponseCannotPublishOrWriteCookies() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        var authorized = true
        let session = makeSession(store, isAuthorized: { authorized })
        defer { session.invalidate() }
        IntegrationURLProtocol.control.respond(
            headers: ["Set-Cookie": "session=no; Secure; Path=/"], onRequest: { authorized = false })
        do {
            _ = try await session.get(origin.appending(path: "pulls"), accept: "application/json")
            XCTFail("Revoked Space published.")
        } catch {}
        let cookies = await store.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.isEmpty)
        authorized = true
        IntegrationURLProtocol.control.respond(headers: ["Content-Length": "6000000"])
        do {
            _ = try await session.get(origin.appending(path: "pulls"), accept: "application/json")
            XCTFail("Oversized response accepted.")
        } catch { XCTAssertEqual(error as? BrowserIntegrationSessionFailure, .invalidResponse) }
    }

    func testInvalidationReleasesPendingRequestsAndRejectsFutureReads() async throws {
        var store: WKWebsiteDataStore? = .nonPersistent()
        weak var releasedStore = store
        let session = makeSession(try XCTUnwrap(store))
        store = nil
        let started = expectation(description: "Request started")
        IntegrationURLProtocol.control.pause(started: started)
        let pending = Task { try await session.get(origin.appending(path: "pulls"), accept: "application/json") }
        await fulfillment(of: [started], timeout: 2)
        session.invalidate()
        do {
            _ = try await pending.value
            XCTFail("Invalidated request published.")
        } catch {}
        do {
            _ = try await session.get(origin, accept: "application/json")
            XCTFail("Invalidated session reused.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(releasedStore, "A stopped integration must not retain a profile being removed.")
    }

    private func makeSession(_ store: WKWebsiteDataStore, isAuthorized: @escaping @MainActor () -> Bool = { true })
        -> WebKitIntegrationSession
    {
        WebKitIntegrationSession(
            store: store, origin: origin, isAuthorized: isAuthorized,
            configuration: {
                let settings = URLSessionConfiguration.ephemeral
                settings.protocolClasses = [IntegrationURLProtocol.self]
                return settings
            })
    }

    private func cookie(_ name: String, value: String, domain: String = "github.com", path: String = "/") -> HTTPCookie
    {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"])!
    }
}

private final class IntegrationURLProtocol: URLProtocol, @unchecked Sendable {
    final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var captured: [URLRequest] = []
        private var status = 200
        private var headers: [String: String] = [:]
        private var pending: [IntegrationURLProtocol] = []
        private var started: XCTestExpectation?
        private var onRequest: (@MainActor () -> Void)?
        var requests: [URLRequest] { lock.withLock { captured } }
        func reset() {
            lock.withLock {
                pending = []
                captured = []
                status = 200
                headers = [:]
                started = nil
                onRequest = nil
            }
        }
        func respond(status: Int = 200, headers: [String: String] = [:], onRequest: (@MainActor () -> Void)? = nil) {
            lock.withLock {
                self.status = status
                self.headers = headers
                self.onRequest = onRequest
                started = nil
            }
        }
        func pause(started: XCTestExpectation) { lock.withLock { self.started = started } }
        func hold(_ request: IntegrationURLProtocol) { lock.withLock { pending.append(request) } }
        func remove(_ request: IntegrationURLProtocol) { lock.withLock { pending.removeAll { $0 === request } } }
        func release(headers: [String: String]) {
            let waiting = lock.withLock {
                let result = pending
                pending = []
                return result
            }
            for request in waiting { request.finish(status: 200, headers: headers, onRequest: nil) }
        }
        func receive(_ request: URLRequest) -> (Int, [String: String], XCTestExpectation?, (@MainActor () -> Void)?) {
            lock.withLock {
                captured.append(request)
                return (status, headers, started, onRequest)
            }
        }
    }
    static let control = Control()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, headers, started, onRequest) = Self.control.receive(request)
        if let started {
            Self.control.hold(self)
            started.fulfill()
            return
        }
        finish(status: status, headers: headers, onRequest: onRequest)
    }

    func finish(status: Int, headers: [String: String], onRequest: (@MainActor () -> Void)?) {
        Task { @MainActor in
            onRequest?()
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { Self.control.remove(self) }
}
