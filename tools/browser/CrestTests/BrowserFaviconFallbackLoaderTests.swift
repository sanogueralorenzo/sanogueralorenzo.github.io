import Foundation
import WebKit
import XCTest

@testable import Crest

final class BrowserFaviconFallbackLoaderTests: XCTestCase {
    @MainActor
    func testRejectedResponsesDoNotAccumulateTasksInTheLiveResourceSession() async throws {
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { request in
            if request.path == "/too-large" {
                return (
                    "200 OK", "Content-Type: image/png\r\n",
                    Data(repeating: 65, count: BrowserFaviconCapture.maximumByteCount + 1)
                )
            }
            return ("404 Not Found", "Content-Type: text/plain\r\n", Data("Missing site icon".utf8))
        }
        try await server.start()
        defer { server.stop() }
        let tracker = FaviconTaskLifetimeTracker()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: tracker, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        for path in ["/missing", "/too-large", "/missing", "/too-large", "/missing", "/too-large"] {
            let data = await BrowserFaviconFallbackLoader.download(
                server.url(host: "127.0.0.1", path: path), session: session)
            XCTAssertNil(data)
        }

        // getAllTasks excludes these canceled tasks even when the session
        // retains them. Observe weak lifetimes while the session stays alive.
        for _ in 0..<100 where tracker.livingCount > 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(tracker.createdCount, 6)
        XCTAssertLessThanOrEqual(tracker.livingCount, 1, "Rejected responses must not accumulate retained tasks")
    }

    func testNativeFaviconCandidateRequestBypassesPageCORSAndStaleCaches() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            FaviconURLProtocolStub.lastRequest = nil
        }
        let iconData = Data([0x00, 0x00, 0x01, 0x00])
        FaviconURLProtocolStub.responseData = iconData
        let iconURL = try XCTUnwrap(
            URL(string: "https://res.cdn.office.net/admin-favicon.ico")
        )
        let data = await BrowserFaviconCapture.downloadCandidate(
            iconURL,
            userAgent: "Mozilla/5.0 Crest favicon fixture",
            session: session
        )

        XCTAssertEqual(data, iconData)
        let request = try XCTUnwrap(FaviconURLProtocolStub.lastRequest)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            "Mozilla/5.0 Crest favicon fixture"
        )
    }

    func testFallbackRejectsHTMLReturnedFromACloudMicrosoftFaviconPath() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            FaviconURLProtocolStub.lastRequest = nil
            FaviconURLProtocolStub.contentType = "image/x-icon"
        }
        FaviconURLProtocolStub.responseData = Data("<html>login</html>".utf8)
        FaviconURLProtocolStub.contentType = "text/html; charset=utf-8"
        let iconURL = try XCTUnwrap(
            URL(string: "https://admin.cloud.microsoft/favicon.ico")
        )

        let data = await BrowserFaviconFallbackLoader.download(
            iconURL,
            session: session
        )

        XCTAssertNil(data)
    }

    func testProfileInvalidationPreventsAnOlderCompletionFromReplacingNewCacheState() async {
        let downloader = ControlledDownloader()
        let loader = BrowserFaviconFallbackLoader(download: downloader.download)
        let profileID = UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xF0)
        )
        let pageURL = try! XCTUnwrap(URL(string: "https://fallback.invalid/page"))
        let oldData = Data([0x01, 0x02, 0x03])
        let newData = Data([0x04, 0x05, 0x06])

        let oldRequest = Task {
            await loader.data(for: pageURL, profileID: profileID)
        }
        let firstStarted = await downloader.waitForRequestCount(1)
        XCTAssertTrue(firstStarted)

        await loader.removeAll(for: profileID)

        let newRequest = Task {
            await loader.data(for: pageURL, profileID: profileID)
        }
        let secondStarted = await downloader.waitForRequestCount(2)
        XCTAssertTrue(secondStarted)

        await downloader.completeRequest(at: 1, with: newData)
        let newResult = await newRequest.value
        XCTAssertEqual(newResult, newData)

        await downloader.completeRequest(at: 0, with: oldData)
        let oldResult = await oldRequest.value
        XCTAssertNil(oldResult)

        let cachedResult = await loader.data(for: pageURL, profileID: profileID)
        XCTAssertEqual(cachedResult, newData)
        let requestCount = await downloader.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    /// Signals request starts and lets each test release completions explicitly.
    private actor ControlledDownloader {
        private var continuations: [CheckedContinuation<Data?, Never>] = []
        private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        var requestCount: Int { continuations.count }

        func download(_ url: URL) async -> Data? {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
                announceStart()
            }
        }

        /// Suspends until `expectedCount` downloads have started. Returns `true`
        /// once they have, so the caller can assert on the fact rather than
        /// assume it.
        func waitForRequestCount(_ expectedCount: Int) async -> Bool {
            guard continuations.count < expectedCount else { return true }
            await withCheckedContinuation { continuation in
                startWaiters.append((expectedCount, continuation))
            }
            return true
        }

        func completeRequest(at index: Int, with data: Data?) {
            continuations[index].resume(returning: data)
        }

        private func announceStart() {
            let startedCount = continuations.count
            let readyWaiters = startWaiters.filter { $0.count <= startedCount }
            startWaiters.removeAll { $0.count <= startedCount }
            for waiter in readyWaiters {
                waiter.continuation.resume()
            }
        }
    }

    private final class FaviconURLProtocolStub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var lastRequest: URLRequest?
        nonisolated(unsafe) static var responseData = Data()
        nonisolated(unsafe) static var contentType = "image/x-icon"

        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            Self.lastRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": Self.contentType]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.responseData)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private final class FaviconTaskLifetimeTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private final class Reference {
            weak var task: URLSessionTask?
            init(_ task: URLSessionTask) { self.task = task }
        }

        private let lock = NSLock()
        private var references: [Reference] = []

        var createdCount: Int { lock.withLock { references.count } }
        var livingCount: Int { lock.withLock { references.filter { $0.task != nil }.count } }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            lock.withLock { references.append(Reference(task)) }
        }
    }
}
