import CoreGraphics
import Foundation
import XCTest

@testable import Crest

final class BrowserFaviconImageCacheTests: XCTestCase {
    func testLateWaiterFromCompletedLeaseCannotClearNewerSameGenerationLease() {
        let key = BrowserFaviconImageCacheKey(
            payload: BrowserFaviconPayloadIdentity(hashing: Data([0x01])),
            maximumPixelSize: 64
        )
        var registry = BrowserFaviconImageCacheRequestRegistry()
        let firstWaiter = registry.lease(for: key) {
            Task<CGImage?, Never> { nil }
        }
        let lateWaiter = registry.lease(for: key) {
            Task<CGImage?, Never> { nil }
        }

        XCTAssertEqual(firstWaiter.token, lateWaiter.token)
        XCTAssertTrue(registry.complete(firstWaiter, for: key))

        let newerLease = registry.lease(for: key) {
            Task<CGImage?, Never> { nil }
        }
        XCTAssertNotEqual(firstWaiter.token, newerLease.token)
        XCTAssertFalse(registry.complete(lateWaiter, for: key))
        let observedLease = registry.lease(for: key) {
            Task<CGImage?, Never> { nil }
        }
        XCTAssertEqual(observedLease.token, newerLease.token)
        XCTAssertTrue(registry.complete(observedLease, for: key))
    }

    func testPurgePreventsOlderDecodeFromRepopulatingOrClearingNewRequest() async throws {
        let inlinePNG = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
        let oldImage = try XCTUnwrap(
            BrowserFaviconImageDecoder.decodeSynchronously(
                inlinePNG,
                maximumPixelSize: 64
            )
        )
        let newImage = try XCTUnwrap(
            BrowserFaviconImageDecoder.decodeSynchronously(
                inlinePNG,
                maximumPixelSize: 32
            )
        )
        let decoder = ControlledDecoder(results: [oldImage, newImage])
        let cache = BrowserFaviconImageCache(decode: decoder.decode)
        let payload = Data([0x11, 0x22, 0x33])

        let oldRequest = Task {
            await cache.image(for: payload, maximumPixelSize: 64)
        }
        let oldRequestStarted = await decoder.waitUntilStarted(request: 0)
        XCTAssertTrue(oldRequestStarted)

        await cache.removeAll()

        let newRequest = Task {
            await cache.image(for: payload, maximumPixelSize: 64)
        }
        let newRequestStarted = await decoder.waitUntilStarted(request: 1)
        XCTAssertTrue(newRequestStarted)

        decoder.complete(request: 1)
        let newValue = await newRequest.value
        let newResult = try XCTUnwrap(newValue)
        XCTAssertTrue(newResult === newImage)

        decoder.complete(request: 0)
        let oldValue = await oldRequest.value
        XCTAssertNil(oldValue)

        let cachedValue = await cache.image(for: payload, maximumPixelSize: 64)
        let cached = try XCTUnwrap(cachedValue)
        XCTAssertTrue(cached === newImage)
        XCTAssertEqual(decoder.requestCount, 2)
    }

    /// A decode that starts and finishes only when the test says so.
    ///
    /// Both directions are signalled rather than polled. Waiting for a start by
    /// yielding a fixed number of times made this test depend on how much CPU the
    /// machine had spare: under a concurrent build the detached decode had not begun
    /// within the budget and the test failed on a machine where nothing was wrong.
    /// A continuation resumed by the decode itself has no budget to run out of — if
    /// the decode never starts, the test hangs and XCTest reports that instead of
    /// blaming the wrong thing.
    private final class ControlledDecoder: @unchecked Sendable {
        private let lock = NSLock()
        private let results: [CGImage]
        private let completions: [DispatchSemaphore]
        private var count = 0
        private var startWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

        init(results: [CGImage]) {
            self.results = results
            completions = results.map { _ in DispatchSemaphore(value: 0) }
        }

        var requestCount: Int {
            lock.withLock { count }
        }

        func decode(data _: Data, maximumPixelSize _: Int) -> CGImage? {
            let index = lock.withLock {
                defer { count += 1 }
                return count
            }
            announceStart(of: index)
            completions[index].wait()
            return results[index]
        }

        /// Suspends until the decoder has entered request `index`. Returns `true`
        /// once it has, so the caller can assert on the fact rather than assume it.
        func waitUntilStarted(request index: Int) async -> Bool {
            await withCheckedContinuation { continuation in
                let hasStarted = lock.withLock {
                    if count > index { return true }
                    startWaiters[index] = continuation
                    return false
                }
                if hasStarted { continuation.resume() }
            }
            return true
        }

        func complete(request index: Int) {
            completions[index].signal()
        }

        private func announceStart(of index: Int) {
            let waiter = lock.withLock { startWaiters.removeValue(forKey: index) }
            waiter?.resume()
        }
    }
}
