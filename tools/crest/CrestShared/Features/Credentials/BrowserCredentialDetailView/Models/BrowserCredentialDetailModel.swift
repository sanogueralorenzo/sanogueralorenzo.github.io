import Foundation
import LocalAuthentication
import Observation

typealias BrowserCredentialClipboardWriter =
    @MainActor (
        BrowserCredentialSecretLease
    ) -> Bool

typealias BrowserCredentialRevealer =
    @MainActor (
        UUID,
        BrowserSpaceRuntimeAssignment,
        String
    ) async throws -> BrowserCredential

struct BrowserCredentialDetailOperationToken: Equatable, Sendable {
    let assignment: BrowserSpaceRuntimeAssignment
    let sequence: UInt64
}

@Observable
@MainActor
final class BrowserCredentialDetailModel {
    private(set) var revealLease: BrowserCredentialSecretLease?
    private(set) var isAuthenticating = false
    private(set) var copiedUntil: Date?
    private(set) var errorMessage: String?

    let request: BrowserCredentialDetailRequest

    @ObservationIgnored private let isAssignmentCurrent:
        @MainActor (
            BrowserSpaceRuntimeAssignment
        ) -> Bool
    @ObservationIgnored private let revealCredential: BrowserCredentialRevealer
    @ObservationIgnored private let writeClipboard: BrowserCredentialClipboardWriter
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private var operationSequence: UInt64 = 0
    @ObservationIgnored private var activeOperationToken: BrowserCredentialDetailOperationToken?
    @ObservationIgnored private var activeOperationTask: Task<Void, Never>?

