import AppKit
import Observation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceAccessTests: XCTestCase {

    func testChosenDefaultSpaceBecomesTheLaunchSelection() throws {
        let store = BrowserStore(seed: .preview)
        let work = try XCTUnwrap(store.spaceModels.first)
        let personal = try XCTUnwrap(store.spaceModels.last)

        store.setDefaultSpace(personal.id)
        store.selectSpace(work.id)

        XCTAssertEqual(store.workspaceModel?.defaultSpaceID, personal.id)
        XCTAssertEqual(store.selectedSpaceID, work.id)
        let relaunched = SessionState.Seed(
            spaces: store.spaceModels.map(\.value.seed), defaultSpaceID: store.workspaceModel?.defaultSpaceID)
        XCTAssertEqual(BrowserStore(seed: relaunched).selectedSpaceID, personal.id)
    }

    /// The stores the tests' controllers unlock Spaces of, which the
    /// controllers do not keep.
    private var stores: [BrowserStore] = []

    /// A store whose first Space asks for authentication, and a controller
    /// for its core that answers with `authenticator`.
    private func guardedStore(authenticator: any BrowserDeviceAuthenticating) throws
        -> (store: BrowserStore, access: BrowserSpaceAccessController, space: SpaceModel)
    {
        var session = SessionState.Seed.preview
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        let store = BrowserStore(seed: session)
        stores.append(store)
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        store.attachSpaceAccess(access)
        return (store, access, try XCTUnwrap(store.spaceModels.first))
    }

    func testPrivateSpaceRemainsLockedUntilDeviceOwnerAuthenticationSucceeds() async throws {
        let authenticator = BrowserDeviceAuthenticatorStub(results: [.success(true)])
        let (_, access, space) = try guardedStore(authenticator: authenticator)

        XCTAssertTrue(access.isLocked(space))
        let unlocked = await access.unlock(space)

        XCTAssertTrue(unlocked)
        XCTAssertFalse(access.isLocked(space))
        XCTAssertEqual(
            authenticator.reasons,
            [
                "Authenticate to unlock the Work Space in Crest."
            ])
    }

    func testSuccessfulAuthenticationPublishesTheUnlockedState() async throws {
        let (_, access, space) = try guardedStore(
            authenticator: BrowserDeviceAuthenticatorStub(results: [.success(true)]))
        let stateChanged = expectation(description: "Unlocked state published")
        withObservationTracking {
            _ = access.isLocked(space)
        } onChange: {
            stateChanged.fulfill()
        }

        let unlocked = await access.unlock(space)

        await fulfillment(of: [stateChanged], timeout: 1)
        XCTAssertTrue(unlocked)
        XCTAssertFalse(access.isLocked(space))
    }

    func testAuthenticationCompletingAfterRelockCannotRevealTheSpace() async throws {
        let authenticator = SuspendedBrowserDeviceAuthenticator()
        let (_, access, space) = try guardedStore(authenticator: authenticator)
        let unlockTask = Task { await access.unlock(space) }
        while authenticator.attemptCount == 0 { await Task.yield() }
        XCTAssertTrue(access.isAuthenticating(space))

        access.lockAll()
        authenticator.complete(with: true)
        let unlocked = await unlockTask.value

        XCTAssertFalse(unlocked)
        XCTAssertTrue(access.isLocked(space))
        XCTAssertNil(access.authenticatingAssignment)
    }

    func testDeniedAuthenticationNeverUnlocksAPrivateSpace() async throws {
        let (_, access, space) = try guardedStore(
            authenticator: BrowserDeviceAuthenticatorStub(results: [.success(false)]))

        let unlocked = await access.unlock(space)

        XCTAssertFalse(unlocked)
        XCTAssertTrue(access.isLocked(space))
        XCTAssertEqual(access.failure, .authenticationDenied)
    }

    func testUnavailableAuthenticationKeepsTheSpaceLockedAndAllowsRetry() async throws {
        let authenticator = BrowserDeviceAuthenticatorStub(
            results: [.failure(CancellationError()), .success(true)]
        )
        let (_, access, space) = try guardedStore(authenticator: authenticator)

        let cancelled = await access.unlock(space)

        XCTAssertFalse(cancelled)
        XCTAssertTrue(access.isLocked(space))
        XCTAssertNil(access.authenticatingAssignment)
        XCTAssertEqual(access.failure, .authenticationUnavailable)

        let retried = await access.unlock(space)

        XCTAssertTrue(retried)
        XCTAssertNil(access.failure)
        XCTAssertNil(access.authenticatingAssignment)
        XCTAssertEqual(authenticator.reasons.count, 2)
    }

    func testStorePersistsDefaultAndPrivateSpacePolicies() throws {
        let store = BrowserStore(seed: .preview)
        let personal = try XCTUnwrap(store.spaceModels.last)

        store.setDefaultSpace(personal.id)
        store.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: personal.id)

        XCTAssertEqual(store.workspaceModel?.defaultSpaceID, personal.id)
        XCTAssertEqual(store.spaceModel(personal.id)?.settings.accessPolicy, .deviceOwnerAuthentication)
    }
}

@MainActor
private final class BrowserDeviceAuthenticatorStub: BrowserDeviceAuthenticating {
    private var results: [Result<Bool, Error>]
    private(set) var reasons: [String] = []

    init(results: [Result<Bool, Error>]) {
        self.results = results
    }

    func authenticate(reason: String) async throws -> Bool {
        reasons.append(reason)
        return try results.removeFirst().get()
    }
}

@MainActor
private final class SuspendedBrowserDeviceAuthenticator: BrowserDeviceAuthenticating {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var attemptCount = 0

    func authenticate(reason: String) async throws -> Bool {
        attemptCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(with result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
