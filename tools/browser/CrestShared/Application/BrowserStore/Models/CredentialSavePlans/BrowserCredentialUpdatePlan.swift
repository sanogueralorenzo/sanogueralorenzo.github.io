import Foundation

/// The candidate changes the password of the saved account `existing`:
/// saving replaces it, keeping its identity.
struct BrowserCredentialUpdatePlan: BrowserCredentialSavePlan {
    // MARK: - Variables

    let existing: CredentialDescriptor

    var promptPhase: BrowserCredentialSavePromptPhase { .update }

    // MARK: - Actions - Committing

    func commit(
        _ candidate: BrowserCredentialSaveCandidate, in spaceID: UUID, now: Date, on store: BrowserStore
    ) async throws -> BrowserCredentialSaveResult {
        let descriptor = try await store.saveCredential(
            candidate,
            in: spaceID,
            replacing: existing,
            now: now
        )
        return BrowserCredentialSaveResult(
            descriptor: descriptor,
            disposition: .updated
        )
    }
}
