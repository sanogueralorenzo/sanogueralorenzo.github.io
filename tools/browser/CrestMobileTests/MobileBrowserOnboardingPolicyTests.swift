import XCTest

@testable import CrestMobile

final class MobileBrowserOnboardingPolicyTests: XCTestCase {
    func testAutomaticWelcomeIsSuppressedForAnIsolatedTestLaunch() {
        XCTAssertFalse(
            MobileBrowserWindowScene.presentsOnboardingAutomatically(
                forceOnboarding: false,
                usesIsolatedLaunch: true
            )
        )
    }

    func testExplicitOnboardingFixtureOverridesLaunchIsolation() {
        XCTAssertTrue(
            MobileBrowserWindowScene.presentsOnboardingAutomatically(
                forceOnboarding: true,
                usesIsolatedLaunch: true
            )
        )
    }

    func testProductionLaunchCanPresentTheAutomaticWelcome() {
        XCTAssertTrue(
            MobileBrowserWindowScene.presentsOnboardingAutomatically(
                forceOnboarding: false,
                usesIsolatedLaunch: false
            )
        )
    }

    func testLaunchGateOnlyReplacesTheBrowserOnAnIncompleteInstall() {
        XCTAssertTrue(
            MobileBrowserWindowScene.showsLaunchGate(
                automaticallyPresentsOnboarding: true,
                isLaunchGateActive: true
            )
        )
        XCTAssertFalse(
            MobileBrowserWindowScene.showsLaunchGate(
                automaticallyPresentsOnboarding: true,
                isLaunchGateActive: false
            )
        )
        XCTAssertFalse(
            MobileBrowserWindowScene.showsLaunchGate(
                automaticallyPresentsOnboarding: false,
                isLaunchGateActive: true
            )
        )
    }

    /// iCloud's check never holds the first-run welcome: after a few seconds
    /// it offers to set up without iCloud, and once the wait runs out it
    /// offers setup, saying iCloud is unavailable, as a failed check does.
    func testAnUnansweredICloudCheckOffersSetupWithoutICloud() {
        let flow = welcomeFlow(setupCompleted: false)

        XCTAssertEqual(welcome(flow, .checking, waited: .seconds(3)), .checking)
        XCTAssertEqual(welcome(flow, .checking, waited: .seconds(4)), .stillChecking)
        XCTAssertTrue(welcome(flow, .checking, waited: .seconds(4)).offersSetupWithoutCloud)
        XCTAssertEqual(welcome(flow, .checking, waited: .seconds(10)), .setupWithoutCloud)
        XCTAssertEqual(welcome(flow, .failed, waited: .zero), .setupWithoutCloud)
        XCTAssertEqual(welcome(flow, .waitingForAccount, waited: .zero), .setupWithoutCloud)
    }

    /// Setting up without iCloud stops the wait for good, so a retry that
    /// checks iCloud again never takes setup away.
    @MainActor
    func testSettingUpWithoutICloudStopsTheWait() {
        let wait = BrowserOnboardingCloudWait()
        wait.setUpWithoutCloud()

        XCTAssertEqual(
            BrowserOnboardingWelcomeAction(
                flow: welcomeFlow(setupCompleted: false), cloudPhase: .checking, wait: wait.stage),
            .setupWithoutCloud)
    }

    /// An answer iCloud gives after the welcome stopped waiting still decides
    /// what it offers: setup once iCloud is reached, or opening Crest once the
    /// setup it brought is complete.
    func testALateICloudAnswerStillDecidesWhatTheWelcomeOffers() {
        XCTAssertEqual(welcome(welcomeFlow(setupCompleted: false), .ready, waited: .seconds(30)), .setup)
        XCTAssertEqual(welcome(welcomeFlow(setupCompleted: true), .ready, waited: .seconds(30)), .open)
        XCTAssertEqual(welcome(welcomeFlow(setupCompleted: true), .checking, waited: .seconds(30)), .open)
    }

    private func welcome(
        _ flow: SetupFlowState, _ cloudPhase: CloudSyncPhase, waited: Duration
    ) -> BrowserOnboardingWelcomeAction {
        BrowserOnboardingWelcomeAction(
            flow: flow, cloudPhase: cloudPhase, wait: BrowserOnboardingCloudWait.Stage(waited: waited))
    }

    /// The welcome as the core opens it on first run; `setupCompleted`
    /// tells whether it offers to open Crest.
    private func welcomeFlow(setupCompleted: Bool) -> SetupFlowState {
        SetupFlowState(
            workspaceID: UUID(), entry: .firstRun, step: .welcome, backStep: nil, nextStep: .featureSpaces,
            phase: .idle, offered: [], selected: [], queue: nil, source: nil, review: nil, failure: nil,
            summary: nil, opensGuide: !setupCompleted, opensCrestFromWelcome: setupCompleted, look: .heraldic)
    }
}
