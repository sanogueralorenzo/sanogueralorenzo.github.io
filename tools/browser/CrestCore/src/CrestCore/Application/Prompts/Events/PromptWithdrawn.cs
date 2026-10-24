using CrestCore.Application;

namespace CrestCore.Contracts;

/// The engine no longer waits for a prompt's answer: the page moved on, or
/// what asked went away.
public sealed record PromptWithdrawn(Guid PromptId) : PromptEvent(PromptId) {
    #region Actions - Prompts

    /// Only the engine that asked withdraws a prompt.
    internal override void Apply(Prompts prompts, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (prompts.WaitingPrompts.TryGetValue(PromptId, out var prompt) && ReferenceEquals(prompt.Engine, engine))
            prompts.Settle(PromptId, changes);
    }

    #endregion
}
