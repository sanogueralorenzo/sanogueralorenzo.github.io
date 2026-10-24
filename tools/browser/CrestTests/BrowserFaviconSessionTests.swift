import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserFaviconSessionTests: XCTestCase {
    func testNavigationPreventsOldCaptureFromStartingFallback() async {
        let document = SuspendedFaviconDocument()
        let session = BrowserFaviconSession(document: document, receive: { _ in XCTFail("Stale icon published") })
        let started = expectation(description: "Capture started")
        document.captureStarted = { started.fulfill() }
        let request = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)

        // A reload may replace the document without changing its URL.
        session.invalidate()
        document.finishCapture(nil)
        let result = await request.value

        XCTAssertNil(result)
        XCTAssertEqual(document.fallbackCount, 0)
    }

    func testRemovalDuringFallbackRejectsCompletionAndFurtherRequests() async {
        let document = SuspendedFaviconDocument()
        document.suspendsCapture = false
        let session = BrowserFaviconSession(document: document, receive: { _ in XCTFail("Removed page published") })
        let started = expectation(description: "Fallback started")
        document.fallbackStarted = { started.fulfill() }
        let request = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)

        session.stop()
        document.finishFallback(Data([1]))
        let result = await request.value
        let laterResult = await session.pull()
        session.refresh()
        await Task.yield()

        XCTAssertNil(result)
        XCTAssertNil(laterResult)
        XCTAssertEqual(document.captureCount, 1)
        XCTAssertEqual(document.fallbackCount, 1)
    }

    func testNewerRequestOwnsPublicationAndMissingCaptureKeepsLastIcon() async {
        let document = SuspendedFaviconDocument()
        var icon = Data([1])
        let session = BrowserFaviconSession(document: document, receive: { icon = $0 })
        let started = expectation(description: "Older capture started")
        document.captureStarted = { started.fulfill() }
        let oldRequest = Task { await session.pull() }
        await fulfillment(of: [started], timeout: 1)
        document.captureStarted = nil

        document.suspendsCapture = false
        document.captureData = Data([2])
        let current = await session.pull()
        document.finishCapture(Data([3]))
        let old = await oldRequest.value

        XCTAssertEqual(current, Data([2]))
        XCTAssertNil(old)
        XCTAssertEqual(icon, Data([2]))

        document.captureData = nil
        document.suspendsFallback = false
        let missing = await session.pull()
        XCTAssertNil(missing)
        XCTAssertEqual(icon, Data([2]))
    }

}

@MainActor
private final class SuspendedFaviconDocument: BrowserFaviconDocument {
    var url = URL(string: "https://favicon.crest.test/document")
    var suspendsCapture = true
    var suspendsFallback = true
    var captureData: Data?
    var captureStarted: (() -> Void)?
    var fallbackStarted: (() -> Void)?
    private(set) var captureCount = 0
    private(set) var fallbackCount = 0
    private var captureContinuation: CheckedContinuation<Data?, Never>?
    private var fallbackContinuation: CheckedContinuation<Data?, Never>?

    func capture() async -> Data? {
        captureCount += 1
        guard suspendsCapture else {
            captureStarted?()
            return captureData
        }
        return await withCheckedContinuation { continuation in
            captureContinuation = continuation
            captureStarted?()
        }
    }

    func fallback(for url: URL) async -> Data? {
        fallbackCount += 1
        guard suspendsFallback else { return nil }
        return await withCheckedContinuation { continuation in
            fallbackContinuation = continuation
            fallbackStarted?()
        }
    }

    func finishCapture(_ data: Data?) {
        captureContinuation?.resume(returning: data)
        captureContinuation = nil
    }

    func finishFallback(_ data: Data?) {
        fallbackContinuation?.resume(returning: data)
        fallbackContinuation = nil
    }
}
