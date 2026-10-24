using CrestCore.Application;

namespace CrestCore.Contracts;

/// A question the engine raises with the person, or takes back, which its
/// `PromptId` names until the core settles it.
public abstract record PromptEvent(Guid PromptId) : EngineEvent {
    #region Abstract Methods

    /// Applies what `engine` reported about the prompt, publishing what the
    /// person is asked or what settled to `changes`, and handing an answer the
    /// core gives at once to `issue`.
    internal abstract void Apply(Prompts prompts, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue);

    #endregion

    #region Actions - Routing

    internal sealed override void Route(CrestApp app, Engine engine, ChangeFeed changes) =>
        app.Prompts.Report(this, engine, changes, app.Issue);

    #endregion
}
