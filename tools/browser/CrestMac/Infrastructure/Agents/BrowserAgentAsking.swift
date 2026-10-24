import Foundation

// MARK: - Types

/// An agent asking to remove every visit to `address` from the history of the
/// Space named `spaceName`, as the person is asked about it: by the name they
/// allowed the agent under.
struct BrowserAgentHistoryDeletion: Equatable, Sendable {
    let agentName: String
    let address: String
    let spaceName: String
}

/// An agent asking to open a window of `kind`, over the Space named
/// `spaceName` and at `address` where it gives them, as the person is asked.
struct BrowserAgentWindowOpening: Equatable, Sendable {
    let agentName: String
    let kind: BrowserAgentWindowKind
    let spaceName: String?
    let address: String?
}

/// How the person answered an agent's question: no, yes this once, or yes
/// for as long as that connection lasts.
struct BrowserAgentAnswer: Equatable, Sendable {
    static let declined = Self(allows: false, lasts: false)
    static let once = Self(allows: true, lasts: false)
    static let whileConnected = Self(allows: true, lasts: true)

    let allows: Bool
    /// The connection may do it again without asking.
    let lasts: Bool
}

/// What asks the person about agents: Crest's dialogs, or a test that answers
/// for them. A `dismissal` closes a question unanswered, which declines.
@MainActor
protocol BrowserAgentAsking: AnyObject {
    func approveAgent(_ agent: BrowserAgentPeer.Program, client: AgentClientInfo?, dismissal: BrowserPromptDismissal?)
        async -> Bool
    func approveHistoryDeletion(_ deletion: BrowserAgentHistoryDeletion, dismissal: BrowserPromptDismissal?) async
        -> Bool
    func approveWindow(_ opening: BrowserAgentWindowOpening, dismissal: BrowserPromptDismissal?) async
        -> BrowserAgentAnswer
}

extension BrowserDialogPresenter: BrowserAgentAsking {}
