import Foundation

/// The candidate is a new account: saving adds it.
struct BrowserCredentialCreatePlan: BrowserCredentialSavePlan {
    // MARK: - Variables

    var promptPhase: BrowserCredentialSavePromptPhase { .create }

    // MARK: - Actions - Committing

    func commit(
        _ candidate: BrowserCredentialSaveCandidate, in spaceID: UUID, now: Date, on store: BrowserStore
    ) async throws -> BrowserCredentialSaveResult {
        let descriptor = try await store.saveCredential(
            candidate,
            in: spaceID,
            replacing: nil,
            now: now
        )
        return BrowserCredentialSaveResult(
            descriptor: descriptor,
            disposition: .created
        )
    }
}
