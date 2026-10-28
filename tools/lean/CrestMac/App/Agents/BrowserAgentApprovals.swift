import Foundation

/// The person's answers to agents asking to use Crest, or to delete history:
/// one question on screen at a time, an agent that asks to connect again while
/// it is asked about waits for the same answer, and at most `maximumWaiting`
/// questions wait to be asked. A question closes unanswered once every
/// connection waiting on it is gone, and turning agents off closes them all.
@MainActor
final class BrowserAgentApprovals {
    // MARK: - Types

    /// One open question, and the connections waiting on its answer. Only a
    /// question about connecting names an agent, which a later connection of
    /// that agent shares.
    private final class Asking {
        let identity: AgentIdentity?
        let dismissal: BrowserPromptDismissal
        var waiters: Set<ObjectIdentifier>
        var answer: Task<BrowserAgentAnswer, Never>?

        init(identity: AgentIdentity?, dismissal: BrowserPromptDismissal, waiter: ObjectIdentifier) {
            self.identity = identity
            self.dismissal = dismissal
            waiters = [waiter]
        }
    }

    // MARK: - Static Variables

    static let maximumWaiting = 4

    // MARK: - Variables

    private let dialogs: any BrowserAgentAsking
    private var asking: [Asking] = []
    /// The question asked last, which the next one waits for.
    private var last: Task<Void, Never>?

    // MARK: - Initializers

    init(asking dialogs: any BrowserAgentAsking = BrowserDialogPresenter()) {
        self.dialogs = dialogs
    }

    // MARK: - Actions - Questions

    /// Returns once the person allowed `agent` for the connection `waiter`,
    /// asking them when no question about it is open. Throws `declined` when
    /// they did not, and `busy` when too many agents already wait.
    func approve(_ agent: BrowserAgentPeer.Program, client: AgentClientInfo?, for waiter: ObjectIdentifier)
        async throws(BrowserAgentFailure)
    {
        if let open = asking.first(where: { $0.identity == agent.identity }), let answer = open.answer {
            open.waiters.insert(waiter)
            guard await answer.value.allows else { throw .declined }
            return
        }
        let answer = try await ask(about: agent.identity, for: waiter) { [dialogs] dismissal in
            await dialogs.approveAgent(agent, client: client, dismissal: dismissal) ? .once : .declined
        }
        guard answer.allows else { throw .declined }
    }

    /// Returns once the person let the connection `waiter` make `deletion`.
    /// Throws `historyKept` when they did not, and `busy` when too many
    /// questions already wait.
    func approve(_ deletion: BrowserAgentHistoryDeletion, for waiter: ObjectIdentifier)
        async throws(BrowserAgentFailure)
    {
        let answer = try await ask(about: nil, for: waiter) { [dialogs] dismissal in
            await dialogs.approveHistoryDeletion(deletion, dismissal: dismissal) ? .once : .declined
        }
        guard answer.allows else { throw .historyKept }
    }

    /// Returns how the person let the connection `waiter` make `opening`.
    /// Throws `windowDeclined` when they did not, and `busy` when too many
    /// questions already wait.
    func approve(_ opening: BrowserAgentWindowOpening, for waiter: ObjectIdentifier)
        async throws(BrowserAgentFailure) -> BrowserAgentAnswer
    {
        let answer = try await ask(about: nil, for: waiter) { [dialogs] dismissal in
            await dialogs.approveWindow(opening, dismissal: dismissal)
        }
        guard answer.allows else { throw .windowDeclined }
        return answer
    }

    /// Asks `question` once the questions before it are answered, and answers
    /// declined when it closes unanswered.
    private func ask(
        about identity: AgentIdentity?, for waiter: ObjectIdentifier,
        _ question: @escaping @MainActor (BrowserPromptDismissal) async -> BrowserAgentAnswer
    ) async throws(BrowserAgentFailure) -> BrowserAgentAnswer {
        guard asking.count < Self.maximumWaiting else { throw .busy }
        let dismissal = BrowserPromptDismissal()
        let open = Asking(identity: identity, dismissal: dismissal, waiter: waiter)
        let earlier = last
        let answer = Task {
            await earlier?.value
            guard !dismissal.isDismissed else { return BrowserAgentAnswer.declined }
            let answer = await question(dismissal)
            return dismissal.isDismissed ? .declined : answer
        }
        open.answer = answer
        asking.append(open)
        last = Task { _ = await answer.value }
        let answered = await answer.value
        asking.removeAll { $0 === open }
        return answered
    }

    /// Stops the connection `waiter` waiting, closing unanswered any question
    /// no other connection waits on.
    func withdraw(_ waiter: ObjectIdentifier) {
        for question in asking where question.waiters.remove(waiter) != nil && question.waiters.isEmpty {
            question.dismissal.dismiss()
        }
    }

    /// Closes every open question unanswered.
    func dismissAll() {
        for question in asking { question.dismissal.dismiss() }
    }
}
