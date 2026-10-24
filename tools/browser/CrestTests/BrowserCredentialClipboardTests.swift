import AppKit
import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialClipboardTests: XCTestCase {
    func testWriteUsesConcealedTransientPasteboardAndExpiresUnchangedLease() async {
        let pasteboard = RecordingPasteboard()
        let sleeper = SuspendedSleeper()
        let clipboard = BrowserCredentialClipboard(
            pasteboard: pasteboard,
            notificationCenter: NotificationCenter(),
            now: { Self.referenceDate },
            sleep: { duration in
                try await sleeper.sleep(duration)
            }
        )

        XCTAssertTrue(clipboard.write(Self.lease(password: "secret")))
        await waitForInvocation(of: sleeper, count: 1)

        XCTAssertEqual(pasteboard.writtenValues, ["secret"])
        XCTAssertEqual(pasteboard.clearCount, 0)

        sleeper.resume(at: 0)
        await waitUntil { pasteboard.clearCount == 1 }

        XCTAssertEqual(pasteboard.clearCount, 1)
    }

    func testExpirationPreservesNewerUserPasteboardContents() async {
        let pasteboard = RecordingPasteboard()
        let sleeper = SuspendedSleeper()
        let clipboard = BrowserCredentialClipboard(
            pasteboard: pasteboard,
            notificationCenter: NotificationCenter(),
            now: { Self.referenceDate },
            sleep: { duration in
                try await sleeper.sleep(duration)
            }
        )

        XCTAssertTrue(clipboard.write(Self.lease(password: "secret")))
        await waitForInvocation(of: sleeper, count: 1)
        pasteboard.simulateUserWrite("newer-user-value")

        sleeper.resume(at: 0)
        await Task.yield()

        XCTAssertEqual(pasteboard.clearCount, 0)
        XCTAssertEqual(pasteboard.currentValue, "newer-user-value")
    }

    func testNewLeaseCannotBeClearedByOlderExpiration() async {
        let pasteboard = RecordingPasteboard()
        let sleeper = SuspendedSleeper()
        let clipboard = BrowserCredentialClipboard(
            pasteboard: pasteboard,
            notificationCenter: NotificationCenter(),
            now: { Self.referenceDate },
            sleep: { duration in
                try await sleeper.sleep(duration)
            }
        )

        XCTAssertTrue(clipboard.write(Self.lease(password: "first")))
        await waitForInvocation(of: sleeper, count: 1)
        XCTAssertTrue(clipboard.write(Self.lease(password: "second")))
        await waitForInvocation(of: sleeper, count: 2)

        sleeper.resume(at: 0)
        await Task.yield()
        XCTAssertEqual(pasteboard.clearCount, 0)
        XCTAssertEqual(pasteboard.currentValue, "second")

        sleeper.resume(at: 1)
        await waitUntil { pasteboard.clearCount == 1 }
        XCTAssertEqual(pasteboard.clearCount, 1)
    }

    func testTerminationClearsOnlyTheUnchangedLease() async {
        let pasteboard = RecordingPasteboard()
        let notifications = NotificationCenter()
        let clipboard = BrowserCredentialClipboard(
            pasteboard: pasteboard,
            notificationCenter: notifications,
            now: { Self.referenceDate },
            sleep: { _ in throw CancellationError() }
        )

        XCTAssertTrue(clipboard.write(Self.lease(password: "secret")))
        notifications.post(name: NSApplication.willTerminateNotification, object: nil)
        await waitUntil { pasteboard.clearCount == 1 }

        XCTAssertEqual(pasteboard.clearCount, 1)
    }
}

extension BrowserCredentialClipboardTests {
    fileprivate static let referenceDate = Date(timeIntervalSince1970: 1_000)

    fileprivate final class RecordingPasteboard: BrowserCredentialPasteboard {
        private(set) var changeCount = 0
        private(set) var writtenValues: [String] = []
        private(set) var clearCount = 0
        private(set) var currentValue: String?

        func writeConcealedTransientString(_ value: String) -> Bool {
            changeCount += 1
            writtenValues.append(value)
            currentValue = value
            return true
        }

        func clearContents() {
            changeCount += 1
            clearCount += 1
            currentValue = nil
        }

        func simulateUserWrite(_ value: String) {
            changeCount += 1
            currentValue = value
        }
    }

    @MainActor
    fileprivate final class SuspendedSleeper {
        private(set) var invocationCount = 0
        private var continuations: [CheckedContinuation<Void, Error>?] = []

        func sleep(_: Duration) async throws {
            invocationCount += 1
            try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func resume(at index: Int) {
            continuations[index]?.resume()
            continuations[index] = nil
        }
    }

    fileprivate static func lease(password: String) -> BrowserCredentialSecretLease {
        .clipboard(password: password, issuedAt: referenceDate)
    }

    fileprivate func waitForInvocation(
        of sleeper: SuspendedSleeper,
        count: Int
    ) async {
        for _ in 0..<100 where sleeper.invocationCount < count {
            await Task.yield()
        }
        XCTAssertEqual(sleeper.invocationCount, count)
    }

    fileprivate func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}
