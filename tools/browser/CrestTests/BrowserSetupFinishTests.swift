import XCTest

@testable import Crest

@MainActor
final class BrowserSetupFinishTests: XCTestCase {
    /// The guide never opens in a locked first Space. Finishing asks to unlock
    /// it first; a refusal applies nothing and leaves setup to finish, and
    /// the retry applies the manual setup once over whatever changed meanwhile.
    func testARefusedUnlockLeavesSetupUnfinishedUntilARetryAppliesTheManualSetupOnce() async throws {
        var session = SessionState.Seed.preview
        session.spaces[0].settings.accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(seed: session)
        let authenticator = SetupFinishAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        browser.attachSpaceAccess(access)
        try browser.core.send(StartSetup(workspaceID: browser.family.workspaceID, entry: .firstRun))
        try browser.core.send(ShowSetupStep(step: .manualSetup))
        let setup = BrowserManualSetupModel(core: browser.core)
        let addedID = try XCTUnwrap(setup.addSpace())
        let before = browser.sessionSeed

        let refused = Task { await BrowserSetupFinish.finish(browser: browser, spaceAccess: access) }
        await authenticator.waitForRequest()
        authenticator.resolve(false)
        let refusal = await refused.value
        XCTAssertTrue(refusal is BrowserSetupCancelled)
        XCTAssertEqual(browser.sessionSeed, before)
        XCTAssertNotNil(setup.draft)
        XCTAssertNotEqual(browser.core.state.setupCompleted, true)

        let retry = Task { await BrowserSetupFinish.finish(browser: browser, spaceAccess: access) }
        await authenticator.waitForRequest()
        let updated = browser.spaceModels[1]
        XCTAssertTrue(browser.setTabCustomTitle("Updated during setup", for: updated.tabs.models[0].id, in: updated.id))
        authenticator.resolve(true)
        guard let completed = await retry.value as? BrowserSetupCompleted else {
            return XCTFail("Setup did not complete")
        }
        XCTAssertEqual(completed.guide?.spaceID, before.spaces.first?.id)
        XCTAssertEqual(browser.spaceModels.filter { $0.id == addedID }.count, 1)
        XCTAssertEqual(browser.spaceModel(updated.id)?.tabs.models[0].customTitle, "Updated during setup")
        XCTAssertNil(setup.draft)
        XCTAssertEqual(browser.core.state.setupCompleted, true)
    }
}

@MainActor
private final class SetupFinishAuthenticator: BrowserDeviceAuthenticating {
    private var request: CheckedContinuation<Bool, Error>?
    private var waiter: CheckedContinuation<Void, Never>?

    func authenticate(reason: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            request = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitForRequest() async {
        if request != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resolve(_ allowed: Bool) {
        let pending = request
        request = nil
        pending?.resume(returning: allowed)
    }
}
