import Foundation

@MainActor
final class BrowserHTTPAuthenticationSession {
    typealias LoadCredential =
        @MainActor (
            BrowserHTTPAuthenticationProtectionSpace
        ) async throws -> BrowserCredential?

    typealias SaveCredential =
        @MainActor (
            BrowserHTTPAuthenticationSaveRequest
        ) async throws -> Void

    typealias Prompt =
        @MainActor (
            BrowserHTTPAuthenticationPrompt
        ) async -> BrowserHTTPAuthenticationPromptResponse?

    private let loadCredential: LoadCredential
    private let saveCredential: SaveCredential
    private var allowsCredentialSaving: Bool
    let spaceID: UUID
    private var attemptedStoredCredential: BrowserCredential?
    private var attemptedProtectionSpace: BrowserHTTPAuthenticationProtectionSpace?
    private var pendingSaveRequest: BrowserHTTPAuthenticationSaveRequest?

    init(
        spaceID: UUID,
        allowsCredentialSaving: Bool = true,
        loadCredential: @escaping LoadCredential = { _ in nil },
        saveCredential: @escaping SaveCredential = { _ in }
    ) {
        self.spaceID = spaceID
        self.allowsCredentialSaving = allowsCredentialSaving
        self.loadCredential = loadCredential
        self.saveCredential = saveCredential
    }

    func setCredentialStorageEnabled(_ isEnabled: Bool) {
        guard allowsCredentialSaving != isEnabled else { return }
        allowsCredentialSaving = isEnabled
        reset()
    }

    func response(
        to challenge: BrowserAuthenticationChallenge,
        prompt: Prompt
    ) async -> BrowserHTTPAuthenticationDecision {
        await challenge.handling.respond(on: self)(challenge, prompt)
    }

    func authenticationSucceeded() async {
        guard let pendingSaveRequest else {
            reset()
            return
        }
        self.pendingSaveRequest = nil
        try? await saveCredential(pendingSaveRequest)
        reset()
    }

    func authenticationFailed() {
        reset()
    }

    private func passwordResponse(
        to challenge: BrowserAuthenticationChallenge,
        prompt: Prompt
    ) async -> BrowserHTTPAuthenticationDecision {
        guard let protectionSpace = challenge.protectionSpace else {
            return .performDefaultHandling
        }

        let rejectedCredential = rejectedCredential(
            for: protectionSpace,
            previousFailureCount: challenge.previousFailureCount
        )
        if allowsCredentialSaving,
            challenge.previousFailureCount == 0,
            protectionSpace.origin.isSecure,
            let stored = try? await loadCredential(protectionSpace)
        {
            attemptedStoredCredential = stored
            attemptedProtectionSpace = protectionSpace
            pendingSaveRequest = BrowserHTTPAuthenticationSaveRequest(
                protectionSpace: protectionSpace,
                username: stored.descriptor.username,
                password: stored.password,
                replacing: stored.descriptor
            )
            return credentialResolution(
                username: stored.descriptor.username,
                password: stored.password
            )
        }

        let response = await prompt(
            BrowserHTTPAuthenticationPrompt(
                descriptor: challenge.descriptor,
                suggestedUsername:
                    challenge.proposedUsername
                    ?? rejectedCredential?.descriptor.username,
                allowsSaving:
                    allowsCredentialSaving && protectionSpace.origin.isSecure
            )
        )
        guard let response else {
            authenticationFailed()
            return .cancel
        }

        if allowsCredentialSaving,
            response.shouldSave,
            protectionSpace.origin.isSecure
        {
            let replacing =
                rejectedCredential?.descriptor.username == response.username
                ? rejectedCredential?.descriptor
                : nil
            pendingSaveRequest = BrowserHTTPAuthenticationSaveRequest(
                protectionSpace: protectionSpace,
                username: response.username,
                password: response.password,
                replacing: replacing
            )
        } else {
            pendingSaveRequest = nil
        }
        attemptedStoredCredential = nil
        attemptedProtectionSpace = nil
        return credentialResolution(
            username: response.username,
            password: response.password
        )
    }

    private func rejectedCredential(
        for protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        previousFailureCount: Int
    ) -> BrowserCredential? {
        guard previousFailureCount > 0,
            attemptedProtectionSpace == protectionSpace
        else {
            return nil
        }
        let rejected = attemptedStoredCredential
        attemptedStoredCredential = nil
        attemptedProtectionSpace = nil
        pendingSaveRequest = nil
        return rejected
    }

    private func credentialResolution(
        username: String,
        password: String
    ) -> BrowserHTTPAuthenticationDecision {
        .useCredential(username: username, password: password)
    }

    private func reset() {
        attemptedStoredCredential = nil
        attemptedProtectionSpace = nil
        pendingSaveRequest = nil
    }
}

// MARK: - Actions - Responding

extension BrowserHTTPAuthenticationSession: AuthenticationResponder {
    /// The session's answer to a challenge, which it finishes with the
    /// challenge and the prompt that may ask the person.
    typealias Response =
        @MainActor (BrowserAuthenticationChallenge, Prompt) async -> BrowserHTTPAuthenticationDecision

    func performDefaultHandling() -> Response {
        { _, _ in .performDefaultHandling }
    }

    func cancelChallenge() -> Response {
        { [self] _, _ in
            authenticationFailed()
            return .cancel
        }
    }

    func promptForCredentials() -> Response {
        { [self] challenge, prompt in
            await passwordResponse(to: challenge, prompt: prompt)
        }
    }
}
