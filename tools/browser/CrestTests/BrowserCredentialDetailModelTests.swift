import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialDetailModelTests: XCTestCase {
    func testRevealForwardsExactCredentialAndRuntimeAssignment() async throws {
        let descriptor = try makeDescriptor()
        let assignment = makeAssignment(for: descriptor)
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "test-password"
        )
        var receivedCredentialID: UUID?
        var receivedAssignment: BrowserSpaceRuntimeAssignment?
        let model = makeModel(
            descriptor: descriptor,
            assignment: assignment,
            revealCredential: { credentialID, requestedAssignment, _ in
                receivedCredentialID = credentialID
                receivedAssignment = requestedAssignment
                return credential
            }
        )

        await model.toggleReveal()

        XCTAssertEqual(receivedCredentialID, descriptor.id)
        XCTAssertEqual(receivedAssignment, assignment)
        XCTAssertEqual(model.visiblePassword, "test-password")
        XCTAssertNotNil(model.revealExpiration)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertNil(model.errorMessage)

        await model.toggleReveal()

        XCTAssertNil(model.visiblePassword)
        XCTAssertNil(model.revealExpiration)
    }

    func testCopyWritesAnExpiringLocalLease() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "clipboard-password"
        )
        var writtenPassword: String?
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { _, _, _ in credential },
            writeClipboard: { lease in
                writtenPassword = lease.password(
                    at: Date(timeIntervalSince1970: 1_001)
                )
                return true
            }
        )

        await model.copy()

        XCTAssertEqual(writtenPassword, "clipboard-password")
        XCTAssertNotNil(model.copyExpiration)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertNil(model.errorMessage)
    }

    func testAuthenticationFailureDoesNotExposeASecret() async throws {
        let descriptor = try makeDescriptor()
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { _, _, _ in throw TestError.expected }
        )

        await model.toggleReveal()

        XCTAssertNil(model.visiblePassword)
        XCTAssertEqual(
            model.errorMessage,
            String(
                localized: "Crest couldn’t authenticate and read that password from this Space."
            )
        )
        XCTAssertFalse(model.isAuthenticating)
    }

    func testClearingSensitiveStateRejectsLateRevealCompletion() async throws {
        let descriptor = try makeDescriptor()
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "must-not-appear"
        )
        let suspendedReveal = SuspendedReveal()
        let model = makeModel(
            descriptor: descriptor,
            revealCredential: { credentialID, assignment, reason in
                try await suspendedReveal.call(credentialID, assignment, reason)
            }
        )

        let task = Task { await model.toggleReveal() }
        await waitForInvocation(of: suspendedReveal)

        model.clearSensitiveState()
        suspendedReveal.resume(returning: credential)
        await task.value

        XCTAssertNil(model.visiblePassword)
        XCTAssertNil(model.revealExpiration)
        XCTAssertFalse(model.isAuthenticating)
    }

    func testProfileReplacementRejectsRevealCompletion() async throws {
        let descriptor = try makeDescriptor()
        let assignment = makeAssignment(for: descriptor)
        var currentAssignment = assignment
        let credential = BrowserCredential(
            descriptor: descriptor,
            password: "old-profile-secret"
        )
        let suspendedReveal = SuspendedReveal()
        let model = makeModel(
            descriptor: descriptor,
            assignment: assignment,
            isAssignmentCurrent: { $0 == currentAssignment },
            revealCredential: { credentialID, assignment, reason in
                try await suspendedReveal.call(credentialID, assignment, reason)
            }
        )

        let task = Task { await model.toggleReveal() }
        await waitForInvocation(of: suspendedReveal)

        currentAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID,
            profileID: fixedUUID(3)
        )
        suspendedReveal.resume(returning: credential)
        await task.value

        XCTAssertNil(model.visiblePassword)
        XCTAssertNil(model.revealExpiration)
        XCTAssertFalse(model.isAuthenticating)
    }

}

extension BrowserCredentialDetailModelTests {
    @MainActor
    fileprivate final class SuspendedReveal {
        private(set) var invocationCount = 0
        private var continuation: CheckedContinuation<BrowserCredential, Error>?

        func call(
            _: UUID,
            _: BrowserSpaceRuntimeAssignment,
            _: String
        ) async throws -> BrowserCredential {
            invocationCount += 1
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func resume(returning credential: BrowserCredential) {
            continuation?.resume(returning: credential)
            continuation = nil
        }
    }

    fileprivate enum TestError: Error {
        case expected
    }

    fileprivate func makeModel(
        descriptor: CredentialDescriptor,
        assignment: BrowserSpaceRuntimeAssignment? = nil,
        isAssignmentCurrent:
            @escaping @MainActor (
                BrowserSpaceRuntimeAssignment
            ) -> Bool = { _ in true },
        revealCredential: @escaping BrowserCredentialRevealer,
        writeClipboard: @escaping BrowserCredentialClipboardWriter = { _ in true },
        now: @escaping @MainActor () -> Date = {
            Date(timeIntervalSince1970: 1_000)
        },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { _ in }
    ) -> BrowserCredentialDetailModel {
        BrowserCredentialDetailModel(
            descriptor: descriptor,
            assignment: assignment ?? makeAssignment(for: descriptor),
            isAssignmentCurrent: isAssignmentCurrent,
            revealCredential: revealCredential,
            writeClipboard: writeClipboard,
            now: now,
            sleep: sleep
        )
    }

    fileprivate func makeAssignment(
        for descriptor: CredentialDescriptor
    ) -> BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: descriptor.spaceID,
            profileID: fixedUUID(2)
        )
    }

    fileprivate func makeDescriptor() throws -> CredentialDescriptor {
        let origin = try XCTUnwrap(
            CredentialOrigin(
                securityProtocol: "https",
                host: "example.com",
                port: 443
            )
        )
        return CredentialDescriptor(
            id: fixedUUID(1),
            spaceID: fixedUUID(2),
            origin: origin,
            username: "person@example.com",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    fileprivate func fixedUUID(_ byte: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, byte
            )
        )
    }

    fileprivate func waitForInvocation(of revealer: SuspendedReveal) async {
        for _ in 0..<100 where revealer.invocationCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(revealer.invocationCount, 1)
    }

}
