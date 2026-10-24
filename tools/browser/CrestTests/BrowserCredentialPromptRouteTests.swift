import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialPromptRouteTests: XCTestCase {
    func testEveryCredentialPhaseMapsToOneExactRoute() {
        let expectations:
            [(
                phase: BrowserCredentialSavePromptPhase,
                state: BrowserCredentialPromptState,
                primaryAction: BrowserCredentialPromptPrimaryAction?,
                dismissAction: BrowserCredentialPromptDismissAction,
                busyActivity: BrowserCredentialPromptBusyActivity?
            )] = [
                (.preparing, .preparing, nil, .notNow, .checkingSavedPasswords),
                (.create, .create, .commit(.create), .notNow, nil),
                (.update, .update, .commit(.update), .notNow, nil),
                (.alreadyStored, .alreadyStored, nil, .notNow, nil),
                (.saving(.create), .saving(.create), nil, .notNow, .savingPassword),
                (.saving(.update), .saving(.update), nil, .notNow, .savingPassword),
                (.saved(.created), .saved(.created), nil, .done, nil),
                (.failed(.preparation), .failedPreparation, .retryCredentialPreparation, .notNow, nil),
                (
                    .failed(.commit(.create)),
                    .failedCommit(.create),
                    .retryCredentialPreparation,
                    .notNow,
                    nil
                ),
                (
                    .failed(.commit(.update)),
                    .failedCommit(.update),
                    .retryCredentialPreparation,
                    .notNow,
                    nil
                ),
            ]

        for expectation in expectations {
            let route = BrowserCredentialPromptRoute(
                phase: expectation.phase,
                systemPasswordOfferPhase: .notRequested,
                offersSystemPasswords: false
            )

            XCTAssertEqual(route.state, expectation.state)
            XCTAssertEqual(route.primaryAction, expectation.primaryAction)
            XCTAssertEqual(route.dismissAction, expectation.dismissAction)
            XCTAssertEqual(route.busyActivity, expectation.busyActivity)
            XCTAssertEqual(route.isBusy, expectation.busyActivity != nil)
        }
    }

    func testSystemPasswordOfferPhasesRouteOnlyAfterTheCrestSave() {
        let expectations:
            [(
                phase: BrowserSystemPasswordOfferPhase,
                state: BrowserCredentialPromptState,
                primaryAction: BrowserCredentialPromptPrimaryAction?,
                busyActivity: BrowserCredentialPromptBusyActivity?
            )] = [
                (.notRequested, .saved(.updated), nil, nil),
                (.offering, .offeringToSystemPasswords, nil, .openingSystemPasswords),
                (.completed, .completedSystemPasswords, nil, nil),
                (.failed, .failedSystemPasswords, .retrySystemPasswords, nil),
            ]

        for expectation in expectations {
            let route = BrowserCredentialPromptRoute(
                phase: .saved(.updated),
                systemPasswordOfferPhase: expectation.phase,
                offersSystemPasswords: true
            )

            XCTAssertEqual(route.state, expectation.state)
            XCTAssertEqual(route.primaryAction, expectation.primaryAction)
            XCTAssertEqual(route.busyActivity, expectation.busyActivity)
            XCTAssertEqual(route.dismissAction, .done)
        }

        for systemPhase in [
            BrowserSystemPasswordOfferPhase.notRequested,
            .offering,
            .completed,
            .failed,
        ] {
            let route = BrowserCredentialPromptRoute(
                phase: .create,
                systemPasswordOfferPhase: systemPhase,
                offersSystemPasswords: true
            )
            XCTAssertEqual(route.state, .create)
            XCTAssertEqual(route.primaryAction, .commit(.create))
        }
    }

    func testReplacingPromptWhileSystemOfferIsSuspendedCannotMutateTheReplacementSpace() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let firstSpace = try XCTUnwrap(store.spaceModels.first)
        let replacementSpace = try XCTUnwrap(store.spaceModels.dropFirst().first)
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let firstCandidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "first@example.com",
            password: "first-secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 4_000)
        )
        let replacementCandidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "replacement@example.com",
            password: "replacement-secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 4_100)
        )
        let model = BrowserCredentialSavePromptModel()
        let offerStarted = expectation(description: "system Passwords offer started")
        let suspension = SystemPasswordOfferSuspension()

        await model.prepare(
            candidate: firstCandidate,
            in: firstSpace.id,
            browser: store,
            now: firstCandidate.submittedAt
        )
        await model.commit(
            candidate: firstCandidate,
            in: firstSpace.id,
            browser: store,
            now: firstCandidate.submittedAt
        )

        let staleOffer = Task { @MainActor in
            await model.offerToSystemPasswords {
                offerStarted.fulfill()
                await suspension.wait()
            }
        }
        await fulfillment(of: [offerStarted])

        await model.prepare(
            candidate: replacementCandidate,
            in: replacementSpace.id,
            browser: store,
            now: replacementCandidate.submittedAt
        )
        XCTAssertEqual(model.phase, .create)
        XCTAssertEqual(model.systemPasswordOfferPhase, .notRequested)

        await suspension.resume()
        await staleOffer.value

        XCTAssertEqual(model.phase, .create)
        XCTAssertEqual(model.systemPasswordOfferPhase, .notRequested)

        await model.commit(
            candidate: firstCandidate,
            in: firstSpace.id,
            browser: store,
            now: firstCandidate.submittedAt
        )
        XCTAssertEqual(model.phase, .create)

        await model.commit(
            candidate: replacementCandidate,
            in: replacementSpace.id,
            browser: store,
            now: replacementCandidate.submittedAt
        )
        XCTAssertEqual(model.phase, .saved(.created))
        let firstSpaceDescriptors = try await store.savedCredentialDescriptors(in: firstSpace.id)
        let replacementSpaceDescriptors = try await store.savedCredentialDescriptors(
            in: replacementSpace.id
        )
        XCTAssertEqual(firstSpaceDescriptors.count, 1)
        XCTAssertEqual(replacementSpaceDescriptors.count, 1)
    }

    func testUpdateTransitionKeepsTheCandidateSpaceBoundAndCommitsOnce() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let space = try XCTUnwrap(store.spaceModels.first)
        let url = try XCTUnwrap(URL(string: "https://accounts.crest.test/login"))
        let origin = try XCTUnwrap(CredentialOrigin(url: url))
        _ = try await store.saveCredential(
            username: "person@example.com",
            password: "old-secret",
            for: url,
            in: space.id
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "new-secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 3_000)
        )
        let model = BrowserCredentialSavePromptModel()

        await model.prepare(
            candidate: candidate,
            in: space.id,
            browser: store,
            now: candidate.submittedAt
        )
        XCTAssertEqual(model.phase, .update)
        XCTAssertEqual(model.confirmationAction, .update)

        await model.commit(
            candidate: candidate,
            in: space.id,
            browser: store,
            now: candidate.submittedAt
        )
        XCTAssertEqual(model.phase, .saved(.updated))

        let descriptors = try await store.savedCredentialDescriptors(in: space.id)
        XCTAssertEqual(descriptors.count, 1)
        let credential = try await store.credential(
            id: try XCTUnwrap(descriptors.first?.id),
            in: space.id
        )
        XCTAssertEqual(credential?.password, "new-secret")
    }

    private actor SystemPasswordOfferSuspension {
        private var isResumed = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            guard !isResumed else { return }
            await withCheckedContinuation { continuation in
                if isResumed {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        }

        func resume() {
            isResumed = true
            continuation?.resume()
            continuation = nil
        }
    }
}
