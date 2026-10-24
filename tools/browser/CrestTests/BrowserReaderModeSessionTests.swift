import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserReaderModeSessionTests: XCTestCase {
    func testNavigationDuringAvailabilityPreventsActivationOfTheReplacementDocument() async throws {
        let document = SuspendedReaderModeDocument()
        let session = BrowserReaderModeSession(document: document)
        let availability = expectation(description: "Availability requested")
        document.availabilityRequested = { availability.fulfill() }
        let activation = Task { try await session.setActive(true) }
        await fulfillment(of: [availability], timeout: 1)

        document.url = URL(string: "https://reader.crest.test/replacement")
        session.invalidate()
        document.finishAvailability(true)
        await assertRejected(activation)

        XCTAssertEqual(document.activationCount, 0)
        XCTAssertEqual(session.state, .unavailable)
    }

    func testSupersededActivationFailureCannotEraseTheNewerReaderState() async throws {
        let document = SuspendedReaderModeDocument()
        document.suspendsAvailability = false
        document.suspendsActivation = true
        let session = BrowserReaderModeSession(document: document)
        let started = expectation(description: "Activation requested")
        document.activationRequested = { started.fulfill() }
        let firstActivation = Task { try await session.setActive(true) }
        await fulfillment(of: [started], timeout: 1)

        document.suspendsActivation = false
        document.activationRequested = nil
        try await session.setActive(true)
        XCTAssertEqual(session.state, .active)

        document.failActivation()
        await assertRejected(firstActivation)
        XCTAssertEqual(session.state, .active)
    }

    func testCancelledAvailabilityCannotActivateTheDocument() async throws {
        let document = SuspendedReaderModeDocument()
        let session = BrowserReaderModeSession(document: document)
        let availability = expectation(description: "Availability requested")
        document.availabilityRequested = { availability.fulfill() }
        let activation = Task { try await session.setActive(true) }
        await fulfillment(of: [availability], timeout: 1)

        activation.cancel()
        document.finishAvailability(true)
        await assertRejected(activation)

        XCTAssertEqual(document.activationCount, 0)
        XCTAssertEqual(session.state, .unavailable)
    }

    func testAvailabilityRefreshDoesNotSupersedeAnActivationInProgress() async throws {
        let document = SuspendedReaderModeDocument()
        document.suspendsAvailability = false
        document.suspendsActivation = true
        let session = BrowserReaderModeSession(document: document)
        let started = expectation(description: "Activation requested")
        document.activationRequested = { started.fulfill() }
        let activation = Task { try await session.setActive(true) }
        await fulfillment(of: [started], timeout: 1)

        await session.refreshAvailability()
        document.finishActivation()
        try await activation.value

        XCTAssertEqual(session.state, .active)
    }

    private func assertRejected(_ task: Task<Void, any Error>) async {
        do {
            try await task.value
            XCTFail("An interrupted Reader request must fail")
        } catch {}
    }
}

@MainActor
private final class SuspendedReaderModeDocument: BrowserReaderModeDocument {
    var url = URL(string: "https://reader.crest.test/article")
    var suspendsAvailability = true
    var suspendsActivation = false
    var availabilityRequested: (() -> Void)?
    var activationRequested: (() -> Void)?
    private(set) var activationCount = 0
    private var availabilityContinuation: CheckedContinuation<Bool, any Error>?
    private var activationContinuation: CheckedContinuation<Void, any Error>?

    func prepareForReaderMode() async throws {}

    func readerModeIsAvailable() async throws -> Bool {
        guard suspendsAvailability else { return true }
        return try await withCheckedThrowingContinuation { continuation in
            availabilityContinuation = continuation
            availabilityRequested?()
        }
    }

    func activateReaderMode() async throws {
        activationCount += 1
        guard suspendsActivation else { return }
        try await withCheckedThrowingContinuation { continuation in
            activationContinuation = continuation
            activationRequested?()
        }
    }

    func deactivateReaderMode() async throws {}

    func finishAvailability(_ isAvailable: Bool) {
        availabilityContinuation?.resume(returning: isAvailable)
        availabilityContinuation = nil
    }

    func failActivation() {
        activationContinuation?.resume(throwing: BrowserReaderModeError.presentationFailed)
        activationContinuation = nil
    }

    func finishActivation() {
        activationContinuation?.resume()
        activationContinuation = nil
    }
}
