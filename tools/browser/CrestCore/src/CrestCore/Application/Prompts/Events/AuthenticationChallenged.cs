using CrestCore.Application;

namespace CrestCore.Contracts;

/// A server a page loads from asked for a user name and password; the load
/// waits for the core's `SettleAuthentication`.
public sealed record AuthenticationChallenged(Guid PromptId, Guid PageId, AuthenticationQuestion Question) : PromptEvent(PromptId) {
    #region Actions - Prompts

    internal override void Apply(Prompts prompts, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (prompts.Raised(engine, PromptId, PageId, Question, new SettleAuthentication(PromptId, Credential: null), issue))
            changes.Publish(new AuthenticationAsked(PromptId, PageId, Question));
    }

    #endregion
}
