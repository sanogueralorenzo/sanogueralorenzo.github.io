import Foundation

/// The saved account `existing` already keeps the candidate's password:
/// there is nothing to save.
struct BrowserCredentialAlreadyStoredPlan: BrowserCredentialSavePlan {
    // MARK: - Variables

    let existing: CredentialDescriptor

    var promptPhase: BrowserCredentialSavePromptPhase { .alreadyStored }

    // MARK: - Actions - Committing

    func commit(
        _ candidate: BrowserCredentialSaveCandidate, in spaceID: UUID, now: Date, on store: BrowserStore
    ) async throws -> BrowserCredentialSaveResult {
        BrowserCredentialSaveResult(
            descriptor: existing,
            disposition: .unchanged
        )
    }
}
