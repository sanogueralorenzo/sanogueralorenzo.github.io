import AppKit
import Observation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceAccessTests: XCTestCase {

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

    func testDeniedAuthenticationNeverUnlocksAPrivateSpace() async throws {
        let (_, access, space) = try guardedStore(
            authenticator: BrowserDeviceAuthenticatorStub(results: [.success(false)]))

        let unlocked = await access.unlock(space)

        XCTAssertFalse(unlocked)
        XCTAssertTrue(access.isLocked(space))
        XCTAssertEqual(access.failure, .authenticationDenied)
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
