import XCTest

@testable import Crest

@MainActor
final class BrowserAutomaticPictureInPictureTests: XCTestCase {
    func testPendingRequestReservesSlotAcrossPages() {
        let coordinator = BrowserAutomaticPictureInPictureCoordinator(isEnabled: { true }, isSystemOccupied: { false })
        let first = Client()
        let second = Client()
        coordinator.register(first)
        coordinator.register(second)
        coordinator.request(from: first)
        coordinator.request(from: second)
        XCTAssertEqual(first.requests, 1)
        XCTAssertEqual(second.requests, 0)
        first.isPictureInPictureActive = true
        first.completions[0](true)
        coordinator.request(from: second)
        XCTAssertEqual(second.requests, 0, "An active session must not be replaced after its pending reservation ends.")
        first.isPictureInPictureActive = false
        coordinator.request(from: second)
        XCTAssertEqual(second.requests, 1)
    }

    func testDisabledBusyAndIneligibleRequestsAreSkipped() {
        for (enabled, occupied, eligible) in [(false, false, true), (true, true, true), (true, false, false)] {
            let coordinator = BrowserAutomaticPictureInPictureCoordinator(
                isEnabled: { enabled }, isSystemOccupied: { occupied })
            let client = Client()
            client.canAutomaticallyEnterPictureInPicture = eligible
            coordinator.request(from: client)
            XCTAssertEqual(client.requests, 0)
        }
    }

    func testManualSessionAlsoOccupiesSlot() {
        let coordinator = BrowserAutomaticPictureInPictureCoordinator(isEnabled: { true }, isSystemOccupied: { false })
        let manual = Client()
        let automatic = Client()
        manual.isPictureInPictureActive = true
        coordinator.register(manual)
        coordinator.request(from: automatic)
        XCTAssertEqual(automatic.requests, 0)
    }

    func testCancelledCallbackCannotReleaseAnotherPagesReservation() {
        let coordinator = BrowserAutomaticPictureInPictureCoordinator(isEnabled: { true }, isSystemOccupied: { false })
        let first = Client()
        let second = Client()
        let third = Client()
        coordinator.request(from: first)
        coordinator.cancel(first)
        coordinator.request(from: second)
        first.completions[0](false)
        coordinator.request(from: third)
        XCTAssertEqual(first.cancellations, 1)
        XCTAssertEqual(second.requests, 1)
        XCTAssertEqual(third.requests, 0)
        second.completions[0](false)
        coordinator.request(from: third)
        XCTAssertEqual(third.requests, 1)
    }

    private final class Client: BrowserAutomaticPictureInPictureClient {
        var canAutomaticallyEnterPictureInPicture = true
        var isPictureInPictureActive = false
        var requests = 0
        var cancellations = 0
        var completions: [@MainActor (Bool) -> Void] = []

        func beginAutomaticPictureInPicture(completion: @escaping @MainActor (Bool) -> Void) {
            requests += 1
            completions.append(completion)
        }

        func cancelAutomaticPictureInPicture() { cancellations += 1 }
    }
}