    var descriptor: CredentialDescriptor {
        request.descriptor
    }

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        request.spaceAssignment
    }

    var spaceName: String {
        request.spaceName
    }

    var visiblePassword: String? {
        revealLease?.password(at: now())
    }

    var revealExpiration: Date? {
        revealLease?.expiration
    }

    var copyExpiration: Date? {
        copiedUntil
    }

    var showsCopyConfirmation: Bool {
        copiedUntil != nil
    }

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        request: BrowserCredentialDetailRequest
    ) {
        let sensitiveAccess = BrowserCredentialSensitiveAccess(browser: browser)
        self.request = request
        isAssignmentCurrent = { spaceAssignment in
            guard let space = browser.spaceModel(matching: spaceAssignment) else {
                return false
            }
            return !spaceAccess.isLocked(space)
        }
        revealCredential = { credentialID, spaceAssignment, reason in
            try await sensitiveAccess.revealCredential(
                id: credentialID,
                matching: spaceAssignment,
                reason: reason
            )
        }
        writeClipboard = BrowserCredentialClipboard.write
        now = { .now }
        sleep = { try await Task.sleep(for: $0) }
    }

    init(
        descriptor: CredentialDescriptor,
        assignment: BrowserSpaceRuntimeAssignment,
        spaceName: String = "Space",
        isAssignmentCurrent:
            @escaping @MainActor (
                BrowserSpaceRuntimeAssignment
            ) -> Bool,
        revealCredential: @escaping BrowserCredentialRevealer,
        writeClipboard: @escaping BrowserCredentialClipboardWriter,
        now: @escaping @MainActor () -> Date = { .now },
        sleep: @escaping @MainActor (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        request = BrowserCredentialDetailRequest(
            descriptor: descriptor,
            spaceAssignment: assignment,
            spaceName: spaceName
        )
        self.isAssignmentCurrent = isAssignmentCurrent
        self.revealCredential = revealCredential
        self.writeClipboard = writeClipboard
        self.now = now
        self.sleep = sleep
    }

    func toggleReveal() async {
        if visiblePassword != nil {
            revealLease = nil
            return
        }
        guard let token = beginAuthentication() else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performReveal(token: token)
        }
        activeOperationTask = task
        await task.value
        finishAuthentication(token: token)
    }

    func copy() async {
        guard let token = beginAuthentication() else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCopy(token: token)
        }
        activeOperationTask = task
        await task.value
        finishAuthentication(token: token)
    }

    func expireReveal(at expiration: Date) async {
        guard await waitUntil(expiration), !Task.isCancelled else { return }
        guard revealLease?.expiration == expiration else { return }
        revealLease = nil
    }

    func expireCopyConfirmation(at expiration: Date) async {
        guard await waitUntil(expiration), !Task.isCancelled else { return }
        guard copiedUntil == expiration else { return }
        copiedUntil = nil
    }

    func clearSensitiveState() {
        cancelActiveOperation()
        revealLease = nil
        copiedUntil = nil
        errorMessage = nil
    }

    private func performReveal(token: BrowserCredentialDetailOperationToken) async {
        do {
            let credential = try await revealCredential(
                descriptor.id,
                spaceAssignment,
                String(
                    localized: "Authenticate to reveal the Crest password for \(descriptor.origin.host)."
                )
            )
            guard !Task.isCancelled,
                activeOperationToken == token,
                isCurrent(token),
                credentialMatchesRequest(credential)
            else { return }
            revealLease = .reveal(
                password: credential.password,
                issuedAt: now()
            )
        } catch {
            guard !Task.isCancelled, activeOperationToken == token,
                isCurrent(token)
            else { return }
            handleAccessError(error)
        }
    }

    private func performCopy(token: BrowserCredentialDetailOperationToken) async {
        do {
            let credential = try await revealCredential(
                descriptor.id,
                spaceAssignment,
                String(
                    localized: "Authenticate to copy the Crest password for \(descriptor.origin.host)."
                )
            )
            guard !Task.isCancelled,
                activeOperationToken == token,
                isCurrent(token),
                credentialMatchesRequest(credential)
            else { return }
            let lease = BrowserCredentialSecretLease.clipboard(
                password: credential.password,
                issuedAt: now()
            )
            guard writeClipboard(lease) else {
                errorMessage = String(
                    localized: "Crest couldn’t copy that password."
                )
                return
            }
            copiedUntil = lease.expiration
        } catch {
            guard !Task.isCancelled, activeOperationToken == token,
                isCurrent(token)
            else { return }
            handleAccessError(error)
        }
    }

    private func beginAuthentication() -> BrowserCredentialDetailOperationToken? {
        guard !isAuthenticating,
            descriptor.spaceID == spaceAssignment.spaceID,
            isAssignmentCurrent(spaceAssignment)
        else {
            if !isAuthenticating {
                errorMessage = Self.accessFailureMessage
            }
            return nil
        }
        operationSequence &+= 1
        let token = BrowserCredentialDetailOperationToken(
            assignment: spaceAssignment,
            sequence: operationSequence
        )
        activeOperationToken = token
        isAuthenticating = true
        errorMessage = nil
        return token
    }

    private func finishAuthentication(
        token: BrowserCredentialDetailOperationToken
    ) {
        guard activeOperationToken == token else { return }
        activeOperationTask = nil
        activeOperationToken = nil
        isAuthenticating = false
    }

    private func cancelActiveOperation() {
        operationSequence &+= 1
        activeOperationTask?.cancel()
        activeOperationTask = nil
        activeOperationToken = nil
        isAuthenticating = false
    }

    private func isCurrent(
        _ token: BrowserCredentialDetailOperationToken
    ) -> Bool {
        token.assignment == spaceAssignment
            && activeOperationToken == token
            && isAssignmentCurrent(spaceAssignment)
    }

    private func credentialMatchesRequest(
        _ credential: BrowserCredential
    ) -> Bool {
        credential.descriptor.id == descriptor.id
            && credential.descriptor.spaceID == descriptor.spaceID
    }

    private func handleAccessError(_ error: Error) {
        guard !Self.isAuthenticationCancellation(error) else { return }
        errorMessage = Self.accessFailureMessage
    }

    private func waitUntil(_ date: Date) async -> Bool {
        let delay = max(0, date.timeIntervalSince(now()))
        do {
            try await sleep(.seconds(delay))
            return true
        } catch {
            return false
        }
    }

    private static var accessFailureMessage: String {
        String(
            localized: "Crest couldn’t authenticate and read that password from this Space."
        )
    }

    private static func isAuthenticationCancellation(_ error: Error) -> Bool {
        guard let error = error as? LAError else { return false }
        return switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            true
        default:
            false
        }
    }
}
