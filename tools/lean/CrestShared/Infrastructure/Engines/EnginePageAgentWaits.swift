import Foundation

/// What an agent's scripts and input wait for on one page: each evaluation and
/// each input by its identity, until the engine presents how it settled, the
/// wait runs out, or the page goes. Every wait ends exactly once.
@MainActor
struct EnginePageAgentWaits {
    // MARK: - Variables

    private var evaluations: [UUID: CheckedContinuation<PageScriptEvaluated?, Never>] = [:]
    private var inputs: [UUID: CheckedContinuation<PageInputDelivered?, Never>] = [:]

    // MARK: - Actions - Presentations

    /// Ends the wait for the evaluation the engine settled, if any waits for it.
    mutating func settle(_ evaluated: PageScriptEvaluated) {
        evaluations.removeValue(forKey: evaluated.evaluationID)?.resume(returning: evaluated)
    }

    /// Ends the wait for the input the engine delivered, if any waits for it.
    mutating func settle(_ delivered: PageInputDelivered) {
        inputs.removeValue(forKey: delivered.inputID)?.resume(returning: delivered)
    }

    // MARK: - Mutators

    mutating func wait(forEvaluation id: UUID, _ continuation: CheckedContinuation<PageScriptEvaluated?, Never>) {
        evaluations[id] = continuation
    }

    mutating func wait(forInput id: UUID, _ continuation: CheckedContinuation<PageInputDelivered?, Never>) {
        inputs[id] = continuation
    }

    /// Ends the wait for evaluation or input `id` empty-handed, when the
    /// engine refused it or took too long.
    mutating func expire(_ id: UUID) {
        evaluations.removeValue(forKey: id)?.resume(returning: nil)
        inputs.removeValue(forKey: id)?.resume(returning: nil)
    }

    /// The page went: every wait ends empty-handed.
    mutating func end() {
        let waitingEvaluations = evaluations
        let waitingInputs = inputs
        evaluations = [:]
        inputs = [:]
        for continuation in waitingEvaluations.values { continuation.resume(returning: nil) }
        for continuation in waitingInputs.values { continuation.resume(returning: nil) }
    }
}
