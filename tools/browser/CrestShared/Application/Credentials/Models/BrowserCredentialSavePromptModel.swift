import Foundation
import Observation

/// Owns the platform-neutral save/update prompt lifecycle without retaining
/// the submitted secret. SwiftUI views keep the candidate page-owned and use
/// this model only for the decision and persistence phases.
@Observable
@MainActor
final class BrowserCredentialSavePromptModel {
    private(set) var phase: BrowserCredentialSavePromptPhase = .preparing
    private(set) var systemPasswordOfferPhase = BrowserSystemPasswordOfferPhase.notRequested

    @ObservationIgnored private var candidateID: UUID?

    var confirmationAction: BrowserCredentialSavePromptAction? {
        switch phase {
        case .create:
            .create
        case .update:
            .update
        case .saving(let action):
            action
        case .failed(.commit(let action)):
            action
        case .preparing, .alreadyStored, .saved, .failed(.preparation):
            nil
        }
    }

    var isBusy: Bool {
        if systemPasswordOfferPhase == .offering {
            return true
        }
        return switch phase {
        case .preparing, .saving:
            true
        case .create, .update, .alreadyStored, .saved, .failed:
            false
        }
    }

    var hasFailure: Bool {
        if case .failed = phase {
            return true
        }
        return false
    }

    func prepare(
        candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        browser: BrowserStore,
        now: Date = .now
    ) async {
        candidateID = candidate.id
        phase = .preparing
        systemPasswordOfferPhase = .notRequested
        do {
            let plan = try await browser.credentialSavePlan(
                for: candidate,
                in: spaceID,
                now: now
            )
            guard !Task.isCancelled, candidateID == candidate.id else { return }
            phase = plan.promptPhase
        } catch {
            guard !Task.isCancelled, candidateID == candidate.id else { return }
            phase = .failed(.preparation)
        }
    }

    func commit(
        candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        browser: BrowserStore,
        now: Date = .now
    ) async {
        guard candidateID == candidate.id else { return }
        let action: BrowserCredentialSavePromptAction
        switch phase {
        case .create:
            action = .create
        case .update:
            action = .update
        case .preparing, .alreadyStored, .saving, .saved, .failed:
            return
        }
        phase = .saving(action)
        do {
            let result = try await browser.commitCredentialSave(
                candidate,
                in: spaceID,
                now: now
            )
            guard !Task.isCancelled, candidateID == candidate.id else { return }
            phase = .saved(result.disposition)
        } catch {
            guard !Task.isCancelled, candidateID == candidate.id else { return }
            phase = .failed(.commit(action))
        }
    }

    func offerToSystemPasswords(
        _ offer: @MainActor () async throws -> Void
    ) async {
        guard case .saved = phase,
            systemPasswordOfferPhase != .offering,
            systemPasswordOfferPhase != .completed
        else {
            return
        }
        let expectedCandidateID = candidateID
        systemPasswordOfferPhase = .offering
        do {
            try await offer()
            guard !Task.isCancelled, candidateID == expectedCandidateID else { return }
            systemPasswordOfferPhase = .completed
        } catch is CancellationError {
            guard candidateID == expectedCandidateID else { return }
            systemPasswordOfferPhase = .notRequested
        } catch {
            guard candidateID == expectedCandidateID else { return }
            systemPasswordOfferPhase = .failed
        }
    }
}

/// Whether the prompt saves a new password or updates a saved one, with the
/// words for each.
struct BrowserCredentialSavePromptAction: Hashable, Sendable {
    // MARK: - Variables

    static let create = BrowserCredentialSavePromptAction(
        name: "create", promptTitle: "Save password?", offerTitle: "Save & Offer to Passwords",
        commitTitle: { spaceName in spaceName.map { "Save in \($0)" } ?? "Save in this Space" })
    static let update = BrowserCredentialSavePromptAction(
        name: "update", promptTitle: "Update password?", offerTitle: "Update & Offer to Passwords",
        commitTitle: { spaceName in spaceName.map { "Update in \($0)" } ?? "Update in this Space" })

    let name: String

    /// The prompt's question.
    let promptTitle: LocalizedStringResource

    /// The commit button's title when the save also offers the password to
    /// the system's Passwords app.
    let offerTitle: LocalizedStringResource

    /// The commit button's title, naming the Space the password is saved in.
    let commitTitle: @Sendable (_ spaceName: String?) -> LocalizedStringResource

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCredentialSavePromptAction, rhs: BrowserCredentialSavePromptAction) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

enum BrowserCredentialSavePromptFailure: Equatable, Sendable {
    case preparation
    case commit(BrowserCredentialSavePromptAction)
}

enum BrowserCredentialSavePromptPhase: Equatable, Sendable {
    case preparing
    case create
    case update
    case alreadyStored
    case saving(BrowserCredentialSavePromptAction)
    case saved(BrowserCredentialSaveDisposition)
    case failed(BrowserCredentialSavePromptFailure)
}

enum BrowserSystemPasswordOfferPhase: Equatable, Sendable {
    case notRequested
    case offering
    case completed
    case failed
}
