import Foundation

/// The core's save plan for one candidate, carrying the descriptor it names.
/// Each plan commits the candidate its own way and says which prompt it asks
/// the person.
@MainActor
protocol BrowserCredentialSavePlan: Sendable {
    /// What the save prompt asks for this plan.
    var promptPhase: BrowserCredentialSavePromptPhase { get }

    /// Commits `candidate` in the Space `spaceID` at `now`, as this plan says.
    func commit(
        _ candidate: BrowserCredentialSaveCandidate, in spaceID: UUID, now: Date, on store: BrowserStore
    ) async throws -> BrowserCredentialSaveResult
}
